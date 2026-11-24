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

    @Test func issueStableIdsDiffer() {
        let s = withNewKey()
        let ids = s.issues.map(\.stableId)
        #expect(Set(ids).count == ids.count)
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
