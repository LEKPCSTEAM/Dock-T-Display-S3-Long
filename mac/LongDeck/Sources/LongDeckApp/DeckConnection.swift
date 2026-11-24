import Foundation
import LongDeckCore
import Network

enum ConnectionEvent {
    case needPairCode
    case codeRejected
    case ready(boardId: String)
    case pageChanged(Int)
    case actionFailed(String)
    case closed(reason: String?)
    case boardForgotMac
}

@MainActor
final class DeckConnection {
    private let board: DiscoveredBoard
    private let pairing: Bool
    private let runner: ActionRunner
    private let configProvider: () -> DeckConfig?
    private let onEvent: (ConnectionEvent) -> Void
    private let volume: VolumeControl
    private let claudeBody: () -> String?
    private let onClaudeAction: (String) -> Void

    private var link = LiveLink()
    private var pushGeneration = 0
    private var handshake: DeckHandshake
    private var task: URLSessionWebSocketTask?
    private var sealer: FrameSealer?
    private var opener: FrameOpener?
    private var sawChallenge = false
    private var boardHash: String?
    private var closed = false
    private var pingTask: Task<Void, Never>?
    private var pushTask: Task<Void, Never>?
    private var lastPong = Date()
    private static let pingInterval = 5.0
    private static let pongTimeout = 10.0

    init(
        board: DiscoveredBoard, pairing: Bool, runner: ActionRunner,
        configProvider: @escaping () -> DeckConfig?, volume: VolumeControl,
        claudeBody: @escaping () -> String?, onClaudeAction: @escaping (String) -> Void,
        onEvent: @escaping (ConnectionEvent) -> Void
    ) {
        self.volume = volume
        self.claudeBody = claudeBody
        self.onClaudeAction = onClaudeAction
        self.board = board
        self.pairing = pairing
        self.runner = runner
        self.configProvider = configProvider
        self.onEvent = onEvent
        handshake = DeckHandshake(
            storedKey: { pairing ? nil : KeyStore.load(boardId: $0) },
            random: { n in Data((0..<n).map { _ in UInt8.random(in: 0...255) }) },
            keyPair: { DeckCrypto.newKeyPair() }
        )
    }

