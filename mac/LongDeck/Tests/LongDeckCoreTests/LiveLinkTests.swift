import Foundation
import Testing
@testable import LongDeckCore

private let s1 = #"{"battery":-1,"cpu":37,"disk_free_pct":58,"disk_io_bps":1048576,"gpu":12,"net_down_bps":125000,"net_up_bps":2048,"ram":62,"temp_c":67}"#
private let v1 = #"{"available":true,"level":44,"muted":false}"#
private let v2 = #"{"available":false,"level":0,"muted":false}"#
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
        #expect(link.pushFinished() == OutFrame(type: "volume", body: v2))
        #expect(link.volumeFrame(body: v2) == nil)
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
