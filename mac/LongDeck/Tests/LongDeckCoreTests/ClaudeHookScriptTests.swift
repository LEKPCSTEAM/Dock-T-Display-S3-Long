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
    // EOF on both pipes means no background child still holds them.
    let out = outPipe.fileHandleForReading.readDataToEndOfFile()
    let err = errPipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return HookRun(out: String(decoding: out, as: UTF8.self), err: String(decoding: err, as: UTF8.self),
                   status: p.terminationStatus, seconds: Date().timeIntervalSince(start))
}

private struct FakeCurl {
    let path: URL
    let args: URL
    let body: URL

    init(in dir: URL, extra: String = "") throws {
        path = dir.appendingPathComponent("fakecurl")
        args = dir.appendingPathComponent("args.txt")
        body = dir.appendingPathComponent("body.txt")
        let q = StatusLineWrapper.shellQuote
        let src = "#!/bin/sh\nprintf '%s\\n' \"$@\" > \(q(args.path))\ncat > \(q(body.path))\n\(extra)"
        try src.write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
    }

    func reset() {
        try? FileManager.default.removeItem(at: args)
        try? FileManager.default.removeItem(at: body)
    }

    func recorded(expecting input: String) -> (args: [String], body: String) {
        let deadline = Date().addingTimeInterval(10)
        var argText = "", bodyText = ""
        while Date() < deadline {
            argText = (try? String(contentsOf: args, encoding: .utf8)) ?? ""
            bodyText = (try? String(contentsOf: body, encoding: .utf8)) ?? ""
            if argText.contains(hookURL) && bodyText == input { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return (argText.split(separator: "\n").map(String.init), bodyText)
    }
}

private let hookURL = "http://127.0.0.1:9/hook"

@Suite struct ClaudeHookScriptTests {
    @Test func scriptLayout() {
        let s = ClaudeHookScript.script(url: "http://x/hook", token: "tok")
        #expect(s == """
        #!/bin/sh
        in=$(cat)
        set -- -H 'X-LongDeck-Token: tok'
        case ${TMUX_PANE:-} in
        %*[!0-9]* | %) ;;
        %*) set -- "$@" -H "X-Tmux-Pane: $TMUX_PANE" ;;
        esac
        { printf '%s' "$in" | '/usr/bin/curl' -s -o /dev/null --max-time 1 -X POST -H 'Content-Type: application/json' "$@" --data-binary @- 'http://x/hook'; } </dev/null >/dev/null 2>&1 &
        exit 0

        """)
    }

    @Test func refusedListenerPrintsNothingAndExitsZero() throws {
        let dir = try tempDir()
        let r = try runHook(ClaudeHookScript.script(url: hookURL, token: "t"), stdin: "{\"a\":1}", pane: "%3", in: dir)
        #expect(r.out.isEmpty)
        #expect(r.err.isEmpty)
        #expect(r.status == 0)
    }

    @Test func doesNotWaitForSlowListener() throws {
        let dir = try tempDir()
        let curl = try FakeCurl(in: dir, extra: "sleep 2\necho late\necho late >&2\nexit 7\n")
        let r = try runHook(ClaudeHookScript.script(url: hookURL, token: "t", curl: curl.path.path),
                            stdin: "{\"a\":1}", pane: "%3", in: dir)
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
        _ = curl.recorded(expecting: "{}")
        #expect(r.out.isEmpty)
        #expect(r.err.isEmpty)
        #expect(r.status == 0)
    }

    @Test func postsHeadersAndBodyVerbatim() throws {
        let dir = try tempDir()
        let curl = try FakeCurl(in: dir)
        let input = #"{"a":"$HOME \\ 'q' \"d\" `id` %s","b":"line\nnext"}"#
        let r = try runHook(ClaudeHookScript.script(url: hookURL, token: "tok123", curl: curl.path.path),
                            stdin: input, pane: "%99", in: dir)
        #expect(r.status == 0)
        let (args, body) = curl.recorded(expecting: input)
        #expect(body == input)
        #expect(args.contains("--max-time"))
        #expect(args.contains("1"))
        #expect(args.contains("X-LongDeck-Token: tok123"))
        #expect(args.contains("X-Tmux-Pane: %99"))
        #expect(args.contains("Content-Type: application/json"))
        #expect(args.last == hookURL)
    }

    @Test func paneHeaderOnlyForTmuxPaneIds() throws {
        let dir = try tempDir()
        let curl = try FakeCurl(in: dir)
        for pane in [nil, "", "%", "%12x", "x%12", "%1 2", "%$(id)"] as [String?] {
            curl.reset()
            _ = try runHook(ClaudeHookScript.script(url: hookURL, token: "t", curl: curl.path.path),
                            stdin: "{}", pane: pane, in: dir)
            let (args, body) = curl.recorded(expecting: "{}")
            #expect(body == "{}", "pane \(pane ?? "nil")")
            #expect(!args.contains { $0.hasPrefix("X-Tmux-Pane") }, "pane \(pane ?? "nil")")
        }
    }
}
