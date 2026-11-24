import Foundation
import Testing
@testable import LongDeckCore

final class FakeTmux: TmuxRunner, @unchecked Sendable {
    var calls: [[String]] = []
    var outputs: [String: String] = ["display-message": paneReply("2.1.331")]
    var failing: Set<String> = []

    init(capture: String? = nil) {
        if let capture { outputs["capture-pane"] = capture }
    }

    func run(_ args: [String]) throws -> String {
        calls.append(args)
        if failing.contains(args[0]) { throw TmuxError.failed(1, "boom") }
        return outputs[args[0]] ?? ""
    }

    var keys: [[String]] { calls.filter { $0.first == "send-keys" } }
}

private final class Activations: @unchecked Sendable {
    var ttys: [String?] = []
    var frontCalls = 0
}

func paneReply(_ command: String, sync: String = "0", mode: String = "0", inputOff: String = "0",
               width: String = "173", session: String = "T-Display-S3-Long") -> String {
    [command, sync, mode, inputOff, width, session].joined(separator: "\t")
}

private let paneFormat = "#{pane_current_command}\t#{pane_synchronized}\t#{pane_in_mode}\t#{pane_input_off}"
    + "\t#{pane_width}\t#{session_name}"
private let promptF8Framed = promptScreen([promptRule]) + promptF8
private let clientFormat = "#{client_tty}\t#{client_session}\t#{client_activity}"
private let displayCall = ["display-message", "-p", "-t", "%37", paneFormat]
private let captureCall = ["capture-pane", "-p", "-t", "%37"]
private let a1 = #"{"action":"approve","request":"a3f9-1","session":"5f0c6c1e-2b7a-4c55-9a51-0d7f3b1c9e42"}"#
private let a2 = #"{"action":"focus","request":"","session":"9b2d7e00-1111-4222-8333-444455556666"}"#
private let workingScreen = promptScreen(["⏺ Building the firmware", "", "✻ Building… (12s · esc to interrupt)"])

private func responder(_ tmux: FakeTmux, front: String? = nil, log: Activations = Activations()) -> ClaudeResponder {
    ClaudeResponder(runner: tmux, frontTTY: {
        log.frontCalls += 1
        return front
    }, activateTerminal: { log.ttys.append($0) })
}

private func target(pane: String? = "%37", pending: String? = "a3f9-1", tool: String? = "Bash",
                    input: String? = hk1Input) -> ClaudeTarget {
    ClaudeTarget(pane: pane, pendingRequest: pending, toolName: tool, toolInputJSON: input, cwd: claudeCwd)
}

private func act(_ action: ClaudeActionKind, _ request: String = "a3f9-1") -> ClaudeActionRequest {
    ClaudeActionRequest(session: claudeA, request: request, action: action)
}

private func refused(_ reason: String, _ request: String = "a3f9-1") -> ClaudeAck {
    ClaudeAck(request: request, ok: false, reason: reason)
}

private let okAck = ClaudeAck(request: "a3f9-1", ok: true, reason: "")

private func client(_ tty: String, _ session: String, _ activity: Int) -> TmuxClient {
    TmuxClient(tty: tty, session: session, activity: activity)
}

@Suite struct ClaudeResponderTests {
    @Test func actionParseA1A2() {
        #expect(ClaudeActionRequest.parse(a1) == ClaudeActionRequest(session: claudeA, request: "a3f9-1", action: .approve))
        #expect(ClaudeActionRequest.parse(a2) == ClaudeActionRequest(session: claudeB, request: "", action: .focus))
    }

