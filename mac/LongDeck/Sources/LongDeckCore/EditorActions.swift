public enum ActionSlot: String, Sendable { case primary, long }

public enum ActionKind: String, CaseIterable, Sendable {
    case openApp, openURL, hotkey, media, volume, typeText, shell, shortcut

    public static let unsetKeyCode: UInt16 = 0xFFFF

    public init(_ action: DeckAction) {
        switch action {
        case .openApp: self = .openApp
        case .openURL: self = .openURL
        case .hotkey: self = .hotkey
        case .media: self = .media
        case .volume: self = .volume
        case .typeText: self = .typeText
        case .shell: self = .shell
        case .shortcut: self = .shortcut
        }
    }

    public var title: String {
        switch self {
        case .openApp: return "Open app"
        case .openURL: return "Open URL"
        case .hotkey: return "Hotkey"
        case .media: return "Media key"
        case .volume: return "Volume"
        case .typeText: return "Type text"
        case .shell: return "Shell command"
        case .shortcut: return "Shortcut"
        }
    }

    public var defaultAction: DeckAction {
        switch self {
        case .openApp: return .openApp(path: "")
        case .openURL: return .openURL("")
        case .hotkey: return .hotkey(keyCode: Self.unsetKeyCode, modifiers: [])
        case .media: return .media(.playPause)
        case .volume: return .volume(.mute)
        case .typeText: return .typeText("")
        case .shell: return .shell("")
        case .shortcut: return .shortcut("")
        }
    }
}
