import Combine
import Foundation
import LongDeckCore
import Testing
@testable import LongDeckEditor

@Suite @MainActor struct EditorStoreTests {
    private func blank() -> DeckConfig {
        DeckConfig(version: 1, pages: [PageConfig(name: "A", keys: [])])
    }

    private func makeRoot() throws -> (URL, [AppRoot]) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("longdeck-tests-\(UUID().uuidString)", isDirectory: true)
        let tool = root.appendingPathComponent("Tool.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: tool, withIntermediateDirectories: true)
        return (root, [AppRoot(url: root, label: "Test")])
    }

    private func store(_ config: DeckConfig? = nil, onDisk: Bool = true, diskError: String? = nil,
                       roots: [AppRoot] = []) -> EditorStore {
        EditorStore(config: config ?? blank(), onDisk: onDisk, diskError: diskError,
                    appRoots: roots, environment: .permissive)
    }

    @Test func addPublishesAndRecomputesIssues() {
        let s = EditorStore(config: blank(), onDisk: true, diskError: nil, appRoots: [], environment: .permissive)
        var fired = 0
        let sub = s.objectWillChange.sink { fired += 1 }
        let id = s.add(.key)
        #expect(fired > 0)
        #expect(id != nil)
        #expect(s.issues.contains { $0.widget == id && $0.message.contains("Choose an app") })
        #expect(s.issues(forWidget: id!).count >= 1)
        sub.cancel()
    }

    @Test func canSaveNeedsDirtyAndNoErrors() {
        let clean = store(SampleConfig.dev)
        #expect(!clean.canSave)
        let ok = store(SampleConfig.dev)
        ok.selectPage(2)
        #expect(ok.add(.clock) != nil)
        let clock = ok.model.page.live.last
        #expect(clock?.col == 6 && clock?.row == 1)
        #expect(ok.canSave)
        let bad = store(SampleConfig.dev)
        bad.selectPage(2)
        bad.add(.key)
        #expect(!bad.canSave)
    }

    @Test func saveSentMarksClean() {
        let s = store()
        s.add(.clock)
        var received: DeckConfig?
        s.onSave = { received = $0; return .sent }
        #expect(s.save())
        #expect(received == s.model.document)
        #expect(!s.isDirty)
        #expect(s.status == "Saved. Sending to the board.")
    }

    @Test func saveFailedStaysDirty() {
        let s = store()
        s.add(.clock)
        s.onSave = { _ in .failed("disk full") }
        #expect(!s.save())
        #expect(s.status == "Not saved: disk full")
        #expect(s.isDirty)
    }

    @Test func saveBlockedByErrors() {
        let s = store()
        s.add(.key)
        var called = false
        s.onSave = { _ in called = true; return .sent }
        #expect(!s.save())
        #expect(!called)
        #expect(s.status.hasPrefix("Fix 1 error"))
    }

    @Test func invalidDiskOpensDirty() {
        let s = store(onDisk: false, diskError: "x")
        #expect(s.isDirty)
        #expect(s.status.contains("x"))
        s.onSave = { _ in .savedOffline }
        #expect(s.save())
        #expect(s.diskError == nil)
        #expect(s.status == "Saved. The board updates when it connects.")
    }

    @Test func externalChangeWhenCleanReplaces() {
        let s = store()
        let other = DeckConfig(version: 1, pages: [PageConfig(name: "B", keys: [])])
        s.externalChange(other)
        #expect(s.model.document.pages.first?.name == "B")
        #expect(s.status.isEmpty)
    }

    @Test func appsScannedOnce() throws {
        let (root, roots) = try makeRoot()
        let s = store(roots: roots)
        #expect(s.apps.contains { $0.name == "Tool" })
        try FileManager.default.removeItem(at: root)
        #expect(s.apps.contains { $0.name == "Tool" })
    }

    @Test func revealSelectsPageAndWidget() {
        let s = store(SampleConfig.dev)
        s.selectPage(2)
        let id = s.add(.key)!
        s.selectPage(0)
        let issue = s.issues.first { $0.widget == id }!
        s.reveal(issue)
        #expect(s.model.pageIndex == 2)
        #expect(s.model.selection == id)
    }

    @Test func failedPlacementSetsStatus() {
        let s = store()
        for _ in 0..<16 { s.add(.key) }
        #expect(s.add(.key) == nil)
        #expect(s.status == "No room there")
        let id = s.model.page.keys[0].id
        #expect(!s.setFrame(id, CellRect(col: 7, row: 1, w: 3, h: 1)))
        #expect(s.status == "No room there")
        #expect(s.setFrame(id, CellRect(col: 0, row: 0, w: 1, h: 1)))
        #expect(s.status.isEmpty)
    }
}
