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
        #expect(!guardRecord.matches(a))
        guardRecord.recordWrite(a)
        #expect(guardRecord.matches(a))
        #expect(guardRecord.matches(a))
        #expect(!guardRecord.matches(b))
        guardRecord.recordWrite(b)
        #expect(!guardRecord.matches(a))
    }
}
