import AppKit
import Foundation
import LongDeckCore
import Security

@MainActor
final class ClaudeController: ObservableObject {
    @Published private(set) var installed = false
    @Published private(set) var statusText = "Claude: not installed"
    @Published private(set) var hooksCurrent = true

    var onBody: ((String) -> Void)?
    private(set) var currentBody = ""
    private static let emptyBody = #"{"prompt":null,"sessions":[],"usage":{"five_hour":null,"seven_day":null}}"#

    private var store = ClaudeStore(runTag: String(UUID().uuidString.prefix(4)).lowercased())
    private let names = ClaudeNames(runner: ProcessTmuxRunner())
    private var listener: ClaudeListener?
    private var listening = false
    private var listenerError: String?
    private var timer: Timer?
    private var lastPublished: String?
    private var inFlight = Set<String>()
    private var actionRequests = Set<String>()
    private var busyPanes = Set<String>()
    private var listenerToken: String?
    private var retryTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
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
        store.history = ClaudeHistory.load(from: Self.historyURL)
        if let state = ClaudeInstaller.loadState(Self.livePaths()) {
            installed = true
            hooksCurrent = ClaudeInstaller.isCurrent(Self.livePaths())
            startListener(token: state.token)
        }
        publish()
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.restartListener() }
            }
        }
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
        alert.informativeText = "LongDeck will add command hooks to ~/.claude/settings.json next to your existing hooks "
            + "(they run a small script that only reports events), "
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
            hooksCurrent = ClaudeInstaller.isCurrent(paths)
            startListener(token: state.token)
            publish()
            let done = NSAlert()
            done.messageText = "Claude Code integration installed"
            done.informativeText = "Backup saved at \(state.backupPath ?? "(none, settings.json did not exist)"). "
                + "Restart running Claude Code sessions."
            done.runModal()
        } catch {
            showError(error)
        }
    }

    func uninstall() {
        let alert = NSAlert()
        alert.messageText = "Uninstall Claude Code integration"
        alert.informativeText = "LongDeck will remove its hooks and restore your status line. "
            + "Restart running Claude Code sessions afterwards: until then they keep calling the removed hook script "
            + "and may show hook errors."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try ClaudeInstaller.uninstall(Self.livePaths(), now: Date())
        } catch {
            showError(error)
            return
        }
        listener?.stop()
        listener = nil
        listening = false
        listenerToken = nil
        retryTask?.cancel()
        listenerError = nil
        installed = false
        hooksCurrent = true
        let kept = store.history
        store = ClaudeStore(runTag: String(UUID().uuidString.prefix(4)).lowercased())
        store.history = kept
        inFlight = []
        publish()
    }

    func handleAction(_ body: String, reply: @escaping (String) -> Void) {
        guard let req = ClaudeActionRequest.parse(body) else {
            let object = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any]
            if let request = object?["request"] as? String, !request.isEmpty {
                reply(ClaudeAck(request: request, ok: false, reason: "proto").body)
            } else {
                NSLog("LongDeck: dropped unparsable claude_action")
            }
            return
        }
        let session = store.sessions[req.session]
        let pane = session?.pane
        if actionRequests.contains(req.request) && !req.request.isEmpty || pane.map(busyPanes.contains) == true {
            reply(ClaudeAck(request: req.request, ok: false, reason: "busy").body)
            return
        }
        actionRequests.insert(req.request)
        if let pane { busyPanes.insert(pane) }
        let target = store.target(session: req.session)
        let responder = responder
        Task { @MainActor [weak self] in
            let ack = await Task.detached { responder.handle(req, target: target) }.value
            guard let self else { return }
            actionRequests.remove(req.request)
            if let pane { busyPanes.remove(pane) }
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
        listenerToken = token
        let l = ClaudeListener(port: UInt16(ClaudeInstaller.port), token: token) { [weak self] inbound in
            self?.receive(inbound)
        }
        l.onFailure = { [weak self, weak l] _ in self?.listenerFailed(l) }
        listener = l
        l.start { [weak self, weak l] result in
            guard let self, self.listener === l else { return }
            switch result {
            case .success:
                listenerError = nil
                listening = true
                publish()
            case .failure:
                listenerFailed(l)
            }
        }
    }

    private func restartListener() {
        guard let token = listenerToken else { return }
        retryTask?.cancel()
        startListener(token: token)
    }

    private func listenerFailed(_ failed: ClaudeListener?) {
        guard failed === listener else { return }
        listenerError = "Claude: listener failed (port \(ClaudeInstaller.port) busy?)"
        listening = false
        publish()
        retryTask?.cancel()
        retryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.restartListener()
        }
    }

    private func receive(_ inbound: ClaudeInbound) {
        switch inbound.channel {
        case .hook:
            guard let event = ClaudeHookEvent.decode(inbound.body) else { return }
            store.apply(event, pane: inbound.pane, now: monotonic)
            if let pane = inbound.pane { lookUpName(pane: pane, session: event.sessionId) }
        case .statusLine:
            guard let update = ClaudeStatusUpdate.decode(inbound.body) else { return }
            store.apply(update, pane: inbound.pane, now: monotonic)
        }
        persistHistory()
        publish()
    }

    private func lookUpName(pane: String, session: String) {
        let (names, now) = (names, monotonic)
        Task { @MainActor [weak self] in
            let name = await Task.detached { names.name(forPane: pane, now: now) }.value
            guard let self, let name else { return }
            store.setName(name, forSession: session)
            publish()
        }
    }

    private func persistHistory() {
        guard store.historyChanged else { return }
        store.historyChanged = false
        store.history.prune(now: Date().timeIntervalSince1970)
        try? FileManager.default.createDirectory(
            at: Self.historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        do { try store.history.save(to: Self.historyURL) } catch { NSLog("LongDeck: history save failed: \(error)") }
    }

    private func tick() {
        store.expire(now: monotonic, wall: Date())
        persistHistory()
        for (session, pending) in store.pendingPrompts() {
            guard let pane = session.pane, !busyPanes.contains(pane), inFlight.insert(pending.request).inserted else { continue }
            let (sessionId, request) = (session.id, pending.request)
            guard let target = store.target(session: sessionId) else { inFlight.remove(request); continue }
            let responder = responder
            Task { @MainActor [weak self] in
                let visible = await Task.detached { responder.promptVisible(pane: pane, target: target) }.value
                guard let self else { return }
                inFlight.remove(request)
                store.promptCheck(session: sessionId, request: request, visible: visible, now: monotonic)
                publish()
            }
        }
        publish()
    }

    // No body until hooks can arrive: the board shows "--" then.
    private func publish() {
        refreshStatus()
        guard installed, listening else {
            currentBody = ""
            // The board keeps a sent body until it relinks; blank it once.
            if lastPublished != nil {
                lastPublished = nil
                onBody?(Self.emptyBody)
            }
            return
        }
        currentBody = store.body(now: Date())
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

    private static var historyURL: URL { livePaths().supportDir.appendingPathComponent("claude-history.json") }

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
        if let tty, tty.range(of: #"^/dev/ttys[0-9]+$"#, options: .regularExpression) != nil {
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
