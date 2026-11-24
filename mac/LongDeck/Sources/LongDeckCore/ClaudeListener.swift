import Foundation
import Network

public enum ClaudeChannel: String, Sendable { case hook, statusLine }

public struct ClaudeInbound: Sendable {
    public let channel: ClaudeChannel
    public let pane: String?
    public let body: Data

    public init(channel: ClaudeChannel, pane: String?, body: Data) {
        self.channel = channel
        self.pane = pane
        self.body = body
    }
}

public struct ClaudeListenerError: Error, Equatable { public let message: String }

@MainActor public final class ClaudeListener {
    private let port: UInt16
    private let connectionDeadline: TimeInterval
    private let maxConnections: Int
    private let token: [UInt8]
    private let onInbound: @MainActor (ClaudeInbound) -> Void
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: Connection] = [:]

    public var onFailure: (@MainActor (Error) -> Void)?

    public init(port: UInt16, token: String, connectionDeadline: TimeInterval = 5, maxConnections: Int = 32,
                onInbound: @escaping @MainActor (ClaudeInbound) -> Void) {
        self.port = port
        self.token = Array(token.utf8)
        self.connectionDeadline = connectionDeadline
        self.maxConnections = maxConnections
        self.onInbound = onInbound
    }

    public func start(onReady: @escaping @MainActor (Result<UInt16, Error>) -> Void) {
        stop()
        guard !token.isEmpty else {
            onReady(.failure(ClaudeListenerError(message: "empty token")))
            return
        }
        let params = NWParameters.tcp
        params.acceptLocalOnly = true
        params.allowLocalEndpointReuse = true
        let local: NWEndpoint.Port = port == 0 ? .any : NWEndpoint.Port(rawValue: port) ?? .any
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: local)
        let l: NWListener
        do { l = try NWListener(using: params) } catch {
            onReady(.failure(error))
            return
        }
        var reported = false
        l.stateUpdateHandler = { [weak self, weak l] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                if reported {
                    if case .failed(let error) = state { self.onFailure?(error) }
                    return
                }
                switch state {
                case .ready:
                    reported = true
                    onReady(.success(l?.port?.rawValue ?? 0))
                case .failed(let error):
                    reported = true
                    onReady(.failure(error))
                default: break
                }
            }
        }
        l.newConnectionHandler = { [weak self] conn in
            MainActor.assumeIsolated { self?.accept(conn) }
        }
        listener = l
        l.start(queue: .main)
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        for c in connections.values { c.close() }
        connections.removeAll()
    }

    public static func validPane(_ value: String?) -> String? {
        guard let v = value, v.utf8.count >= 2, v.utf8.count <= 12, v.hasPrefix("%"),
              v.utf8.dropFirst().allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
        return v
    }

    private func accept(_ nw: NWConnection) {
        guard connections.count < maxConnections else {
            nw.cancel()
            return
        }
        let c = Connection(nw, deadline: connectionDeadline) { [weak self] request in self?.route(request) ?? 500 }
        let id = ObjectIdentifier(c)
        connections[id] = c
        c.onClosed = { [weak self] in self?.connections[id] = nil }
        c.begin()
    }

    private func route(_ r: HTTPRequest) -> Int {
        let channel: ClaudeChannel
        switch r.path {
        case "/hook": channel = .hook
        case "/statusline": channel = .statusLine
        default: return 404
        }
        guard r.method == "POST" else { return 405 }
        guard let supplied = r.headers["x-longdeck-token"],
              Self.constantTimeEqual(Array(supplied.utf8), token) else { return 403 }
        onInbound(ClaudeInbound(channel: channel, pane: Self.validPane(r.headers["x-tmux-pane"]), body: r.body))
        return 200
    }

    private static func constantTimeEqual(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        var diff = UInt8(truncatingIfNeeded: a.count ^ b.count)
        for i in 0..<max(a.count, b.count) {
            diff |= (i < a.count ? a[i] : 0) ^ (i < b.count ? b[i] : 0)
        }
        return diff == 0
    }
}

@MainActor private final class Connection {
    private let deadline: TimeInterval
    private static let reasons = [200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found",
                                  405: "Method Not Allowed", 411: "Length Required",
                                  413: "Payload Too Large", 431: "Request Header Fields Too Large",
                                  501: "Not Implemented"]
    private let nw: NWConnection
    private let handle: (HTTPRequest) -> Int
    private var buffer = Data()
    private var idle: DispatchWorkItem?
    private var finished = false
    var onClosed: (() -> Void)?

    init(_ nw: NWConnection, deadline: TimeInterval, handle: @escaping (HTTPRequest) -> Int) {
        self.nw = nw
        self.deadline = deadline
        self.handle = handle
    }

    func begin() {
        nw.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                switch state {
                case .failed, .cancelled: self?.close()
                default: break
                }
            }
        }
        nw.start(queue: .main)
        armDeadline()
        receive()
    }

    func close() {
        idle?.cancel()
        idle = nil
        nw.stateUpdateHandler = nil
        nw.cancel()
        let cb = onClosed
        onClosed = nil
        cb?()
    }

    private func armDeadline() {
        let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.close() } }
        idle = w
        DispatchQueue.main.asyncAfter(deadline: .now() + deadline, execute: w)
    }

    private func receive() {
        nw.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, !self.finished else { return }
                if let data { self.buffer.append(data) }
                switch HTTPRequestParser.parse(self.buffer) {
                case .request(let r): self.respond(self.handle(r))
                case .failure(let status): self.respond(status)
                case .needMore:
                    if error != nil || isComplete { self.close() } else { self.receive() }
                }
            }
        }
    }

    private func respond(_ status: Int) {
        finished = true
        idle?.cancel()
        let reason = Self.reasons[status] ?? "Error"
        let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        nw.send(content: Data(head.utf8), completion: .contentProcessed { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        })
    }
}
