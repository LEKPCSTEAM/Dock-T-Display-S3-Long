import Foundation
import Testing
@testable import LongDeckCore

private func tempDir() throws -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("longdeck-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

private func run(script: String, stdin: String, env: [String: String] = [:], in dir: URL) throws -> (out: String, status: Int32, seconds: Double) {
    let path = dir.appendingPathComponent("w.sh")
    try script.write(to: path, atomically: true, encoding: .utf8)
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = [path.path]
    var e = ProcessInfo.processInfo.environment
    for (k, v) in env { e[k] = v }
    p.environment = e
    let inPipe = Pipe(), outPipe = Pipe()
    p.standardInput = inPipe
    p.standardOutput = outPipe
    p.standardError = FileHandle.nullDevice
    let start = Date()
    try p.run()
    inPipe.fileHandleForWriting.write(Data(stdin.utf8))
    try inPipe.fileHandleForWriting.close()
    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (String(decoding: data, as: UTF8.self), p.terminationStatus, Date().timeIntervalSince(start))
}

private let refusedURL = "http://127.0.0.1:9/statusline"

@Suite struct StatusLineWrapperTests {
    @Test func scriptLayout() {
        let s = StatusLineWrapper.script(previousCommand: "cat", url: "http://x/y", token: "tok")
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines.count == 7)
        #expect(lines[0] == "#!/bin/sh")
        #expect(lines[1] == "in=$(cat)")
        #expect(lines[2] == "printf '%s' \"$in\" | '/usr/bin/curl' -s -o /dev/null --max-time 0.2 -X POST -H 'Content-Type: application/json' -H 'Expect:' -H @/dev/fd/3 -H \"X-Tmux-Pane: ${TMUX_PANE:-}\" --data-binary @- 'http://x/y' >/dev/null 2>&1 3<<'LONGDECK_TOKEN' &")
        #expect(lines[3] == "X-LongDeck-Token: tok")
        #expect(lines[4] == "LONGDECK_TOKEN")
        #expect(lines[5] == "printf '%s' \"$in\" | /bin/sh -c 'cat'")
        #expect(lines[6] == "")
    }

    @Test func shellQuoteEscapesSingleQuote() {
        #expect(StatusLineWrapper.shellQuote("it's") == "'it'\\''s'")
    }

    @Test func wrapperPassesOutputThrough() throws {
        let dir = try tempDir()
        let r = try run(script: StatusLineWrapper.script(previousCommand: "cat", url: refusedURL, token: "t"),
                        stdin: "{\"a\":1}", in: dir)
        #expect(r.out == "{\"a\":1}")
    }

    @Test func quotesPreviousCommandSafely() throws {
        let dir = try tempDir()
        let r = try run(script: StatusLineWrapper.script(previousCommand: "printf '%s' \"it's\"", url: refusedURL, token: "t"),
                        stdin: "x", in: dir)
        #expect(r.out == "it's")
    }

    @Test func noPreviousCommandPrintsNothing() throws {
        let dir = try tempDir()
        let r = try run(script: StatusLineWrapper.script(previousCommand: nil, url: refusedURL, token: "t"),
                        stdin: "x", in: dir)
        #expect(r.out.isEmpty)
        #expect(r.status == 0)
    }

    @Test func wrapperDoesNotWaitForListener() throws {
        let dir = try tempDir()
        let r = try run(script: StatusLineWrapper.script(previousCommand: "cat", url: refusedURL, token: "t"),
                        stdin: "x", in: dir)
        #expect(r.seconds < 1)
    }

    @Test func postsHeadersAndBody() throws {
        let dir = try tempDir()
        let fake = dir.appendingPathComponent("fakecurl")
        let args = dir.appendingPathComponent("args.txt")
        let headers = dir.appendingPathComponent("headers.txt")
        let body = dir.appendingPathComponent("body.txt")
        let src = "#!/bin/sh\nprintf '%s\\n' \"$@\" > \(StatusLineWrapper.shellQuote(args.path))\n"
            + "cat /dev/fd/3 > \(StatusLineWrapper.shellQuote(headers.path))\ncat > \(StatusLineWrapper.shellQuote(body.path))\n"
        try src.write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fake.path)
        let input = "{\"model\":\"x\"}"
        _ = try run(script: StatusLineWrapper.script(previousCommand: nil, url: refusedURL, token: "tok123", curl: fake.path),
                    stdin: input, env: ["TMUX_PANE": "%99"], in: dir)
        let deadline = Date().addingTimeInterval(2)
        var argText = "", bodyText = ""
        while Date() < deadline {
            argText = (try? String(contentsOf: args, encoding: .utf8)) ?? ""
            bodyText = (try? String(contentsOf: body, encoding: .utf8)) ?? ""
            if argText.contains(refusedURL) && bodyText == input { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        let list = argText.split(separator: "\n").map(String.init)
        #expect(list.contains("0.2"))
        #expect(list.contains("--max-time"))
        #expect(list.contains("Expect:"))
        #expect(list.contains("@/dev/fd/3"))
        #expect(!list.contains { $0.contains("tok123") })
        #expect((try? String(contentsOf: headers, encoding: .utf8)) == "X-LongDeck-Token: tok123\n")
        #expect(list.contains("X-Tmux-Pane: %99"))
        #expect(list.contains(refusedURL))
        #expect(bodyText == input)
    }
}
