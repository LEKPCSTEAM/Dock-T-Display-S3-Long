import Testing
import Foundation
import Network
@testable import LongDeckCore

@MainActor
private final class Collector {
    var items: [ClaudeInbound] = []
}

@MainActor
private func startListener(_ box: Collector) async throws -> (ClaudeListener, UInt16) {
    let l = ClaudeListener(port: 0, token: "t0k") { box.items.append($0) }
    let port: UInt16 = try await withCheckedThrowingContinuation { c in
        l.start { c.resume(with: $0) }
    }
    return (l, port)
}

private func send(_ port: UInt16, path: String, method: String = "POST", token: String? = "t0k",
                  pane: String? = nil, body: Data = Data()) async throws -> (Int, Data) {
    var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
    req.httpMethod = method
    if method == "POST" { req.httpBody = body }
    if let token { req.setValue(token, forHTTPHeaderField: "X-LongDeck-Token") }
    if let pane { req.setValue(pane, forHTTPHeaderField: "X-Tmux-Pane") }
    req.timeoutInterval = 5
    let (d, resp) = try await URLSession.shared.data(for: req)
    return ((resp as! HTTPURLResponse).statusCode, d)
}

@MainActor @Suite struct ClaudeListenerTests {
    @Test func acceptsHookWithToken() async throws {
        let box = Collector()
        let (l, port) = try await startListener(box)
        defer { l.stop() }
        let body = Data(#"{"a":1}"#.utf8)
        let (code, d) = try await send(port, path: "/hook", pane: "%37", body: body)
        #expect(code == 200)
        #expect(d.isEmpty)
        #expect(box.items.count == 1)
        #expect(box.items.first?.channel == .hook)
        #expect(box.items.first?.pane == "%37")
        #expect(box.items.first?.body == body)
    }

    @Test func statusLineChannel() async throws {
        let box = Collector()
        let (l, port) = try await startListener(box)
        defer { l.stop() }
        let (code, _) = try await send(port, path: "/statusline", body: Data("{}".utf8))
        #expect(code == 200)
        #expect(box.items.first?.channel == .statusLine)
        #expect(box.items.first?.pane == nil)
    }

    @Test func rejectsMissingOrWrongToken() async throws {
        let box = Collector()
        let (l, port) = try await startListener(box)
        defer { l.stop() }
        #expect(try await send(port, path: "/hook", token: nil).0 == 403)
        #expect(try await send(port, path: "/hook", token: "nope").0 == 403)
        #expect(box.items.isEmpty)
    }

    @Test func unknownPathIs404() async throws {
        let box = Collector()
        let (l, port) = try await startListener(box)
        defer { l.stop() }
        #expect(try await send(port, path: "/other").0 == 404)
    }

    @Test func getIs405() async throws {
        let box = Collector()
        let (l, port) = try await startListener(box)
        defer { l.stop() }
        #expect(try await send(port, path: "/hook", method: "GET").0 == 405)
        #expect(box.items.isEmpty)
    }

    @Test func validPaneRules() {
        #expect(ClaudeListener.validPane("%37") == "%37")
        for bad in ["", "%", "%3a", "37"] { #expect(ClaudeListener.validPane(bad) == nil) }
        #expect(ClaudeListener.validPane(nil) == nil)
    }

    @Test func notReachableFromLanAddress() async throws {
        guard let addr = Self.lanAddress() else { return }
        let box = Collector()
        let (l, port) = try await startListener(box)
        defer { l.stop() }
        let conn = NWConnection(host: NWEndpoint.Host(addr), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let ready = Ready()
        conn.stateUpdateHandler = { if case .ready = $0 { ready.set() } }
        conn.start(queue: .global())
        try await Task.sleep(nanoseconds: 1_000_000_000)
        conn.cancel()
        #expect(!ready.value)
    }

    @Test func stopReleasesPort() async throws {
        let box = Collector()
        let (l, port) = try await startListener(box)
        l.stop()
        try await Task.sleep(nanoseconds: 200_000_000)
        await #expect(throws: (any Error).self) { _ = try await send(port, path: "/hook") }
    }

    nonisolated static func lanAddress() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = p {
            let i = cur.pointee
            if let sa = i.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
               (i.ifa_flags & UInt32(IFF_UP)) != 0,
               String(cString: i.ifa_name).hasPrefix("en") {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: host)
                }
            }
            p = i.ifa_next
        }
        return nil
    }
}

private final class Ready: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}