    @Test func actionParseRejects() {
        let long = String(repeating: "s", count: 65)
        for body in [
            #"{"action":"maybe","request":"a3f9-1","session":"s"}"#,
            #"{"action":"focus","request":""}"#,
            #"{"action":"focus","request":"","session":""}"#,
            #"{"action":"focus","request":"","session":"\#(long)"}"#,
            #"{"action":"approve","request":"","session":"s"}"#,
            #"{"action":"deny","session":"s"}"#,
            #"{"action":"interrupt","request":7,"session":"s"}"#,
            #"{"action":7,"request":"","session":"s"}"#,
            #"["approve"]"#,
            "not json",
        ] {
            #expect(ClaudeActionRequest.parse(body) == nil, "\(body)")
        }
        let max = String(repeating: "s", count: 64)
        #expect(ClaudeActionRequest.parse(#"{"action":"interrupt","request":"","session":"\#(max)"}"#)?.session == max)
    }

    @Test func ackBodiesMatchK1K2() {
        #expect(refused("mismatch").body == #"{"ok":false,"reason":"mismatch","request":"a3f9-1"}"#)
        #expect(okAck.body == #"{"ok":true,"reason":"","request":"a3f9-1"}"#)
    }

    @Test func approveSendsYesKey() {
        let tmux = FakeTmux(capture: promptF1)
        #expect(responder(tmux).handle(act(.approve), target: target()) == okAck)
        #expect(tmux.calls == [displayCall, captureCall, ["send-keys", "-t", "%37", "-l", "1"]])
    }

    @Test func alwaysSendsAlwaysKey() {
        let wholeRule = "   2. Yes, and don't ask again for pio run -e ntp_clock commands in /tmp/work"
        let tmux = FakeTmux(capture: bashDialog(["pio run -e ntp_clock", "Build firmware"], always: wholeRule))
        #expect(responder(tmux).handle(act(.always), target: target()) == okAck)
        #expect(tmux.keys == [["send-keys", "-t", "%37", "-l", "2"]])
        let prefixRule = FakeTmux(capture: promptF1)
        #expect(responder(prefixRule).handle(act(.always), target: target()) == refused("unverifiable"))
        #expect(prefixRule.keys.isEmpty)
    }

    @Test func denySendsNoKey() {
        let tmux = FakeTmux(capture: promptF1)
        #expect(responder(tmux).handle(act(.deny), target: target()) == okAck)
        #expect(tmux.keys == [["send-keys", "-t", "%37", "-l", "3"]])
    }

    @Test func noFirstVariantDenySendsOne() {
        let tmux = FakeTmux(capture: promptF8Framed)
        #expect(responder(tmux).handle(act(.deny), target: target(input: curlInput)) == okAck)
        #expect(tmux.keys == [["send-keys", "-t", "%37", "-l", "1"]])
    }

    @Test func alwaysWithoutRowRefused() {
        let tmux = FakeTmux(capture: promptF2)
        #expect(responder(tmux).handle(act(.always), target: target()) == refused("no_always"))
        #expect(tmux.keys.isEmpty)
    }

    @Test func staleRequestRefusedWithoutCapture() {
        let tmux = FakeTmux(capture: promptF1)
        let r = responder(tmux)
        #expect(r.handle(act(.approve, "a3f9-0"), target: target()) == refused("stale", "a3f9-0"))
        #expect(r.handle(act(.deny), target: target(pending: nil)) == refused("stale"))
        #expect(r.handle(act(.always, ""), target: target(pending: "")) == refused("stale", ""))
        #expect(tmux.calls.isEmpty)
    }

    @Test func notClaudePaneRefused() {
        let tmux = FakeTmux(capture: promptF1)
        tmux.outputs["display-message"] = paneReply("zsh", session: "x")
        #expect(responder(tmux).handle(act(.approve), target: target()) == refused("not_claude"))
        #expect(responder(tmux).handle(act(.interrupt, ""), target: target()) == refused("not_claude", ""))
        #expect(tmux.calls.allSatisfy { $0.first == "display-message" })
        for command in ["2.1", "2.1.331.4", "v2.1.331", "2.1.x", "claude-code", ""] {
            tmux.outputs["display-message"] = paneReply(command)
            #expect(responder(tmux).handle(act(.approve), target: target()) == refused("not_claude"), "\(command)")
        }
        tmux.outputs["display-message"] = paneReply("claude") + "\n"
        #expect(responder(tmux).handle(act(.approve), target: target()) == okAck)
    }

