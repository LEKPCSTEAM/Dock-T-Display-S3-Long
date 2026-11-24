import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public protocol SystemControl: Sendable {
    func openApp(path: String) throws
    func openURL(_ url: URL) throws
    func postKey(code: UInt16, flags: CGEventFlags) throws
    func postSystemKey(_ nx: Int32) throws
    func typeText(_ s: String) throws
    func runShell(_ cmd: String) throws
    func runShortcut(_ name: String) throws
    var isTrusted: Bool { get }
}

public struct RealSystemControl: SystemControl {
    public init() {}

    public var isTrusted: Bool { AXIsProcessTrusted() }

    public func openApp(path: String) throws {
        guard NSWorkspace.shared.open(URL(fileURLWithPath: path)) else {
            throw ActionError.failed("cannot open \(path)")
        }
    }

    public func openURL(_ url: URL) throws {
        guard NSWorkspace.shared.open(url) else { throw ActionError.failed("cannot open \(url)") }
    }

    public func postKey(code: UInt16, flags: CGEventFlags) throws {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else {
                throw ActionError.failed("cannot create key event")
            }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }

    public func postSystemKey(_ nx: Int32) throws {
        for (down, state) in [(true, 0xA), (false, 0xB)] {
            let data1 = Int((nx << 16) | Int32(state << 8))
            guard let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, data1: data1, data2: -1),
                let cg = event.cgEvent
            else { throw ActionError.failed("cannot create system key event (down=\(down))") }
            cg.post(tap: .cghidEventTap)
        }
    }

    public func typeText(_ s: String) throws {
        let units = Array(s.utf16)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else {
                throw ActionError.failed("cannot create key event")
            }
            event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            event.post(tap: .cghidEventTap)
        }
    }

    public func runShell(_ cmd: String) throws {
        try launch("/bin/zsh", ["-lc", cmd])
    }

    public func runShortcut(_ name: String) throws {
        try launch("/usr/bin/shortcuts", ["run", name])
    }

    private func launch(_ path: String, _ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw ActionError.failed("\(error.localizedDescription)") }
    }
}
