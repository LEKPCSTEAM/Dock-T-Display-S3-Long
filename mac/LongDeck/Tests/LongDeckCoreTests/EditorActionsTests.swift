import Testing
@testable import LongDeckCore

@Suite struct EditorActionsTests {
    @Test func kindRoundTrip() {
        for k in ActionKind.allCases {
            #expect(ActionKind(k.defaultAction) == k)
        }
        let expected: [String: ActionKind] = [
            "vscode": .openApp, "github": .openURL, "spotlight": .hotkey, "prev": .media,
            "mute": .volume, "text": .typeText, "work": .shell, "shortcut": .shortcut,
        ]
        let keys = SampleConfig.dev.pages[0].keys
        for (id, kind) in expected {
            let key = keys.first { $0.id == id }
            #expect(key.map { ActionKind($0.action) } == kind)
        }
    }

    @Test func defaultsTable() {
        let rows: [(ActionKind, String, DeckAction)] = [
            (.openApp, "Open app", .openApp(path: "")),
            (.openURL, "Open URL", .openURL("")),
            (.hotkey, "Hotkey", .hotkey(keyCode: 0xFFFF, modifiers: [])),
            (.media, "Media key", .media(.playPause)),
            (.volume, "Volume", .volume(.mute)),
            (.typeText, "Type text", .typeText("")),
            (.shell, "Shell command", .shell("")),
            (.shortcut, "Shortcut", .shortcut("")),
        ]
        #expect(ActionKind.allCases.count == rows.count)
        for (kind, title, action) in rows {
            #expect(kind.title == title)
            #expect(kind.defaultAction == action)
        }
        #expect(ActionKind.unsetKeyCode == 0xFFFF)
    }
}