    @Test func noPaneRefused() {
        let tmux = FakeTmux(capture: promptF1)
        #expect(responder(tmux).handle(act(.approve), target: target(pane: nil)) == refused("no_pane"))
        for pane in ["37", "%", "%3a", "%37 ", "-t", "%37;ls", "%1234567890123"] {
            #expect(responder(tmux).handle(act(.focus, ""), target: target(pane: pane)) == refused("no_pane", ""), "\(pane)")
        }
        #expect(responder(tmux).promptVisible(pane: "%3a") == false)
        #expect(tmux.calls.isEmpty)
    }

    @Test func unknownSessionRefused() {
        let tmux = FakeTmux(capture: promptF1)
        #expect(responder(tmux).handle(act(.approve), target: nil) == refused("unknown_session"))
        #expect(responder(tmux).handle(act(.focus, ""), target: nil) == refused("unknown_session", ""))
        #expect(tmux.calls.isEmpty)
    }

    @Test func unverifiableToolRefused() {
        let tmux = FakeTmux(capture: promptF1)
        #expect(responder(tmux).handle(act(.approve), target: target(tool: nil)) == refused("unverifiable"))
        #expect(responder(tmux).handle(act(.approve), target: target(input: #"{"command":""}"#)) == refused("unverifiable"))
        #expect(!tmux.calls.contains { $0.first == "capture-pane" })
        #expect(tmux.keys.isEmpty)
    }

    @Test func mismatchRefused() {
        let tmux = FakeTmux(capture: promptF6)
        #expect(responder(tmux).handle(act(.approve), target: target()) == refused("mismatch"))
        #expect(tmux.keys.isEmpty)
    }

    @Test func otherCommandBelowHistoryRefused() {
        let tmux = FakeTmux(capture: promptAfterOtherCommand)
        #expect(responder(tmux).handle(act(.approve), target: target()) == refused("mismatch"))
        #expect(tmux.keys.isEmpty)
    }

    @Test func noPromptRefused() {
        let tmux = FakeTmux(capture: promptF5)
        #expect(responder(tmux).handle(act(.approve), target: target()) == refused("no_prompt"))
        #expect(tmux.keys.isEmpty)
    }

    @Test func cutPromptRefused() {
        let tmux = FakeTmux(capture: promptF4)
        #expect(responder(tmux).handle(act(.deny), target: target()) == refused("no_prompt"))
        #expect(tmux.keys.isEmpty)
    }

    @Test func tmuxFailureRefused() {
        let tmux = FakeTmux(capture: promptF1)
        tmux.failing = ["capture-pane"]
        #expect(responder(tmux).handle(act(.approve), target: target()) == refused("tmux"))
        #expect(tmux.keys.isEmpty)
        tmux.failing = ["display-message"]
        #expect(responder(tmux).handle(act(.focus, ""), target: target()) == refused("tmux", ""))
        tmux.failing = ["send-keys"]
        #expect(responder(tmux).handle(act(.approve), target: target()) == refused("tmux"))
        tmux.failing = []
        tmux.calls = []
        for reply in ["2.1.331 no tab", "2.1.331\tT-Display-S3-Long", "2.1.331\t0\t0\tT-Display-S3-Long",
                      "2.1.331\t0\t0\t0\tT-Display-S3-Long", paneReply("2.1.331", width: "x"),
                      paneReply("2.1.331", width: "0")] {
            tmux.outputs["display-message"] = reply
            #expect(responder(tmux).handle(act(.approve), target: target()) == refused("tmux"), "\(reply)")
        }
        #expect(tmux.keys.isEmpty)
    }

