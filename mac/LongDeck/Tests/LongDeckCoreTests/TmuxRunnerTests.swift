import Foundation
import Testing
@testable import LongDeckCore

@Suite struct TmuxRunnerTests {
    @Test func runsBinaryWithArgs() throws {
        #expect(try ProcessTmuxRunner(path: "/bin/echo").run(["a", "b"]) == "-u a b\n")
    }

    @Test func forcesUTF8FlagFirst() throws {
        #expect(try ProcessTmuxRunner(path: "/bin/echo").run(["display-message", "-p", "-t", "%37"])
                == "-u display-message -p -t %37\n")
    }

    @Test func argsReachBinaryWithoutShell() throws {
        #expect(try ProcessTmuxRunner(path: "/bin/echo").run(["$HOME", "a;b", "`id`", "%37"]) == "-u $HOME a;b `id` %37\n")
    }

    @Test func timesOutAndKills() throws {
        let start = Date()
        // sh accepts -u (nounset), so the prepended flag is harmless here.
        #expect(throws: TmuxError.timeout) {
            try ProcessTmuxRunner(path: "/bin/sh", timeout: 0.5).run(["-c", "sleep 5"])
        }
        #expect(Date().timeIntervalSince(start) < 2)
    }

    @Test func nonZeroExitThrowsFailed() {
        let error = #expect(throws: TmuxError.self) {
            try ProcessTmuxRunner(path: "/usr/bin/false").run([])
        }
        guard case .failed(let status, _)? = error else {
            Issue.record("expected .failed, got \(String(describing: error))")
            return
        }
        #expect(status == 1)
    }

    @Test func missingBinaryNotFound() {
        #expect(throws: TmuxError.notFound) {
            try ProcessTmuxRunner(path: "/nonexistent/longdeck-tmux").run(["-V"])
        }
    }

    @Test func candidatesAreAbsolutePaths() {
        #expect(ProcessTmuxRunner.candidates == ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"])
    }
}
