import CoreGraphics
import Foundation
import LongDeckCore
import SwiftUI
import Testing
@testable import LongDeckEditor

@Suite(.serialized) @MainActor struct InspectorSnapshotTests {
    private let calculator = AppEntry(name: "Calculator", path: "/System/Applications/Calculator.app",
                                      folder: "System")

    private func store() -> EditorStore {
        EditorStore(config: SampleConfig.dev, onDisk: true, diskError: nil, appRoots: [], environment: .permissive)
    }

    private func snap<V: View>(_ view: V, _ size: CGSize, _ name: String) throws {
        let rep = Snapshot.render(view.background(Color(nsColor: .windowBackgroundColor)), size: size)
        #expect(rep.pixelsWide == Int(size.width * 2))
        #expect(rep.pixelsHigh == Int(size.height * 2))
        #expect(!Snapshot.isUniform(rep))
        try Snapshot.save(rep, name)
    }

    @Test func inspectorPage() throws {
        try snap(InspectorView(store: store()), CGSize(width: 320, height: 420), "inspector-page")
    }

    @Test func inspectorAppKey() throws {
        let s = store()
        s.select("vscode")
        s.chooseApp(calculator, slot: .primary, for: "vscode")
        s.setAction(.media(.playPause), slot: .long, for: "vscode", coalesce: nil)
        #expect(s.model.widget("vscode") != nil)
        try snap(InspectorView(store: s), CGSize(width: 320, height: 760), "inspector-key-app")
    }

    @Test func inspectorHotkeyKey() throws {
        let s = store()
        s.select("screenshot")
        try snap(InspectorView(store: s), CGSize(width: 320, height: 760), "inspector-key-hotkey")
    }

    @Test func inspectorErrorKey() throws {
        let s = store()
        s.selectPage(2)
        #expect(s.add(.key) != nil)
        try snap(InspectorView(store: s), CGSize(width: 320, height: 760), "inspector-key-error")
    }

    @Test func inspectorStat() throws {
        let s = store()
        s.selectPage(1)
        s.select("cpu")
        #expect(s.model.selection == "cpu")
        try snap(InspectorView(store: s), CGSize(width: 320, height: 420), "inspector-stat")
    }

    @Test func appPicker() throws {
        let tool = AppEntry(name: "Tool", path: "/tmp/longdeck-tests-fake/Tool.app", folder: "Test")
        let calendar = AppEntry(name: "Calendar", path: "/System/Applications/Calendar.app", folder: "System")
        let state = AppPickerState()
        state.query = "cal"
        let view = AppPickerView(apps: [calculator, calendar, tool], state: state, onPick: { _ in }, onCancel: {})
        try snap(view, CGSize(width: 420, height: 480), "app-picker")
    }

    @Test func hotkeyRecorderStates() throws {
        let view = VStack(alignment: .leading, spacing: 12) {
            HotkeyRecorderView(keyCode: 21, modifiers: [.command, .shift]) { _ in }
            HotkeyRecorderView(keyCode: ActionKind.unsetKeyCode, modifiers: []) { _ in }
        }
        .padding(12)
        .frame(width: 420, height: 80, alignment: .topLeading)
        try snap(view, CGSize(width: 420, height: 80), "hotkey-recorder")
    }
}
