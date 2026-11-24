import Foundation
import Testing
@testable import LongDeckCore

let claudeA = "5f0c6c1e-2b7a-4c55-9a51-0d7f3b1c9e42"
let claudeB = "9b2d7e00-1111-4222-8333-444455556666"
let claudeCwd = "/tmp/work/T-Display-S3-Long"

func hookJSON(_ id: String, _ event: String, cwd: String = claudeCwd, extra: String = "") -> Data {
    Data(#"{"session_id":"\#(id)","cwd":"\#(cwd)","hook_event_name":"\#(event)"\#(extra)}"#.utf8)
}

let hk1Extra = #","tool_name":"Bash","tool_input":{"command":"pio run -e ntp_clock","description":"Build firmware"}"#
let hk0 = hookJSON(claudeA, "SessionStart", extra: #","source":"startup""#)
let hkB = hookJSON(claudeB, "UserPromptSubmit", cwd: "/tmp/work/caltera", extra: #","prompt":"hi""#)
let hk1 = hookJSON(claudeA, "PermissionRequest", extra: hk1Extra)
let hk2 = hookJSON(claudeA, "PostToolUse", extra: hk1Extra + #","tool_response":{"stdout":"ok"}"#)
let hk2f = hookJSON(claudeA, "PostToolUseFailure",
                    extra: hk1Extra + #","tool_use_id":"toolu_01","error":"Exit code 1","is_interrupt":false"#)
let hk3 = hookJSON(claudeA, "Notification", extra: #","notification_type":"idle_prompt""#)
let hk4 = hookJSON(claudeA, "Notification", extra: #","notification_type":"permission_prompt""#)

let sl2 = Data(#"{"session_id":"\#(claudeA)","cwd":"\#(claudeCwd)","model":{"id":"claude-opus-5-5","display_name":"Opus 5.5"},"workspace":{"current_dir":"\#(claudeCwd)","project_dir":"\#(claudeCwd)"},"cost":{"total_cost_usd":1.4249},"context_window":{"used_percentage":37.4}}"#.utf8)
let sl1 = Data(#"{"session_id":"\#(claudeA)","cwd":"\#(claudeCwd)","model":{"id":"claude-opus-5-5","display_name":"Opus 5.5"},"workspace":{"current_dir":"\#(claudeCwd)","project_dir":"\#(claudeCwd)"},"cost":{"total_cost_usd":1.4249},"context_window":{"used_percentage":37.4},"rate_limits":{"five_hour":{"used_percentage":42.2,"resets_at":1795530000},"seven_day":{"used_percentage":12.6,"resets_at":1795900000}}}"#.utf8)

@Suite struct ClaudeEventsTests {
    @Test func hookDecodeReadsHK1() throws {
        let e = try #require(ClaudeHookEvent.decode(hk1))
        #expect(e.sessionId == claudeA)
        #expect(e.event == "PermissionRequest")
        #expect(e.toolName == "Bash")
        #expect(e.toolInputJSON == #"{"command":"pio run -e ntp_clock","description":"Build firmware"}"#)
        #expect(e.cwd == claudeCwd)
    }

    @Test func hookDecodeReadsPostToolUseFailure() throws {
        let e = try #require(ClaudeHookEvent.decode(hk2f))
        #expect(e.event == "PostToolUseFailure")
        #expect(e.toolName == "Bash")
        #expect(e.toolInputJSON == ClaudeHookEvent.decode(hk1)?.toolInputJSON)
    }

    @Test func hookDecodeReadsNotificationType() throws {
        let e = try #require(ClaudeHookEvent.decode(hk3))
        #expect(e.event == "Notification")
        #expect(e.notificationType == "idle_prompt")
    }

    @Test func hookDecodeRejects() {
        #expect(ClaudeHookEvent.decode(Data(#"{"hook_event_name":"Stop"}"#.utf8)) == nil)
        #expect(ClaudeHookEvent.decode(Data(#"{"session_id":"A"}"#.utf8)) == nil)
        #expect(ClaudeHookEvent.decode(Data("[]".utf8)) == nil)
        #expect(ClaudeHookEvent.decode(Data("x".utf8)) == nil)
    }

    @Test func statusDecodeReadsSL1() throws {
        let u = try #require(ClaudeStatusUpdate.decode(sl1))
        #expect(u.sessionId == claudeA)
        #expect(u.model == "Opus 5.5")
        #expect(u.costUSD == 1.4249)
        #expect(u.contextPct == 37.4)
        #expect(u.projectDir == claudeCwd)
        #expect(u.fiveHour == UsageWindow(pct: 42.2, resetsAt: 1795530000))
        #expect(u.sevenDay == UsageWindow(pct: 12.6, resetsAt: 1795900000))
    }

    @Test func statusDecodeToleratesMissingRateLimits() throws {
        let u = try #require(ClaudeStatusUpdate.decode(sl2))
        #expect(u.fiveHour == nil)
        #expect(u.sevenDay == nil)
        let only = Data(#"{"session_id":"A","rate_limits":{"five_hour":{"used_percentage":5,"resets_at":1795530000}}}"#.utf8)
        let v = try #require(ClaudeStatusUpdate.decode(only))
        #expect(v.fiveHour == UsageWindow(pct: 5, resetsAt: 1795530000))
        #expect(v.sevenDay == nil)
        #expect(ClaudeStatusUpdate.decode(Data("x".utf8)) == nil)
    }
}
