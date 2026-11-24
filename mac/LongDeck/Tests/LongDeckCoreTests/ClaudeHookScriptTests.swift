import Foundation
import Testing
@testable import LongDeckCore

private func tempDir() throws -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("longdeck-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

private struct HookRun {
    let out: String
    let err: String
    let status: Int32
    let seconds: Double
}

private func runHook(_ script: String, stdin: String, pane: String?, in dir: URL) throws -> HookRun {
    let path = dir.appendingPathComponent("hook.sh")
    try script.write(to: path, atomically: true, encoding: .utf8)
    let p = Process()
    // Through sh: first exec of a fresh file can stall on system checks.
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = [path.path]
    var e = ProcessInfo.processInfo.environment
    e["TMUX_PANE"] = pane
    p.environment = e
    let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
    p.standardInput = inPipe
    p.standardOutput = outPipe
    p.standardError = errPipe
    let start = Date()
    try p.run()
    inPipe.fileHandleForWriting.write(Data(stdin.utf8))
    try inPipe.fileHandleForWriting.close()
    // EOF on both pipes means no child still holds them.
    let out = outPipe.fileHandleForReading.readDataToEndOfFile()
    let err = errPipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return HookRun(out: String(decoding: out, as: UTF8.self), err: String(decoding: err, as: UTF8.self),
                   status: p.terminationStatus, seconds: Date().timeIntervalSince(start))
}

private struct FakeCurl {
    let path: URL
    let args: URL
    let headers: URL
    let body: URL

    init(in dir: URL, extra: String = "") throws {
        path = dir.appendingPathComponent("fakecurl")
        args = dir.appendingPathComponent("args.txt")
        headers = dir.appendingPathComponent("headers.txt")
        body = dir.appendingPathComponent("body.txt")
        let q = StatusLineWrapper.shellQuote
        let src = "#!/bin/sh\nprintf '%s\\n' \"$@\" > \(q(args.path))\ncat /dev/fd/3 > \(q(headers.path))\n"
            + "cat > \(q(body.path))\n\(extra)"
        try src.write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
    }

    func reset() {
        for u in [args, headers, body] { try? FileManager.default.removeItem(at: u) }
    }

    func recorded(expecting input: String) -> (args: [String], headers: String, body: String) {
        let deadline = Date().addingTimeInterval(10)
        var argText = "", headerText = "", bodyText = ""
        while Date() < deadline {
            argText = (try? String(contentsOf: args, encoding: .utf8)) ?? ""
            headerText = (try? String(contentsOf: headers, encoding: .utf8)) ?? ""
            bodyText = (try? String(contentsOf: body, encoding: .utf8)) ?? ""
            if argText.contains(hookURL) && bodyText == input { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return (argText.split(separator: "\n").map(String.init), headerText, bodyText)
    }
}

private struct SocketError: Error {}

// Completes TCP handshakes from the backlog but never reads or answers.
private final class SilentListener {
    let fd: Int32
    let port: UInt16

    init() throws {
        let s = socket(AF_INET, SOCK_STREAM, 0)
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(s, $0, len) == 0 && getsockname(s, $0, &len) == 0 }
        }
        guard s >= 0, bound, listen(s, 8) == 0 else {
            close(s)
            throw SocketError()
        }
        fd = s
        port = UInt16(bigEndian: addr.sin_port)
    }

    deinit { close(fd) }
}

@MainActor private final class Inbox {
    var items: [ClaudeInbound] = []
}

private let hookURL = "http://127.0.0.1:9/hook"

@Suite struct ClaudeHookScriptTests {
    @Test func scriptLayout() {
        let s = ClaudeHookScript.script(url: "http://x/hook", token: "tok")
        #expect(s == """
        #!/bin/sh
        in=$(cat)
        set --
        case ${TMUX_PANE:-} in
        %*[!0-9]* | %) ;;
        %*) set -- -H "X-Tmux-Pane: $TMUX_PANE" ;;
        esac
        { printf '%s' "$in" | '/usr/bin/curl' -s -o /dev/null --connect-timeout 0.2 --max-time 0.5 -X POST -H 'Content-Type: application/json' -H 'Expect:' -H @/dev/fd/3 "$@" --data-binary @- 'http://x/hook'; } </dev/null >/dev/null 2>&1 3<<'LONGDECK_TOKEN'
        X-LongDeck-Token: tok
        LONGDECK_TOKEN
        exit 0

        """)
        #expect(ClaudeHookScript.script(url: "u", token: "a\nLONGDECK_TOKEN\nb").contains("X-LongDeck-Token: aLONGDECK_TOKENb\n"))
    }

    @Test func refusedListenerReturnsAtOnceSilently() throws {
        let dir = try tempDir()
        let r = try runHook(ClaudeHookScript.script(url: hookURL, token: "t"), stdin: "{\"a\":1}", pane: "%3", in: dir)
        #expect(r.seconds < 1)
        #expect(r.out.isEmpty)
        #expect(r.err.isEmpty)
        #expect(r.status == 0)
    }

    @Test func silentListenerCostsAtMostHalfASecond() throws {
        let dir = try tempDir()
        let silent = try SilentListener()
        let r = try runHook(ClaudeHookScript.script(url: "http://127.0.0.1:\(silent.port)/hook", token: "t"),
                            stdin: "{\"a\":1}", pane: "%3", in: dir)
        #expect(r.seconds >= 0.4)
        #expect(r.seconds < 1)
        #expect(r.out.isEmpty)
        #expect(r.err.isEmpty)
        #expect(r.status == 0)
    }

    @Test func failingCurlStaysSilent() throws {
        let dir = try tempDir()
        let curl = try FakeCurl(in: dir, extra: "echo boom\necho boom >&2\nexit 22\n")
        let r = try runHook(ClaudeHookScript.script(url: hookURL, token: "t", curl: curl.path.path),
                            stdin: "{}", pane: nil, in: dir)
        #expect(curl.recorded(expecting: "{}").body == "{}")
        #expect(r.out.isEmpty)
        #expect(r.err.isEmpty)
        #expect(r.status == 0)
    }

    @Test func tokenOnlyOnFd3AndBodyVerbatim() throws {
        let dir = try tempDir()
        let curl = try FakeCurl(in: dir)
        let input = #"{"a":"$HOME \\ 'q' \"d\" `id` %s","b":"line\nnext"}"#
        let r = try runHook(ClaudeHookScript.script(url: hookURL, token: "tok123", curl: curl.path.path),
                            stdin: input, pane: "%99", in: dir)
        #expect(r.status == 0)
        let (args, headers, body) = curl.recorded(expecting: input)
        #expect(body == input)
        #expect(headers == "X-LongDeck-Token: tok123\n")
        #expect(!args.contains { $0.contains("tok123") })
        for arg in ["--connect-timeout", "0.2", "--max-time", "0.5", "Expect:", "@/dev/fd/3", "X-Tmux-Pane: %99",
                    "Content-Type: application/json"] {
            #expect(args.contains(arg), "missing \(arg)")
        }
        #expect(args.last == hookURL)
    }

    @Test func paneHeaderOnlyForTmuxPaneIds() throws {
        let dir = try tempDir()
        let curl = try FakeCurl(in: dir)
        for pane in [nil, "", "%", "%12x", "x%12", "%1 2", "%$(id)"] as [String?] {
            curl.reset()
            _ = try runHook(ClaudeHookScript.script(url: hookURL, token: "t", curl: curl.path.path),
                            stdin: "{}", pane: pane, in: dir)
            let (args, _, body) = curl.recorded(expecting: "{}")
            #expect(body == "{}", "pane \(pane ?? "nil")")
            #expect(!args.contains { $0.hasPrefix("X-Tmux-Pane") }, "pane \(pane ?? "nil")")
        }
    }

    @MainActor @Test func deliversLargeBodyToListener() async throws {
        let inbox = Inbox()
        let listener = ClaudeListener(port: 0, token: "t0k") { inbox.items.append($0) }
        let port: UInt16 = try await withCheckedThrowingContinuation { c in listener.start { c.resume(with: $0) } }
        defer { listener.stop() }
        // Over 1 MiB: curl would wait for a 100-continue that never comes.
        let input = #"{"session_id":"\#(claudeA)","hook_event_name":"Stop","pad":""#
            + String(repeating: "x", count: 2 * 1024 * 1024) + #""}"#
        let script = ClaudeHookScript.script(url: "http://127.0.0.1:\(port)/hook", token: "t0k")
        let dir = try tempDir()
        let r = try await Task.detached { try runHook(script, stdin: input, pane: "%37", in: dir) }.value
        let deadline = Date().addingTimeInterval(5)
        while inbox.items.isEmpty, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(r.status == 0)
        #expect(r.out.isEmpty)
        #expect(r.err.isEmpty)
        #expect(r.seconds < 1)
        #expect(inbox.items.count == 1)
        #expect(inbox.items.first?.channel == .hook)
        #expect(inbox.items.first?.pane == "%37")
        #expect(inbox.items.first?.body == Data(input.utf8))
    }
}
