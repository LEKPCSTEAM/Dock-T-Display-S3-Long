import AppKit
import CoreGraphics
import Foundation
import LongDeckCore
import SwiftUI
import Testing
@testable import LongDeckEditor

@Suite(.serialized) @MainActor struct EditorSnapshotTests {
    private func store(onDisk: Bool = true, diskError: String? = nil) -> EditorStore {
        EditorStore(config: SampleConfig.dev, onDisk: onDisk, diskError: diskError, appRoots: [],
                    environment: .permissive)
    }

    private func snap<V: View>(_ view: V, _ size: CGSize, _ name: String) throws {
        let rep = Snapshot.render(view.background(Color(nsColor: .windowBackgroundColor)), size: size)
        #expect(rep.pixelsWide == Int(size.width * 2))
        #expect(rep.pixelsHigh == Int(size.height * 2))
        #expect(!Snapshot.isUniform(rep))
        try Snapshot.save(rep, name)
    }

    private func withNewKey() -> EditorStore {
        let s = store()
        s.selectPage(2)
        #expect(s.add(.key) != nil)
        return s
    }

    @Test func editorFull() throws {
        let s = withNewKey()
        try snap(EditorView(store: s), CGSize(width: 1440, height: 760), "editor-full")
    }

    @Test func editorExternalConflict() throws {
        let s = withNewKey()
        var theirs = SampleConfig.dev
        theirs.pages[0].name = "Theirs"
        s.externalChange(theirs)
        #expect(s.externalConflict)
        try snap(EditorView(store: s), CGSize(width: 1440, height: 760), "editor-external-conflict")
    }

    @Test func editorDiskError() throws {
        let s = store(onDisk: false, diskError: "Invalid deck config: duplicate widget id a")
        try snap(EditorView(store: s), CGSize(width: 1440, height: 760), "editor-disk-error")
    }

    @Test func pageList() throws {
        try snap(PageListView(store: withNewKey()), CGSize(width: 200, height: 360), "pages")
    }

    @Test func undoRoutingSkipsTextEditing() {
        #expect(UndoRouting.storeHandlesUndo(firstResponder: nil))
        #expect(UndoRouting.storeHandlesUndo(firstResponder: NSView()))
        #expect(!UndoRouting.storeHandlesUndo(firstResponder: NSTextView()))
    }

    @Test func deleteRoutingSkipsTextEditing() {
        #expect(DeleteRouting.removesWidget(firstResponder: nil))
        #expect(DeleteRouting.removesWidget(firstResponder: NSView()))
        #expect(!DeleteRouting.removesWidget(firstResponder: NSTextView()))
    }

    @Test func issueStableIdsDiffer() {
        let s = withNewKey()
        let ids = s.issues.map(\.stableId)
        #expect(Set(ids).count == ids.count)
    }

    @Test func identicalIssuesGetUniqueRowIds() {
        let issue = EditorIssue(severity: .error, page: 0, widget: "a", message: "same")
        let rows = IssueListView.identified([issue, issue, issue])
        #expect(Set(rows.map(\.id)).count == 3)
    }

    @Test func saveRunsAfterResignOnNextTurn() {
        var log: [String] = []
        var pending: (() -> Void)?
        SaveCommit.run(resign: { log.append("resign") },
                       schedule: { pending = $0 },
                       save: { log.append("save") })
        #expect(log == ["resign"])
        pending?()
        #expect(log == ["resign", "save"])
    }

    @Test func issueListReveal() {
        let s = withNewKey()
        s.selectPage(0)
        #expect(!s.issues.isEmpty)
        s.reveal(s.issues[0])
        #expect(s.model.pageIndex == 2)
        #expect(s.model.selection != nil)
    }
}
