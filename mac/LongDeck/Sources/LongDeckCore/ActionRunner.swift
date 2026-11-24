import CoreGraphics
import Foundation

public enum ActionError: Error, Equatable {
    case notTrusted
    case unknownKey(String)
    case failed(String)
}

public struct ActionRunner: Sendable {
    public let system: SystemControl

    public init(system: SystemControl) {
        self.system = system
    }

    public func run(_ action: DeckAction) throws {
        switch action {
        case .openApp(let path):
            try system.openApp(path: path)
        case .openURL(let string):
            guard let url = URL(string: string) else { throw ActionError.failed("bad URL \(string)") }
            try system.openURL(url)
        case .hotkey(let keyCode, let modifiers):
            try requireTrust()
            try system.postKey(code: keyCode, flags: Self.flags(modifiers))
        case .media(let key):
            try requireTrust()
            try system.postSystemKey(Self.nx(key))
        case .volume(let key):
            try requireTrust()
            try system.postSystemKey(Self.nx(key))
        case .typeText(let text):
            try requireTrust()
            try system.typeText(text)
        case .shell(let cmd):
            try system.runShell(cmd)
        case .shortcut(let name):
            try system.runShortcut(name)
        }
    }

    public func handlePress(id: String, kind: String, config: DeckConfig) throws {
        guard let key = config.pages.lazy.flatMap(\.keys).first(where: { $0.id == id }) else {
            throw ActionError.unknownKey(id)
        }
        if kind == "long" {
            if let long = key.longAction { try run(long) }
        } else {
            try run(key.action)
        }
    }

    private func requireTrust() throws {
        guard system.isTrusted else { throw ActionError.notTrusted }
    }

    private static func flags(_ modifiers: [KeyModifier]) -> CGEventFlags {
        var flags: CGEventFlags = []
        for m in modifiers {
            switch m {
            case .command: flags.insert(.maskCommand)
            case .shift: flags.insert(.maskShift)
            case .option: flags.insert(.maskAlternate)
            case .control: flags.insert(.maskControl)
            }
        }
        return flags
    }

    private static func nx(_ key: MediaKey) -> Int32 {
        switch key {
        case .playPause: return 16
        case .next: return 17
        case .previous: return 18
        }
    }

    private static func nx(_ key: VolumeKey) -> Int32 {
        switch key {
        case .up: return 0
        case .down: return 1
        case .mute: return 7
        }
    }
}