    func connect() {
        Task { @MainActor in
            do {
                let host = try await Self.resolveHost(board.endpoint)
                guard !closed else { return }
                open(host: host)
            } catch {
                finish("resolve failed")
            }
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        pingTask?.cancel()
        pushTask?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    func submitPairCode(_ code: String) {
        handle(handshake.submitPairCode(code))
    }

    var isReady: Bool { sealer != nil && !closed }

    func sendStats(_ sample: StatsSample) {
        if let frame = link.statsFrame(body: sample.jsonBody) { sendFrame(frame) }
    }

    func sendVolume(_ state: VolumeState) {
        if let frame = link.volumeFrame(body: state.jsonBody) { sendFrame(frame) }
    }

    func sendClaude(_ body: String) {
        if let frame = link.claudeFrame(body: body) { sendFrame(frame) }
    }

    func sendClaudeAck(_ body: String) {
        if let frame = link.ackFrame(body: body) { sendFrame(frame) }
    }

    private func sendFrame(_ f: OutFrame) {
        guard !closed, var sealer, let task else { return }
        let text = sealer.seal(type: f.type, body: f.body)
        self.sealer = sealer
        task.send(.string(text)) { _ in }
    }

    func push(config: DeckConfig) {
        guard sealer != nil else { return }
        let built = LayoutBuilder.build(config)
        guard built.hash != boardHash else { return }
        send(built)
    }

    private func open(host: String) {
        guard let url = URL(string: "ws://\(host):81") else { return finish("bad host") }
        let task = URLSession.shared.webSocketTask(with: url)
        self.task = task
        task.resume()
        startPinging(task)
        handle(handshake.start())
        receiveLoop(task)
    }

    private func startPinging(_ task: URLSessionWebSocketTask) {
        lastPong = Date()
        pingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.pingInterval))
                guard let self, !self.closed, self.task === task else { return }
                if Date().timeIntervalSince(self.lastPong) > Self.pongTimeout {
                    return self.finish("ping timeout")
                }
                task.sendPing { error in
                    Task { @MainActor in
                        guard !self.closed, self.task === task else { return }
                        if error != nil { self.finish("ping failed") } else { self.lastPong = Date() }
                    }
                }
            }
        }
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, !self.closed, self.task === task else { return }
                switch result {
                case .failure:
                    self.finish(nil)
                case .success(let message):
                    if case .string(let text) = message { self.onText(text) }
                    guard !self.closed else { return }
                    self.receiveLoop(task)
                }
            }
        }
    }

    private func onText(_ text: String) {
        if opener != nil {
            onSession(text)
            return
        }
        if !pairing, Self.isUnpairedChallenge(text) {
            return forgotten()
        }
        handle(handshake.receive(text))
        if pairing, !sawChallenge, text.contains("\"challenge\"") {
            sawChallenge = true
            handle(handshake.beginPairing())
        }
    }

    private func handle(_ outputs: [HandshakeOutput]) {
        for output in outputs {
            guard !closed else { return }
            switch output {
            case .send(let text):
                task?.send(.string(text)) { _ in }
            case .needPairCode:
                onEvent(.needPairCode)
            case .paired(let key, let boardId):
                do { try KeyStore.save(key, boardId: boardId) } catch { return finish("keychain save failed") }
            case .ready(let sessionKey, let boardId):
                sealer = FrameSealer(sessionKey: sessionKey)
                opener = FrameOpener(sessionKey: sessionKey)
                link.reset()
                sendVolume(volume.read())
                if let body = claudeBody() { sendClaude(body) }
                onEvent(.ready(boardId: boardId))
            case .failed(let reason):
                if reason == "code" {
                    onEvent(.codeRejected)
                } else if reason == "auth", !pairing, opener == nil {
                    forgotten()
                } else {
                    finish(reason)
                }
            }
        }
    }

    private func onSession(_ text: String) {
        guard var opener else { return }
        let frame: (type: String, body: String)
        do { frame = try opener.open(text) } catch { return finish("bad frame") }
        self.opener = opener
        let obj = (try? JSONSerialization.jsonObject(with: Data(frame.body.utf8))) as? [String: Any] ?? [:]
        switch frame.type {
        case "hello_state":
            boardHash = obj["hash"] as? String ?? ""
            if let config = configProvider() { push(config: config) }
        case "slider", "press":
            guard let config = configProvider() else { return }
            if let command = LiveLink.command(type: frame.type, body: frame.body, config: config) {
                return run(command)
            }
            guard frame.type == "press", let id = obj["id"] as? String, let kind = obj["kind"] as? String else { return }
            guard !LiveLink.isLiveWidget(id: id, config: config) else { return }
            do {
                try runner.handlePress(id: id, kind: kind, config: config)
            } catch {
                onEvent(.actionFailed(Self.describe(error)))
            }
        case "page":
            let index = obj["index"] as? Int ?? -1
            link.pageChanged(index)
            onEvent(.pageChanged(index))
        case "claude_action":
            onClaudeAction(frame.body)
        default:
            break
        }
    }

    private func run(_ command: LiveCommand) {
        do {
            switch command {
            case .setVolume(let n): try volume.setLevelUnmuting(n)
            case .toggleMute: try volume.toggleMute()
            }
        } catch {
            onEvent(.actionFailed("Volume: \(Self.describe(error))"))
        }
    }

    private func send(_ built: BuiltLayout) {
        guard var sealer, let task else { return }
        let layout = sealer.seal(type: "layout", body: built.json)
        let bytes = layout.utf8.count
        guard LayoutPushPolicy.fits(frameBytes: bytes) else {
            let max = LayoutPushPolicy.maxWebSocketFrame
            onEvent(.actionFailed("Layout too large for the board: \(bytes) bytes, max \(max)"))
            return
        }
        self.sealer = sealer
        boardHash = built.hash
        pushTask?.cancel()
        link.pushStarted()
        pushGeneration += 1
        let generation = pushGeneration
        pushTask = Task { @MainActor [weak self] in
            guard await Self.send(.string(layout), on: task) else { return self?.finish("send failed") ?? () }
            for id in built.faces.keys.sorted() {
                let face = built.faces[id]!
                guard let self, !self.closed, self.task === task, self.sealer != nil else { return }
                let chunks = self.sealer!.faceChunks(id: id, w: face.w, h: face.h, pixels: face.pixels)
                for chunk in chunks {
                    guard !Task.isCancelled, !self.closed else { return }
                    guard await Self.send(.data(chunk), on: task) else { return self.finish("send failed") }
                }
            }
            guard let self, !Task.isCancelled, !self.closed, self.pushGeneration == generation else { return }
            for held in self.link.pushFinished() { self.sendFrame(held) }
        }
    }

    private static func send(_ message: URLSessionWebSocketTask.Message, on task: URLSessionWebSocketTask) async -> Bool {
        await withCheckedContinuation { cont in
            task.send(message) { cont.resume(returning: $0 == nil) }
        }
    }

    private static func isUnpairedChallenge(_ text: String) -> Bool {
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else { return false }
        return obj["t"] as? String == "challenge" && obj["paired"] as? Bool == false
    }

    private func forgotten() {
        guard !closed else { return }
        close()
        onEvent(.boardForgotMac)
    }

    private func finish(_ reason: String?) {
        guard !closed else { return }
        close()
        onEvent(.closed(reason: reason))
    }

    static func describe(_ error: Error) -> String {
        switch error as? ActionError {
        case .notTrusted: return "Accessibility permission needed"
        case .unknownKey(let id): return "Unknown key \(id)"
        case .failed(let message): return message
        case nil: return error.localizedDescription
        }
    }

    private static func resolveHost(_ endpoint: NWEndpoint) async throws -> String {
        let params = NWParameters.tcp
        (params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
        let connection = NWConnection(to: endpoint, using: params)
        return try await withCheckedThrowingContinuation { cont in
            let box = ResumeOnce(cont)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case .hostPort(let host, _) = connection.currentPath?.remoteEndpoint {
                        let text = "\(host)".split(separator: "%").first.map(String.init) ?? "\(host)"
                        box.resume(.success(text))
                    } else {
                        box.resume(.failure(URLError(.cannotFindHost)))
                    }
                    connection.cancel()
                case .failed, .cancelled:
                    box.resume(.failure(URLError(.cannotFindHost)))
                default:
                    break
                }
            }
            connection.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                box.resume(.failure(URLError(.timedOut)))
                connection.cancel()
            }
        }
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private var cont: CheckedContinuation<String, Error>?

    init(_ cont: CheckedContinuation<String, Error>) {
        self.cont = cont
    }

    func resume(_ result: Result<String, Error>) {
        guard let c = cont else { return }
        cont = nil
        c.resume(with: result)
    }
}
