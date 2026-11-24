import LongDeckCore
import SwiftUI

struct ActionEditorView: View {
    @ObservedObject var store: EditorStore
    let keyId: String
    let slot: ActionSlot

    init(store: EditorStore, keyId: String, slot: ActionSlot) {
        self.store = store
        self.keyId = keyId
        self.slot = slot
    }

    private var current: DeckAction? {
        guard case .key(let key)? = store.model.widget(keyId) else { return nil }
        return slot == .primary ? key.action : key.longAction
    }

    private var coalesceKey: String { "action-\(slot.rawValue)-\(keyId)" }

    private func set(_ action: DeckAction, coalesce: String? = nil) {
        store.setAction(action, slot: slot, for: keyId, coalesce: coalesce)
    }

    private var kindBinding: Binding<ActionKind> {
        Binding(
            get: { current.map(ActionKind.init) ?? .openApp },
            set: { kind in
                guard kind != current.map(ActionKind.init) else { return }
                set(kind.defaultAction)
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Action", selection: kindBinding) {
                ForEach(ActionKind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            editor
        }
    }

    @ViewBuilder private var editor: some View {
        switch current {
        case .openApp(let path)?:
            AppChooser(path: path) { store.chooseApp($0, slot: slot, for: keyId) }
        case .openURL(let url)?:
            TextField("https://…", text: text(url) { .openURL($0) })
                .textFieldStyle(.roundedBorder)
        case .hotkey(let code, let mods)?:
            HotkeyRecorderView(keyCode: code, modifiers: mods) { set($0) }
                .frame(width: 180, height: 24)
        case .media(let key)?:
            Picker("Key", selection: Binding(get: { key }, set: { set(.media($0)) })) {
                Text("Play/Pause").tag(MediaKey.playPause)
                Text("Next").tag(MediaKey.next)
                Text("Previous").tag(MediaKey.previous)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        case .volume(let key)?:
            Picker("Key", selection: Binding(get: { key }, set: { set(.volume($0)) })) {
                Text("Up").tag(VolumeKey.up)
                Text("Down").tag(VolumeKey.down)
                Text("Mute").tag(VolumeKey.mute)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        case .typeText(let value)?:
            TextField("Text to type", text: text(value) { .typeText($0) }, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
        case .shell(let value)?:
            VStack(alignment: .leading, spacing: 4) {
                TextField("Command", text: text(value) { .shell($0) }, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                caption("Runs with /bin/zsh -lc. Output is discarded.")
            }
        case .shortcut(let name)?:
            VStack(alignment: .leading, spacing: 4) {
                TextField("Shortcut name", text: text(name) { .shortcut($0) })
                    .textFieldStyle(.roundedBorder)
                caption("Runs the macOS Shortcut with this name.")
            }
        case nil:
            EmptyView()
        }
    }

    private func text(_ value: String, make: @escaping (String) -> DeckAction) -> Binding<String> {
        Binding(get: { value }, set: { set(make($0), coalesce: coalesceKey) })
    }

    private func caption(_ string: String) -> some View {
        Text(string).font(.caption).foregroundColor(.secondary)
    }
}
