import Foundation
import Testing
@testable import LongDeckCore

@Suite struct AppCatalogTests {
    private func makeRoot() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.path
        let real = realpath(tmp, nil).map { String(cString: $0) } ?? tmp
        let url = URL(fileURLWithPath: real)
            .appendingPathComponent("longdeck-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func makeApp(_ url: URL, info: [String: String]? = nil) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if let info {
            let contents = url.appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try data.write(to: contents.appendingPathComponent("Info.plist"))
        }
        return url
    }

    private func makeFixture() throws -> URL {
        let t = try makeRoot().appendingPathComponent("T")
        let fm = FileManager.default
        try fm.createDirectory(at: t, withIntermediateDirectories: true)
        try makeApp(t.appendingPathComponent("A.app"), info: ["CFBundleName": "Alpha"])
        try makeApp(t.appendingPathComponent("b.app"))
        try makeApp(t.appendingPathComponent("Utilities/C.app"), info: ["CFBundleDisplayName": "Cee"])
        try makeApp(t.appendingPathComponent("Nested.app/Contents/Plug.app"))
        try makeApp(t.appendingPathComponent(".Hidden.app"))
        try Data().write(to: t.appendingPathComponent("notes.txt"))
        try makeApp(t.appendingPathComponent("Deep/More/D.app"))
        return t
    }

    private func scanSync(_ roots: [AppRoot]) -> [AppEntry] { AppCatalog.scan(roots) }

    private func triple(_ e: AppEntry) -> [String] { [e.name, e.path, e.folder] }

    @Test func scanFindsAppsOneLevelDeep() throws {
        let t = try makeFixture()
        let found = AppCatalog.scan([AppRoot(url: t, label: "Test")])
        #expect(found.map(triple) == [
            ["Alpha", t.appendingPathComponent("A.app").path, "Test"],
            ["b", t.appendingPathComponent("b.app").path, "Test"],
            ["Cee", t.appendingPathComponent("Utilities/C.app").path, "Test/Utilities"],
            ["Nested", t.appendingPathComponent("Nested.app").path, "Test"],
        ])
    }

    @Test func scanFollowsAppSymlinksAndDedupes() throws {
        let t = try makeFixture()
        let t2 = try makeRoot().appendingPathComponent("T2")
        try FileManager.default.createDirectory(at: t2, withIntermediateDirectories: true)
        let link = t2.appendingPathComponent("Link.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: t.appendingPathComponent("A.app"))
        let alone = AppCatalog.scan([AppRoot(url: t2, label: "Test2")])
        #expect(alone.count == 1)
        #expect(alone.first?.path == link.path)
        #expect(alone.first?.folder == "Test2")
        let both = AppCatalog.scan([AppRoot(url: t, label: "Test"), AppRoot(url: t2, label: "Test2")])
        #expect(!both.contains { $0.path == link.path })
        #expect(both.count == 4)
    }

    @Test func asyncScanMatchesSync() async throws {
        let t = try makeFixture()
        let roots = [AppRoot(url: t, label: "Test")]
        let sync = scanSync(roots)
        let off = await AppCatalog.scan(roots)
        #expect(off == sync)
        #expect(off.count == 4)
    }

    @Test func missingRootIsSkipped() throws {
        let missing = try makeRoot().appendingPathComponent("nope")
        #expect(AppCatalog.scan([AppRoot(url: missing, label: "X")]).isEmpty)
    }

    @Test func filterByName() throws {
        let t = try makeFixture()
        let apps = AppCatalog.scan([AppRoot(url: t, label: "Test")])
        #expect(AppCatalog.filter(apps, query: "al").map(\.name) == ["Alpha"])
        #expect(AppCatalog.filter(apps, query: "  ").count == apps.count)
        #expect(AppCatalog.filter(apps, query: "zz").isEmpty)
    }

    @Test func entryForOpenPanelPick() throws {
        let t = try makeFixture()
        let entry = AppCatalog.entry(forApp: t.appendingPathComponent("Utilities/C.app"))
        #expect(entry?.name == "Cee")
        #expect(entry?.folder == "Utilities")
    }

    @Test func systemAppsAreFound() {
        let path = "/System/Applications/Calculator.app"
        let found = AppCatalog.scan([AppRoot(url: URL(fileURLWithPath: "/System/Applications"), label: "System")])
        let entry = found.first { $0.path == path }
        #expect(entry != nil)
        #expect(entry?.name.isEmpty == false)
        #expect(entry?.name == AppCatalog.name(forPath: path))
    }
}
