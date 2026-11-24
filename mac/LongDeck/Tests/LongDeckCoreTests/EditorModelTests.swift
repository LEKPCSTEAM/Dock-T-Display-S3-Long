import Foundation
import Testing
@testable import LongDeckCore

@Suite struct EditorModelTests {
    private func blankConfig() -> DeckConfig {
        DeckConfig(version: 1, pages: [PageConfig(name: "A", keys: [])])
    }

    private func blank() -> EditorModel {
        EditorModel(document: blankConfig(), saved: blankConfig())
    }

    private func yes(_ value: Bool) { #expect(value) }
    private func no(_ value: Bool) { #expect(!value) }
    private func eq<T: Equatable>(_ a: T, _ b: T) { #expect(a == b) }

    private func frame(_ m: EditorModel, _ id: String) -> CellRect? { m.widget(id)?.frame }

    private func fifteenKeys() -> EditorModel {
        var m = blank()
        for _ in 0..<15 { m.add(.key) }
        return m
    }

    private func key(_ m: EditorModel, _ id: String) -> KeyConfig? {
        if case .key(let k)? = m.widget(id) { return k }
        return nil
    }

    @Test func initAddsPageToEmptyDocument() {
        let m = EditorModel(document: DeckConfig(version: 1, pages: []), saved: nil)
        #expect(m.document.pages.map(\.name) == ["Page 1"])
        #expect(m.isDirty)
    }

    @Test func addKeyAtFirstFreeSpot() {
        var m = blank()
        eq(m.add(.key), "key")
        #expect(frame(m, "key") == CellRect(col: 0, row: 0, w: 1, h: 1))
        #expect(m.selection == "key")
        #expect(m.isDirty)
        eq(m.add(.key), "key2")
        #expect(frame(m, "key2") == CellRect(col: 1, row: 0, w: 1, h: 1))
    }

    @Test func addUsesDefaultSizes() {
        var m = blank()
        eq(m.add(.stat), "cpu")
        #expect(frame(m, "cpu") == CellRect(col: 0, row: 0, w: 2, h: 1))
        #expect(m.page.live[0].kind == .stat(.cpu, .sparkline))
        var v = blank()
        v.add(.volume)
        #expect(frame(v, "volume")?.w == 3)
        var c = blank()
        c.add(.clock)
        #expect(frame(c, "clock")?.w == 2)
        var s = blank()
        let id = s.add(.claudeSessions)!
        #expect(frame(s, id) == CellRect(col: 0, row: 0, w: 4, h: 2))
        let usage = s.add(.claudeUsage)!
        #expect(frame(s, usage) == CellRect(col: 4, row: 0, w: 4, h: 1))
    }

    @Test func addFallsBackToMinSizeThenFails() {
        var m = fifteenKeys()
        let id = m.add(.stat)
        #expect(id != nil)
        #expect(frame(m, id!) == CellRect(col: 7, row: 1, w: 1, h: 1))
        eq(m.add(.key), nil)
        #expect(!m.canAdd(.key))
        var f = fifteenKeys()
        #expect(f.canAdd(.stat))
        eq(f.add(.claudeSessions), nil)
    }

    @Test func addAtCellShiftsIntoGrid() {
        var m = blank()
        let u = m.add(.claudeUsage, col: 6, row: 1)!
        #expect(frame(m, u) == CellRect(col: 4, row: 1, w: 4, h: 1))
        var a = blank()
        a.add(.key, col: 1, row: 0)
        let s = a.add(.stat, col: 0, row: 0)!
        #expect(frame(a, s) == CellRect(col: 0, row: 0, w: 1, h: 1))
        var b = blank()
        b.add(.key, col: 0, row: 0)
        eq(b.add(.stat, col: 0, row: 0), nil)
    }

    @Test func idsUniqueAcrossPages() {
        var m = blank()
        m.add(.key)
        m.addPage()
        eq(m.add(.key), "key2")
    }

    @Test func setFrameChecksBoundsAndCollisions() {
        var m = blank()
        m.add(.key)
        yes(m.setFrame("key", CellRect(col: 7, row: 0, w: 1, h: 1)))
        no(m.setFrame("key", CellRect(col: 8, row: 0, w: 1, h: 1)))
        no(m.setFrame("key", CellRect(col: 7, row: 0, w: 2, h: 1)))
        m.add(.key)
        let other = CellRect(col: 7, row: 0, w: 1, h: 1)
        no(m.setFrame("key2", other))
        m.undo()
        m.undo()
        m.add(.key)
        let current = frame(m, "key")!
        yes(m.setFrame("key", CellRect(col: 3, row: 0, w: 1, h: 1)))
        m.undo()
        #expect(frame(m, "key") == current)
        let undoable = m.canUndo
        yes(m.setFrame("key", current))
        #expect(m.canUndo == undoable)
        var s = blank()
        let id = s.add(.claudeSessions)!
        no(s.setFrame(id,CellRect(col: 0, row: 0, w: 1, h: 2)))
    }

    @Test func removeClearsSelection() {
        var m = blank()
        m.add(.key)
        yes(m.remove("key"))
        #expect(m.selection == nil)
        #expect(m.widget("key") == nil)
        no(m.remove("key"))
    }

    @Test func pagesAddRemoveMoveRename() {
        var m = blank()
        m.addPage()
        m.addPage()
        #expect(m.document.pages.map(\.name) == ["A", "Page 2", "Page 3"])
        m.renamePage(at: 2, to: "Page 4")
        m.addPage()
        #expect(m.document.pages.last?.name == "Page 5")
        while m.addPage() {}
        #expect(m.document.pages.count == 8)
        no(m.addPage())
        var one = blank()
        no(one.removePage(at: 0))

        var p = EditorModel(document: DeckConfig(version: 1, pages: ["A", "B", "C"].map {
            PageConfig(name: $0, keys: [])
        }), saved: nil)
        yes(p.movePage(from: 0, to: 2))
        #expect(p.document.pages.map(\.name) == ["B", "C", "A"])
        #expect(p.pageIndex == 2)
        yes(p.movePage(from: 2, to: 0))
        #expect(p.document.pages.map(\.name) == ["A", "B", "C"])
        no(p.movePage(from: 1, to: 1))
        no(p.movePage(from: 0, to: 5))

        p.renamePage(at: 0, to: "ทดสอบภาษาไทยยาว")
        #expect(p.document.pages[0].name == "ทดสอบภา")
        p.renamePage(at: 0, to: String(repeating: "x", count: 30))
        #expect(p.document.pages[0].name == String(repeating: "x", count: 23))
    }

    @Test func removePageKeepsCurrentPage() {
        var m = EditorModel(document: DeckConfig(version: 1, pages: ["A", "B", "C"].map {
            PageConfig(name: $0, keys: [])
        }), saved: nil)
        m.selectPage(2)
        yes(m.removePage(at: 0))
        #expect(m.pageIndex == 1)
        #expect(m.page.name == "C")
        yes(m.removePage(at: 1))
        #expect(m.pageIndex == 0)
    }

    @Test func updateKeyCannotChangeIdOrFrame() {
        var m = blank()
        m.add(.key)
        m.updateKey("key") { $0.id = "x"; $0.col = 5; $0.label = "Hi" }
        let k = key(m, "key")!
        #expect(k.label == "Hi")
        #expect(k.col == 0)
        #expect(m.widget("x") == nil)
    }

    @Test func chooseAppSetsIconAndLabel() {
        let calc = AppEntry(name: "Calculator", path: "/System/Applications/Calculator.app", folder: "System")
        let notes = AppEntry(name: "Notes", path: "/System/Applications/Notes.app", folder: "System")
        let safari = AppEntry(name: "Safari", path: "/Applications/Safari.app", folder: "Applications")
        var m = blank()
        m.add(.key)
        m.chooseApp(calc, slot: .primary, for: "key")
        var k = key(m, "key")!
        #expect(k.action == .openApp(path: calc.path))
        #expect(k.icon == .app(path: calc.path))
        #expect(k.label == "Calculator")
        m.updateKey("key") { $0.label = "Calc" }
        m.chooseApp(notes, slot: .primary, for: "key")
        k = key(m, "key")!
        #expect(k.label == "Calc")
        #expect(k.icon == .app(path: notes.path))
        #expect(k.action == .openApp(path: notes.path))
        m.updateKey("key") { $0.label = "Notes" }
        m.chooseApp(safari, slot: .primary, for: "key")
        #expect(key(m, "key")!.label == "Safari")
        m.chooseApp(calc, slot: .long, for: "key")
        k = key(m, "key")!
        #expect(k.longAction == .openApp(path: calc.path))
        #expect(k.label == "Safari")
        #expect(k.icon == .app(path: safari.path))

        var u = blank()
        u.add(.key)
        u.markSaved()
        u.chooseApp(calc, slot: .primary, for: "key")
        u.undo()
        #expect(!u.isDirty)
    }

    @Test func setActionSlots() {
        var m = blank()
        m.add(.key)
        m.setAction(.shell("ls"), slot: .long, for: "key")
        #expect(key(m, "key")!.longAction == .shell("ls"))
        m.setAction(nil, slot: .long, for: "key")
        #expect(key(m, "key")!.longAction == nil)
        let before = key(m, "key")!.action
        m.setAction(nil, slot: .primary, for: "key")
        #expect(key(m, "key")!.action == before)
        m.setAction(.typeText("x"), slot: .primary, for: "key")
        #expect(key(m, "key")!.action == .typeText("x"))
    }

    @Test func setStatOnlyForStats() {
        var m = blank()
        m.add(.key)
        m.add(.stat)
        no(m.setStat("key", metric: .ram, style: .bar))
        yes(m.setStat("cpu", metric: .ram, style: .bar))
        #expect(m.page.live[0].kind == .stat(.ram, .bar))
    }

    @Test func undoRedoRestoresDocumentAndSelection() {
        var m = blank()
        m.add(.key)
        m.setFrame("key", CellRect(col: 3, row: 0, w: 1, h: 1))
        m.undo()
        #expect(frame(m, "key") == CellRect(col: 0, row: 0, w: 1, h: 1))
        #expect(m.selection == "key")
        m.undo()
        #expect(m.widget("key") == nil)
        #expect(m.selection == nil)
        m.redo()
        m.redo()
        #expect(frame(m, "key")?.col == 3)
        m.undo()
        #expect(m.canRedo)
        m.add(.key)
        #expect(!m.canRedo)
    }

    @Test func typingCoalescesIntoOneStep() {
        var m = blank()
        m.add(.key)
        for text in ["a", "ab", "abc"] { m.updateKey("key", coalesce: "label-key") { $0.label = text } }
        m.undo()
        #expect(key(m, "key")!.label == "Key")

        var n = blank()
        n.add(.key)
        n.updateKey("key", coalesce: "label-key") { $0.label = "a" }
        n.updateKey("key", coalesce: "label-key") { $0.label = "ab" }
        n.select(nil)
        n.select("key")
        n.updateKey("key", coalesce: "label-key") { $0.label = "abc" }
        n.undo()
        #expect(key(n, "key")!.label == "ab")
        n.undo()
        #expect(key(n, "key")!.label == "Key")
    }

    @Test func undoLimitIs100() {
        var m = blank()
        m.add(.key)
        for i in 0..<105 { m.setFrame("key", CellRect(col: (i % 2) + 1, row: 0, w: 1, h: 1)) }
        var count = 0
        while m.canUndo { m.undo(); count += 1 }
        #expect(count == 100)
    }

    @Test func dirtyFollowsSavedBaseline() {
        var m = blank()
        #expect(!m.isDirty)
        m.add(.key)
        #expect(m.isDirty)
        m.undo()
        #expect(!m.isDirty)
        m.add(.key)
        m.markSaved()
        #expect(!m.isDirty)
        m.undo()
        #expect(m.isDirty)
    }

    @Test func externalChangeRules() {
        var other = blankConfig()
        other.pages[0].name = "Z"
        var clean = blank()
        clean.externalChange(other)
        #expect(clean.document == other)
        #expect(!clean.canUndo)
        #expect(!clean.isDirty)

        var dirty = blank()
        dirty.add(.key)
        let doc = dirty.document
        dirty.externalChange(other)
        #expect(dirty.document == doc)
        dirty.externalChange(doc)
        #expect(!dirty.isDirty)
    }

    @Test func markSavedEndsCoalescing() {
        var m = blank()
        m.add(.key)
        m.markSaved()
        m.updateKey("key", coalesce: "label") { $0.label = "a" }
        m.markSaved()
        m.updateKey("key", coalesce: "label") { $0.label = "ab" }
        m.undo()
        #expect(!m.isDirty)
        #expect(key(m, "key")?.label == "a")
    }

    @Test func matchesSavedComparesBaseline() {
        var m = blank()
        #expect(m.matchesSaved(blankConfig()))
        m.add(.key)
        #expect(m.matchesSaved(blankConfig()))
        #expect(!m.matchesSaved(m.document))
    }

    @Test func switchingAppsReplacesBundleNameLabel() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("longdeck-tests-\(UUID().uuidString)", isDirectory: true)
        let contents = root.appendingPathComponent("Terminal Thing.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleName": "iTerm2"], format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("Terminal Thing.app").path
        let term = AppEntry(name: AppCatalog.name(forPath: path), path: path, folder: "Test")
        let chrome = AppEntry(name: "Chrome", path: "/Applications/Google Chrome.app", folder: "Applications")
        var m = blank()
        m.add(.key)
        m.chooseApp(term, slot: .primary, for: "key")
        #expect(key(m, "key")?.label == "iTerm2")
        m.chooseApp(chrome, slot: .primary, for: "key")
        #expect(key(m, "key")?.label == "Chrome")
    }

    @Test func selectionStaysOnCurrentPage() {
        var m = blank()
        m.add(.key)
        m.addPage()
        m.select("key")
        #expect(m.selection == nil)
        m.selectPage(0)
        m.select("key")
        #expect(m.selection == "key")
        m.selectPage(0)
        #expect(m.selection == nil)
    }

    @Test func noOpEditsAddNoUndoStep() {
        var m = blank()
        m.add(.key)
        m.markSaved()
        var fresh = EditorModel(document: m.document, saved: m.document)
        fresh.select("key")
        fresh.updateKey("key") { $0.label = "Key" }
        #expect(!fresh.canUndo)
    }
}
