import Foundation
import Testing
@testable import LongDeckCore

@Suite struct ConfigSaverTests {
    private func digits(_ n: Int, width: Int) -> String {
        let s = String(n)
        return String(repeating: "0", count: max(0, width - s.count)) + s
    }

    private func fullStatPages(_ n: Int) -> DeckConfig {
        var pages: [PageConfig] = []
        for p in 0..<n {
            var live: [LiveWidgetConfig] = []
            for i in 0..<16 {
                live.append(LiveWidgetConfig(
                    id: "s" + digits(p * 16 + i, width: 14), col: i % 8, row: i / 8, w: 1, h: 1,
                    kind: .stat(.diskFree, .sparkline)))
            }
            pages.append(PageConfig(name: "P" + digits(p, width: 22), keys: [], live: live))
        }
        return DeckConfig(version: 1, pages: pages)
    }

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("longdeck-tests-\(UUID().uuidString)")
    }

    @Test func sampleFits() throws {
        #expect(try ConfigSaver.prepare(SampleConfig.dev) == (try SampleConfig.dev.fileData()))
        #expect(LayoutSize.sealedBytes(SampleConfig.dev) < 15360)
    }

    @Test func sealedBytesMatchesSealer() {
        let json = LayoutBuilder.build(SampleConfig.dev, render: { _ in Data() }).json
        var sealer = FrameSealer(sessionKey: Data(count: 32))
        let expected = sealer.seal(type: "layout", body: json).utf8.count + 9
        #expect(LayoutSize.sealedBytes(SampleConfig.dev) == expected)
    }

    @Test func sixFullStatPagesFit() throws {
        _ = try ConfigSaver.prepare(fullStatPages(6))
    }

    @Test func sevenFullStatPagesTooLarge() {
        do {
            _ = try ConfigSaver.prepare(fullStatPages(7))
            Issue.record("expected layoutTooLarge")
        } catch let error as ConfigSaveError {
            guard case .layoutTooLarge(let bytes, let max) = error else {
                Issue.record("wrong case")
                return
            }
            #expect(bytes > 15360)
            #expect(max == 15360)
            #expect(error.description.contains("\(bytes)"))
            #expect(error.description.contains("15360"))
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func invalidConfigRejected() {
        func key(_ id: String) -> KeyConfig {
            KeyConfig(id: id, col: 0, row: 0, w: 1, h: 1, label: id, icon: nil,
                      background: "#000000", action: .hotkey(keyCode: 0, modifiers: []), longAction: nil)
        }
        let a = key("a")
        let b = key("b")
        let config = DeckConfig(version: 1, pages: [PageConfig(name: "P", keys: [a, b])])
        #expect(throws: DeckConfigError.self) { try ConfigSaver.prepare(config) }
    }

    @Test func writeIsAtomicAndCreatesFolder() throws {
        let root = tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("a/b/config.json")
        try ConfigSaver.write(Data("one".utf8), to: url)
        #expect(try Data(contentsOf: url) == Data("one".utf8))
        try ConfigSaver.write(Data("two".utf8), to: url)
        #expect(try Data(contentsOf: url) == Data("two".utf8))
        let files = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        #expect(files == ["config.json"])
    }

    @Test func writeGuardMatchesOwnBytes() {
        let a = Data("A".utf8)
        let b = Data("B".utf8)
        var guardRecord = ConfigWriteGuard()
        let fresh = guardRecord.matches(a)
        guardRecord.recordWrite(a)
        let other = guardRecord.matches(b)
        let own = guardRecord.matches(a)
        let again = guardRecord.matches(a)
        guardRecord.recordWrite(b)
        guardRecord.recordWrite(a)
        let replaced = guardRecord.matches(b)
        #expect(!fresh && !other && own && !again && !replaced)
    }

    @Test func externalRevertToSavedBytesIsNotIgnored() {
        let a = Data("A".utf8)
        let b = Data("B".utf8)
        var guardRecord = ConfigWriteGuard()
        guardRecord.recordWrite(a)
        let ownEcho = guardRecord.matches(a)
        let externalEdit = guardRecord.matches(b)
        let externalRevert = guardRecord.matches(a)
        #expect(ownEcho && !externalEdit && !externalRevert)
    }

    @Test func writeGuardExpiresAndResets() {
        let a = Data("A".utf8)
        let t0 = Date(timeIntervalSince1970: 1000)
        var late = ConfigWriteGuard()
        late.recordWrite(a, at: t0)
        let expired = late.matches(a, at: t0.addingTimeInterval(ConfigWriteGuard.window + 0.1))
        var soon = ConfigWriteGuard()
        soon.recordWrite(a, at: t0)
        let inTime = soon.matches(a, at: t0.addingTimeInterval(0.5))
        var cleared = ConfigWriteGuard()
        cleared.recordWrite(a, at: t0)
        cleared.reset()
        let afterReset = cleared.matches(a, at: t0)
        #expect(!expired && inTime && !afterReset)
    }

    private func mode(_ url: URL) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    @Test func existingModeIsPreserved() throws {
        let root = tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("config.json")
        try ConfigSaver.write(Data("one".utf8), to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: url.path)
        try ConfigSaver.write(Data("two".utf8), to: url)
        #expect(try mode(url) == 0o640)
    }

    @Test func newFileGets0644() throws {
        let root = tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("x/config.json")
        try ConfigSaver.write(Data("one".utf8), to: url)
        #expect(try mode(url) == 0o644)
    }

    @Test func symlinkIsKeptAndTargetUpdated() throws {
        let root = tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("real"), withIntermediateDirectories: true)
        let target = root.appendingPathComponent("real/config.json")
        try Data("one".utf8).write(to: target)
        let link = root.appendingPathComponent("config.json")
        try fm.createSymbolicLink(at: link, withDestinationURL: target)
        try ConfigSaver.write(Data("two".utf8), to: link)
        #expect((try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil)
        #expect(try Data(contentsOf: target) == Data("two".utf8))
    }

    @Test func failureLeavesOldFileIntact() throws {
        let root = tempDir()
        let fm = FileManager.default
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? fm.removeItem(at: root)
        }
        let url = root.appendingPathComponent("config.json")
        try ConfigSaver.write(Data("old".utf8), to: url)
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        #expect(throws: (any Error).self) { try ConfigSaver.write(Data("new".utf8), to: url) }
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        #expect(try Data(contentsOf: url) == Data("old".utf8))
        #expect(try fm.contentsOfDirectory(atPath: root.path) == ["config.json"])
    }
}
