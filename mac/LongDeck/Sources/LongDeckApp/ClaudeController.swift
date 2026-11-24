import AppKit
import Foundation
import LongDeckCore
import Security

@MainActor
final class ClaudeController: ObservableObject {
    @Published private(set) var installed = false
    @Published private(set) var statusText = "Claude: not installed"

    var onBody: ((String) -> Void)?
    private(set) var currentBody = ""

    private var store = ClaudeStore(runTag: String(UUID().uuidString.prefix(4)).lowercased())
    private var listener: ClaudeListener?
    private var listenerError: String?
    private var timer: Timer?
    private var lastPublished: String?
    private var inFlight = Set<String>()
    private let clockOrigin = ContinuousClock.now
    private let responder = ClaudeResponder(
        runner: ProcessTmuxRunner(), frontTTY: { OSAScript.frontTTY() },
        activateTerminal: { OSAScript.activate($0) }
    )

    private var monotonic: TimeInterval {
        let d = clockOrigin.duration(to: ContinuousClock.now)
        return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }

    func start() {
        if let state = ClaudeInstaller.loadState(Self.livePaths()) {
            installed = true
            startListener(token: state.token)
        }
        publish()
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func install() {
        let paths = Self.livePaths()
        let alert = NSAlert()
        alert.messageText = "Install Claude Code integration"
        alert.informativeText = "LongDeck will add HTTP hooks to ~/.claude/settings.json next to your existing hooks, "
            + "and run your status line (\(Self.currentStatusLine(paths.settings))) through a small wrapper. "
            + "A backup is saved next to the file. Restart running Claude Code sessions afterwards."
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let token = try Self.makeToken()
            let state = try ClaudeInstaller.install(paths, token: token, now: Date())
            installed = true
            startListener(token: state.token)
            publish()
        } catch {
            showError(error)
        }
    }

    func uninstall() {
        let alert = NSAlert()
        alert.messageText = "Uninstall Claude Code integration"
        alert.informativeText = "LongDeck will remove its hooks and restore your status line."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        listener?.stop()
        listener = nil
        listenerError = nil
        do {
            try ClaudeInstaller.uninstall(Self.livePaths(), now: Date())
            installed = false
        } catch {
            showError(error)
        }
        store = ClaudeStore(runTag: String(UUID().uuidString.prefix(4)).lowercased())
        inFlight = []
        publish()
    }

    func handleAction(_ body: String, reply: @escaping (String) -> Void) {
        guard let req = ClaudeActionRequest.parse(body) else {
            NSLog("LongDeck: dropped unparsable claude_action")
            return
        }
        let session = store.sessions[req.session]
        let target = session.map {
            ClaudeTarget(pane: $0.pane, pendingRequest: $0.pending?.request, toolName: $0.pending?.toolName,
                         toolInputJSON: $0.pending?.toolInputJSON, cwd: $0.cwd)
        }
        let responder = responder
        Task { @MainActor [weak self] in
            let ack = await Task.detached { responder.handle(req, target: target) }.value
            guard let self else { return }
            if ack.ok {
                switch req.action {
                case .approve, .always:
                    store.resolve(session: req.session, request: req.request, state: .working, now: monotonic)
                case .deny:
                    store.resolve(session: req.session, request: req.request, state: .waiting, now: monotonic)
                case .interrupt, .focus:
                    break
                }
            }
            publish()
            reply(ack.body)
        }
    }

    private func startListener(token: String) {
        listener?.stop()
        listenerError = nil
        let l = ClaudeListener(port: UInt16(ClaudeInstaller.port), token: token) { [weak self] inbound in
            self?.receive(inbound)
        }
        l.onFailure = { [weak self] _ in self?.listenerFailed() }
        listener = l
        l.start { [weak self] result in
            if case .failure = result { self?.listenerFailed() }
        }
    }

    private func listenerFailed() {
        listenerError = "Claude: listener failed (port \(ClaudeInstaller.port) busy?)"
        refreshStatus()
    }

    private func receive(_ inbound: ClaudeInbound) {
        switch inbound.channel {
        case .hook:
            guard let event = ClaudeHookEvent.decode(inbound.body) else { return }
            store.apply(event, pane: inbound.pane, now: monotonic)
        case .statusLine:
            guard let update = ClaudeStatusUpdate.decode(inbound.body) else { return }
            store.apply(update, pane: inbound.pane, now: monotonic)
        }
        publish()
    }

    private func tick() {
        store.expire(now: monotonic, wall: Date())
        for (session, pending) in store.pendingPrompts() {
            guard let pane = session.pane, inFlight.insert(pending.request).inserted else { continue }
            let (sessionId, request) = (session.id, pending.request)
            let responder = responder
            Task { @MainActor [weak self] in
                let visible = await Task.detached { responder.promptVisible(pane: pane) }.value
                guard let self else { return }
                inFlight.remove(request)
                store.promptCheck(session: sessionId, request: request, visible: visible, now: monotonic)
                publish()
            }
        }
        publish()
    }

    private func publish() {
        currentBody = store.body(now: Date())
        refreshStatus()
        guard currentBody != lastPublished else { return }
        lastPublished = currentBody
        onBody?(currentBody)
    }

    private func refreshStatus() {
        let text: String
        if let listenerError {
            text = listenerError
        } else if installed {
            text = "Claude: \(store.sessions.count) sessions"
        } else {
            text = "Claude: not installed"
        }
        if text != statusText { statusText = text }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Claude Code integration failed"
        alert.informativeText = "\(error)"
        alert.runModal()
    }

    private static func livePaths() -> ClaudeInstallPaths {
        let fm = FileManager.default
        return ClaudeInstallPaths(
            settings: fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json"),
            supportDir: fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("LongDeck")
        )
    }

    private static func currentStatusLine(_ settings: URL) -> String {
        guard let data = try? Data(contentsOf: settings),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let line = root["statusLine"] as? [String: Any],
              let command = line["command"] as? String, !command.isEmpty
        else { return "none" }
        return command
    }

    private static func makeToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw ClaudeInstallError.writeFailed("could not generate a token")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

private enum OSAScript {
    static func frontTTY() -> String? {
        let script = #"tell application "iTerm2" to get tty of current session of current window"#
        guard let out = run(["-e", script]) else { return nil }
        let tty = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return tty.isEmpty ? nil : tty
    }

    static func activate(_ tty: String?) {
        if let tty {
            let script = """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                select w
                                select t
                                select s
                                activate
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
            if run(["-e", script]) != nil { return }
        }
        DispatchQueue.main.async {
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2").first?.activate()
        }
    }

    private static func run(_ args: [String], timeout: TimeInterval = 2) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = args
        process.standardInput = FileHandle.nullDevice
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { return nil }
        guard exited.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}
