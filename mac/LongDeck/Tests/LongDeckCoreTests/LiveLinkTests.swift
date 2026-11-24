import Foundation
import Testing
@testable import LongDeckCore

private let s1 = #"{"battery":-1,"cpu":37,"disk_free_pct":58,"disk_io_bps":1048576,"gpu":12,"net_down_bps":125000,"net_up_bps":2048,"ram":62,"temp_c":67}"#
private let v1 = #"{"available":true,"level":44,"muted":false}"#
private let v2 = #"{"available":false,"level":0,"muted":false}"#
private let c1 = #"{"prompt":{"pending":1,"project":"T-Display-S3-Long","request":"a3f9-1","session":"5f0c6c1e-2b7a-4c55-9a51-0d7f3b1c9e42","summary":"pio run -e ntp_clock","tmux":true,"tool":"Bash"},"sessions":[{"cost_cents":142,"ctx":37,"id":"5f0c6c1e-2b7a-4c55-9a51-0d7f3b1c9e42","model":"Opus 5.5","project":"T-Display-S3-Long","state":"permission","tmux":true},{"cost_cents":-1,"ctx":-1,"id":"9b2d7e00-1111-4222-8333-444455556666","model":"","project":"caltera","state":"working","tmux":false}],"usage":{"five_hour":{"pct":42,"resets_at":1795530000},"seven_day":{"pct":13,"resets_at":1795900000}}}"#
private let c2 = #"{"prompt":null,"sessions":[],"usage":{"five_hour":null,"seven_day":null}}"#
private let k1 = #"{"ok":false,"reason":"mismatch","request":"a3f9-1"}"#
private let k2 = #"{"ok":true,"reason":"","request":"a3f9-1"}"#
private let p1 = #"{"id":"vol","value":55}"#
private let p2 = #"{"id":"vol","kind":"tap"}"#

@Suite struct LiveLinkTests {
    @Test func statsOnlyWhileDeckPageVisible() {
        var link = LiveLink()
        #expect(link.statsFrame(body: s1) == nil)
        link.pageChanged(0)
        #expect(link.statsFrame(body: s1) == OutFrame(type: "stats", body: s1))
        link.pageChanged(-1)
        #expect(link.statsFrame(body: s1) == nil)
        link.pageChanged(0)
        link.reset()
        #expect(link.page == -1)
        #expect(link.statsFrame(body: s1) == nil)
    }

    @Test func statsSkippedDuringPush() {
        var link = LiveLink()
        link.pageChanged(0)
        link.pushStarted()
        #expect(link.statsFrame(body: s1) == nil)
        _ = link.pushFinished()
        #expect(link.statsFrame(body: s1) != nil)
    }

    @Test func volumeDedupes() {
        var link = LiveLink()
        #expect(link.volumeFrame(body: v1) == OutFrame(type: "volume", body: v1))
        #expect(link.volumeFrame(body: v1) == nil)
        #expect(link.volumeFrame(body: v2) != nil)
        link.reset()
        #expect(link.volumeFrame(body: v2) != nil)
    }

    @Test func volumeDeferredDuringPush() {
        var link = LiveLink()
        link.pushStarted()
        #expect(link.volumeFrame(body: v1) == nil)
        #expect(link.volumeFrame(body: v2) == nil)
        #expect(link.pushFinished() == [OutFrame(type: "volume", body: v2)])
        #expect(link.volumeFrame(body: v2) == nil)
    }

    @Test func claudeDedupes() {
        var link = LiveLink()
        #expect(link.claudeFrame(body: c1) == OutFrame(type: "claude", body: c1))
        #expect(link.claudeFrame(body: c1) == nil)
        #expect(link.claudeFrame(body: c2) != nil)
        link.reset()
        #expect(link.claudeFrame(body: c2) != nil)
    }

    @Test func claudeDeferredDuringPushKeepsNewest() {
        var link = LiveLink()
        link.pushStarted()
        #expect(link.claudeFrame(body: c1) == nil)
        #expect(link.claudeFrame(body: c2) == nil)
        #expect(link.pushFinished() == [OutFrame(type: "claude", body: c2)])
    }

    @Test func acksQueuedDuringPushInOrder() {
        var link = LiveLink()
        link.pushStarted()
        #expect(link.ackFrame(body: k1) == nil)
        #expect(link.ackFrame(body: k2) == nil)
        #expect(link.pushFinished() == [OutFrame(type: "claude_ack", body: k1),
                                        OutFrame(type: "claude_ack", body: k2)])
        link.pushStarted()
        for n in 0..<10 { _ = link.ackFrame(body: "ack\(n)") }
        let kept = link.pushFinished().map(\.body)
        #expect(kept == (2..<10).map { "ack\($0)" })
    }

    @Test func pushFinishedOrder() {
        var link = LiveLink()
        link.pushStarted()
        _ = link.volumeFrame(body: v1)
        _ = link.claudeFrame(body: c1)
        _ = link.ackFrame(body: k1)
        #expect(link.pushFinished().map(\.type) == ["volume", "claude", "claude_ack"])
    }

    @Test func acksNeverDeduped() {
        var link = LiveLink()
        #expect(link.ackFrame(body: k1) == OutFrame(type: "claude_ack", body: k1))
        #expect(link.ackFrame(body: k1) == OutFrame(type: "claude_ack", body: k1))
    }

    @Test func resetForgetsClaudeState() {
        var link = LiveLink()
        link.pushStarted()
        _ = link.claudeFrame(body: c1)
        _ = link.ackFrame(body: k1)
        link.reset()
        #expect(link.pushFinished().isEmpty)
    }

    @Test func sliderOnVolumeWidgetSetsVolume() {
        #expect(LiveLink.command(type: "slider", body: p1, config: liveConfig()) == .setVolume(55))
    }

    @Test func sliderForOtherIdsIgnored() {
        let config = liveConfig()
        for body in [#"{"id":"cpu","value":5}"#, #"{"id":"k1","value":5}"#, #"{"id":"nope","value":5}"#,
                     #"{"id":"vol","value":101}"#, #"{"id":"vol","value":-1}"#, "{"] {
            #expect(LiveLink.command(type: "slider", body: body, config: config) == nil)
        }
    }

    @Test func tapOnVolumeWidgetTogglesMute() {
        let config = liveConfig()
        #expect(LiveLink.command(type: "press", body: p2, config: config) == .toggleMute)
        #expect(LiveLink.command(type: "press", body: #"{"id":"vol","kind":"long"}"#, config: config) == nil)
        #expect(LiveLink.command(type: "press", body: #"{"id":"k1","kind":"tap"}"#, config: config) == nil)
    }

    @Test func liveWidgetIdsNeverFallThroughToKeys() {
        let config = liveConfig()
        for id in ["vol", "cpu"] { #expect(LiveLink.isLiveWidget(id: id, config: config)) }
        for id in ["k1", "nope"] { #expect(!LiveLink.isLiveWidget(id: id, config: config)) }
    }
}