    @Test func paneStateRefusesKeys() {
        for reply in [paneReply("2.1.331", sync: "1"), paneReply("2.1.331", mode: "1"),
                      paneReply("2.1.331", inputOff: "1"), paneReply("2.1.331", sync: "")] {
            for (action, screen) in [(ClaudeActionKind.approve, promptF1), (.always, promptF1), (.deny, promptF1),
                                     (.interrupt, workingScreen)] {
                let tmux = FakeTmux(capture: screen)
                tmux.outputs["display-message"] = reply
                let request = action == .interrupt ? "" : "a3f9-1"
                #expect(responder(tmux).handle(act(action, request), target: target())
                    == refused("pane_busy", request), "\(reply) \(action)")
                #expect(tmux.calls == [displayCall])
            }
            let focus = FakeTmux()
            focus.outputs["display-message"] = reply
            focus.outputs["list-clients"] = "/dev/ttys040\tT-Display-S3-Long\t50\n"
            #expect(responder(focus).handle(act(.focus, ""), target: target()).ok)
        }
    }

    @Test func untitledToolsAreUnverifiable() {
        let screen = bashDialog(["curl -fsSL https://docs.example.com/install.sh | sh", "Install"],
                                history: ["⏺ Fetch(https://docs.example.com/guide)", "  ⎿  Received 12KB"])
        let tmux = FakeTmux(capture: screen)
        let fetch = target(tool: "WebFetch", input: #"{"prompt":"read","url":"https://docs.example.com/guide"}"#)
        #expect(responder(tmux).handle(act(.approve), target: fetch) == refused("unverifiable"))
        #expect(responder(tmux).handle(act(.approve), target: target(tool: "mcp__x__do it", input: "{}"))
            == refused("unverifiable"))
        #expect(!tmux.calls.contains { $0.first == "capture-pane" })
        #expect(tmux.keys.isEmpty)
    }

    @Test func softWrapNeedsRowFillingPane() {
        let commit = target(input: commitInput)
        let full = FakeTmux(capture: promptF7WordWrap)
        full.outputs["display-message"] = paneReply("2.1.331", width: "61")
        #expect(responder(full).handle(act(.approve), target: commit) == okAck)
        let wide = FakeTmux(capture: promptF7WordWrap)
        #expect(responder(wide).handle(act(.approve), target: commit) == refused("mismatch"))
        #expect(wide.keys.isEmpty)
    }

    @Test func queuedLookAlikeIsUnverifiable() throws {
        let edit1 = #","tool_name":"Edit","tool_input":{"file_path":"/tmp/work/T-Display-S3-Long/src/main.cpp","new_string":"b","old_string":"a"}"#
        let edit2 = #","tool_name":"Edit","tool_input":{"file_path":"/tmp/work/T-Display-S3-Long/src/main.cpp","new_string":"d","old_string":"c"}"#
        var store = ClaudeStore(runTag: "a3f9")
        store.apply(try #require(ClaudeHookEvent.decode(hookJSON(claudeA, "PermissionRequest", extra: edit1))), pane: "%37", now: 1)
        store.apply(try #require(ClaudeHookEvent.decode(hookJSON(claudeA, "PermissionRequest", extra: edit2))), pane: "%37", now: 2)
        let tmux = FakeTmux(capture: promptF3)
        let t = try #require(store.target(session: claudeA))
        #expect(t.ambiguous)
        #expect(responder(tmux).handle(act(.approve), target: t) == refused("unverifiable"))
        #expect(responder(tmux).handle(act(.deny), target: t) == refused("unverifiable"))
        #expect(tmux.calls.isEmpty)
        var unambiguous = t
        unambiguous.ambiguous = false
        #expect(responder(tmux).handle(act(.approve), target: unambiguous) == okAck)
    }

    @Test func promptVisibleForTargetNeedsItsToolsDialog() {
        #expect(responder(FakeTmux(capture: promptF1)).promptVisible(pane: "%37", target: target()))
        #expect(responder(FakeTmux(capture: promptF6)).promptVisible(pane: "%37", target: target()))
        #expect(!responder(FakeTmux(capture: promptF3)).promptVisible(pane: "%37", target: target()))
        #expect(!responder(FakeTmux(capture: promptF4)).promptVisible(pane: "%37", target: target()))
        #expect(!responder(FakeTmux(capture: promptF5)).promptVisible(pane: "%37", target: target()))
        #expect(responder(FakeTmux(capture: promptF6)).promptVisible(pane: "%37", target: target(tool: "WebFetch")))
        let broken = FakeTmux(capture: promptF1)
        broken.failing = ["display-message"]
        #expect(!responder(broken).promptVisible(pane: "%37", target: target()))
        #expect(!responder(FakeTmux(capture: promptF1)).promptVisible(pane: "%3a", target: target()))
    }

    @Test func longWrappedDialogStaysPresentButIsNotAnswered() {
        let command = "cat /tmp/" + String(repeating: "abcdefghij", count: 20) + "/build.log"
        let chars = Array(command)
        let rows = stride(from: 0, to: chars.count, by: 57).map { String(chars[$0..<min($0 + 57, chars.count)]) }
        #expect(rows.count == 4)
        let tmux = FakeTmux(capture: bashDialog(rows + ["Show the log"]))
        tmux.outputs["display-message"] = paneReply("2.1.331", width: "61")
        let long = target(input: bashInput(command, "Show the log"))
        #expect(responder(tmux).promptVisible(pane: "%37", target: long))
        for action in [ClaudeActionKind.approve, .always, .deny] {
            #expect(!responder(tmux).handle(act(action), target: long).ok)
        }
        #expect(responder(tmux).handle(act(.approve), target: long) == refused("mismatch"))
        #expect(tmux.keys.isEmpty)
    }

    @Test func alwaysRefusedForMultiLineOrCompoundBash() {
        let alwaysRow = "   2. Yes, and don't ask again for npm test commands in /tmp/work"
        let multi = FakeTmux(capture: bashDialog(["npm test", "rm -rf build", "Run"], always: alwaysRow))
        let multiTarget = target(input: bashInput("npm test\nrm -rf build", "Run"))
        #expect(responder(multi).handle(act(.always), target: multiTarget) == refused("unverifiable"))
        #expect(!multi.calls.contains { $0.first == "capture-pane" })
        #expect(responder(multi).handle(act(.approve), target: multiTarget) == okAck)
        for command in ["npm test && rm -rf build", "npm test || rm -rf build", "npm test; rm -rf build",
                        "npm test | sh", "npm test & rm -rf build", "npm test `rm -rf build`",
                        "npm test $(rm -rf build)", "npm test > /etc/hosts", "npm test < x", "npm test\t\u{7}"] {
            let tmux = FakeTmux(capture: bashDialog([command, "Run"], always: alwaysRow))
            #expect(responder(tmux).handle(act(.always), target: target(input: bashInput(command, "Run")))
                == refused("unverifiable"), "\(command)")
            #expect(tmux.keys.isEmpty)
        }
    }

    @Test func alwaysNeedsLabelOnOneRow() {
        let wrapped = FakeTmux(capture: promptF9)
        #expect(responder(wrapped).handle(act(.always), target: target()) == refused("unverifiable"))
        #expect(wrapped.keys.isEmpty)
        #expect(responder(wrapped).handle(act(.approve), target: target()) == okAck)
        let body = ["pio run -e ntp_clock", "Build firmware"]
        let label = "   2. Yes, and don't ask again for pio run -e ntp_clock commands in /tmp/work"
        let split = FakeTmux(capture: bashDialog(body, always: label + "\n   /T-Display-S3-Long"))
        #expect(responder(split).handle(act(.always), target: target()) == refused("unverifiable"))
        #expect(split.keys.isEmpty)
        let whole = FakeTmux(capture: bashDialog(body, always: label))
        #expect(responder(whole).handle(act(.always), target: target()) == okAck)
    }

    @Test func alwaysScopeMustBeTheWholeCommand() {
        let body = ["pio run -e ntp_clock", "Build firmware"]
        func always(_ label: String) -> ClaudeAck {
            responder(FakeTmux(capture: bashDialog(body, always: "   2. " + label))).handle(act(.always), target: target())
        }
        #expect(always("Yes, and don't ask again for pio run -e ntp_clock commands in /tmp/work") == okAck)
        for label in ["Yes, and don't ask again for pio run commands in /tmp/work",
                      "Yes, and don't ask again for pio commands in /tmp/work",
                      "Yes, and don't ask again for rm commands in /tmp/work",
                      "Yes, and don't ask again for pio r commands in /tmp/work",
                      "Yes, and don't ask again for pio run commands in /tmp/wo…",
                      "Yes, and don't ask again for pio run",
                      "Yes, and don't ask again for commands in /tmp/work",
                      "Yes, and don't ask again for pio run commands in "] {
            #expect(always(label) == refused("unverifiable"), "\(label)")
        }
    }

    @Test func alwaysRefusedForPaddedCommand() {
        let rule = "   2. Yes, and don't ask again for rm -rf build commands in /tmp/work"
        for command in ["  rm -rf build", "rm -rf build ", "\trm -rf build", "rm -rf build\n"] {
            let tmux = FakeTmux(capture: bashDialog(["rm -rf build", "Clean"], always: rule))
            #expect(responder(tmux).handle(act(.always), target: target(input: bashInput(command, "Clean")))
                == refused("unverifiable"), "\(command)")
            #expect(tmux.keys.isEmpty)
        }
        let padded = String(repeating: " ", count: 78) + "rm -rf build"
        let short = FakeTmux(capture: bashDialog(["rm -rf build", "Clean"], always: "   2. Yes, and don't ask again for rm commands in /tmp/work"))
        #expect(responder(short).handle(act(.always), target: target(input: bashInput(padded, "Clean"))) == refused("unverifiable"))
        let clean = FakeTmux(capture: bashDialog(["rm -rf build", "Clean"], always: rule))
        #expect(responder(clean).handle(act(.always), target: target(input: bashInput("rm -rf build", "Clean"))) == okAck)
    }

    @Test func alwaysCapsCommandAt55Bytes() {
        func always(_ command: String) -> ClaudeAck {
            let rule = "   2. Yes, and don't ask again for \(command) commands in /tmp/work"
            let tmux = FakeTmux(capture: bashDialog([command, "Run"], always: rule))
            return responder(tmux).handle(act(.always), target: target(input: bashInput(command, "Run")))
        }
        let fits = "echo " + String(repeating: "a", count: 50)
        #expect(fits.utf8.count == 55)
        #expect(always(fits) == okAck)
        #expect(always(fits + "a") == refused("unverifiable"))
        #expect(always("echo " + String(repeating: "ก", count: 17)) == refused("unverifiable"))
    }

    @Test func alwaysRefusedForFileTools() {
        let tmux = FakeTmux(capture: promptF3)
        let edit = target(tool: "Edit", input: #"{"file_path":"/tmp/work/T-Display-S3-Long/src/main.cpp"}"#)
        #expect(responder(tmux).handle(act(.always), target: edit) == refused("unverifiable"))
        #expect(!tmux.calls.contains { $0.first == "capture-pane" })
        #expect(responder(tmux).handle(act(.approve), target: edit) == okAck)
        #expect(tmux.keys == [["send-keys", "-t", "%37", "-l", "1"]])
    }

    @Test func alwaysRefusedWhenRowBelongsToOtherTool() {
        let editRow = "   2. Yes, allow all edits during this session (shift+tab)"
        let tmux = FakeTmux(capture: bashDialog(["pio run -e ntp_clock", "Build firmware"], always: editRow))
        #expect(responder(tmux).handle(act(.always), target: target()) == refused("no_always"))
        #expect(tmux.keys.isEmpty)
        #expect(responder(tmux).handle(act(.approve), target: target()) == okAck)
        #expect(tmux.keys == [["send-keys", "-t", "%37", "-l", "1"]])
    }

    @Test func alwaysRefusedWithTwoAlwaysRows() {
        let tmux = FakeTmux(capture: promptScreen([
            promptRule, " Bash command", "", "   pio run -e ntp_clock", "   Build firmware", "",
            " Do you want to proceed?", " ❯ 1. Yes",
            "   2. Yes, and don't ask again for pio run commands in /tmp/work/T-Display-S3-Long",
            "   3. Yes, and don't ask again for pio commands in /tmp/work",
            "   4. No, and tell Claude what to do differently (esc)",
        ]))
        #expect(responder(tmux).handle(act(.always), target: target()) == refused("no_always"))
        #expect(tmux.keys.isEmpty)
        #expect(responder(tmux).handle(act(.deny), target: target()) == okAck)
        #expect(tmux.keys == [["send-keys", "-t", "%37", "-l", "4"]])
    }

    @Test func interruptNeedsWorkingScreen() {
        let tmux = FakeTmux(capture: workingScreen)
        #expect(responder(tmux).handle(act(.interrupt, ""), target: target(pending: nil))
            == ClaudeAck(request: "", ok: true, reason: ""))
        #expect(tmux.calls == [displayCall, captureCall, ["send-keys", "-t", "%37", "Escape"]])

        let spinner = "✻ Building… (12s · esc to interrupt)\n"
        for screen in [promptF5, promptF1, promptF1 + spinner, promptF4 + spinner] {
            let idle = FakeTmux(capture: screen)
            #expect(responder(idle).handle(act(.interrupt, ""), target: target()) == refused("not_working", ""))
            #expect(idle.keys.isEmpty)
        }

        let old = FakeTmux(capture: promptScreen(["✻ Building… (12s · esc to interrupt)"] + Array(repeating: "out", count: 12)))
        #expect(responder(old).handle(act(.interrupt, ""), target: target()) == refused("not_working", ""))
    }

    @Test func interruptHintMustBeSpinnerOrFooter() {
        let footer = [promptRule, "❯ ", promptRule]
        let working = [
            promptScreen(["⏺ Working"] + footer + ["  ⏵⏵ auto mode on (shift+tab to cycle) · esc to interrupt · ← 2 agents"]),
            promptScreen(["⏺ Working"] + footer + ["  esc to interrupt"]),
            promptScreen(["⏺ Working", "", "✢ Thinking… (esc to interrupt · 3s)"] + footer),
        ]
        for screen in working {
            let tmux = FakeTmux(capture: screen)
            #expect(responder(tmux).handle(act(.interrupt, ""), target: target()).ok)
            #expect(tmux.keys == [["send-keys", "-t", "%37", "Escape"]])
        }
        let idle = [
            promptScreen(["⏺ Tip: press esc to interrupt the build", "  esc to interrupt", ""] + footer + ["  ? for shortcuts"]),
            promptScreen(["⏺ Done. (12s · esc to interrupt)"] + footer),
            promptScreen(["⏺ Done"] + footer + ["  Send now isn't available here · esc to interrupt and send"]),
            promptScreen(["⏺ Done", "  · esc to interrupt"]),
        ]
        for screen in idle {
            let tmux = FakeTmux(capture: screen)
            #expect(responder(tmux).handle(act(.interrupt, ""), target: target()) == refused("not_working", ""))
            #expect(tmux.keys.isEmpty)
        }
    }

    @Test func focusSwitchesChosenClient() {
        let tmux = FakeTmux()
        tmux.outputs["list-clients"] = "/dev/ttys028\tcaltera\t100\n/dev/ttys011\thome\t300\n/dev/ttys031\tq-calling\t200\n"
        let log = Activations()
        let ack = responder(tmux, front: "/dev/ttys011", log: log).handle(act(.focus, ""), target: target(pending: nil))
        #expect(ack == ClaudeAck(request: "", ok: true, reason: ""))
        #expect(tmux.calls == [
            displayCall,
            ["list-clients", "-F", clientFormat],
            ["switch-client", "-c", "/dev/ttys011", "-t", "%37"],
            ["select-window", "-t", "%37"],
            ["select-pane", "-t", "%37"],
        ])
        #expect(log.ttys == ["/dev/ttys011"])
    }

    @Test func focusSkipsSwitchWhenClientOnSession() {
        let tmux = FakeTmux()
        tmux.outputs["list-clients"] = "/dev/ttys028\tcaltera\t900\n/dev/ttys040\tT-Display-S3-Long\t50\n"
        let log = Activations()
        let ack = responder(tmux, front: "/dev/ttys028", log: log).handle(act(.focus, ""), target: target())
        #expect(ack.ok)
        #expect(!tmux.calls.contains { $0.first == "switch-client" })
        #expect(tmux.calls.last == ["select-pane", "-t", "%37"])
        #expect(log.ttys == ["/dev/ttys040"])
        #expect(log.frontCalls == 0)
    }

    @Test func focusWithoutClientRefused() {
        let tmux = FakeTmux()
        tmux.outputs["list-clients"] = "not-a-tty\tcaltera\t1\n/dev/tty s1\tx\t2\n"
        let log = Activations()
        #expect(responder(tmux, log: log).handle(act(.focus, ""), target: target()) == refused("no_client", ""))
        #expect(tmux.calls.count == 2)
        #expect(log.ttys.isEmpty)
    }

    @Test func chooseClientRules() {
        let a = client("/dev/ttys001", "home", 100)
        let b = client("/dev/ttys002", "work", 50)
        let c = client("/dev/ttys003", "work", 70)
        let d = client("/dev/ttys004", "other", 300)
        #expect(TmuxFocus.chooseClient([a, b, c, d], paneSession: "work", frontTTY: a.tty) == c)
        #expect(TmuxFocus.chooseClient([a, d], paneSession: "work", frontTTY: a.tty) == a)
        #expect(TmuxFocus.chooseClient([a, d], paneSession: "work", frontTTY: "/dev/ttys999") == d)
        #expect(TmuxFocus.chooseClient([a, d], paneSession: "work", frontTTY: nil) == d)
        #expect(TmuxFocus.chooseClient([], paneSession: "work", frontTTY: a.tty) == nil)
    }

    @Test func neverSendsKeysWithoutMatchingCapture() {
        let fixtures = [("F2", promptF2), ("F3", promptF3), ("F4", promptF4), ("F5", promptF5), ("F6", promptF6),
                        ("F7", promptF7), ("F8", promptF8), ("F9", promptF9), ("F10", promptF10)]
        var sent: [String] = []
        for (name, screen) in fixtures {
            let tmux = FakeTmux(capture: screen)
            let ack = responder(tmux).handle(act(.approve), target: target())
            if !tmux.keys.isEmpty {
                sent.append(name)
                #expect(ack.ok)
            } else {
                #expect(!ack.ok)
            }
        }
        #expect(sent == ["F2", "F9"])
    }

    @Test func promptVisibleUsesParse() {
        #expect(responder(FakeTmux(capture: promptF1)).promptVisible(pane: "%37"))
        #expect(!responder(FakeTmux(capture: promptF5)).promptVisible(pane: "%37"))
        let broken = FakeTmux(capture: promptF1)
        broken.failing = ["capture-pane"]
        #expect(!responder(broken).promptVisible(pane: "%37"))
        #expect(broken.calls == [captureCall])
    }
}
