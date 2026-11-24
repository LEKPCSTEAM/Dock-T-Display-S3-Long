import Testing
@testable import LongDeckCore

@MainActor
final class FakeVolume: VolumeControl {
    var state: VolumeState

    init(_ state: VolumeState) { self.state = state }

    func read() -> VolumeState { state }

    func setLevel(_ level: Int) throws {
        guard state.available else { throw VolumeError.unavailable }
        state.level = max(0, min(100, level))
    }

    func setMuted(_ muted: Bool) throws {
        guard state.available else { throw VolumeError.unavailable }
        state.muted = muted
    }
}

@MainActor
struct VolumeTests {
    @Test func bodyMatchesV1AndV2() {
        #expect(VolumeState(level: 44, muted: false, available: true).jsonBody
            == #"{"available":true,"level":44,"muted":false}"#)
        #expect(VolumeState.unavailable.jsonBody
            == #"{"available":false,"level":0,"muted":false}"#)
    }

    @Test func stateClampsAndNormalises() {
        #expect(VolumeState(level: 150, muted: false, available: true).level == 100)
        #expect(VolumeState(level: -5, muted: false, available: true).level == 0)
        #expect(VolumeState(level: 70, muted: true, available: false) == .unavailable)
    }

    @Test func toggleMuteFlips() throws {
        let fake = FakeVolume(VolumeState(level: 40, muted: false, available: true))
        try fake.toggleMute()
        #expect(fake.read().muted)
        try fake.toggleMute()
        #expect(!fake.read().muted)
    }

    @Test func setLevelUnmuting() throws {
        let fake = FakeVolume(VolumeState(level: 10, muted: true, available: true))
        try fake.setLevelUnmuting(30)
        #expect(fake.read().level == 30)
        #expect(!fake.read().muted)
        fake.state.muted = true
        try fake.setLevelUnmuting(0)
        #expect(fake.read().level == 0)
        #expect(fake.read().muted)
    }

    @Test func unavailableThrows() {
        let fake = FakeVolume(.unavailable)
        #expect(throws: VolumeError.unavailable) { try fake.toggleMute() }
        #expect(throws: VolumeError.unavailable) { try fake.setLevelUnmuting(50) }
    }

    @Test func percentRejectsNonFinite() {
        #expect(CoreAudioVolume.percent(0.444) == 44)
        #expect(CoreAudioVolume.percent(1e37) == 100)
        #expect(CoreAudioVolume.percent(-1e37) == 0)
        #expect(CoreAudioVolume.percent(1.5) == 100)
        #expect(CoreAudioVolume.percent(.nan) == nil)
        #expect(CoreAudioVolume.percent(.infinity) == nil)
        #expect(CoreAudioVolume.percent(-.infinity) == nil)
    }

    @Test func coreAudioReadsDefaultOutput() {
        let volume = CoreAudioVolume()
        let state = volume.read()
        #expect((0...100).contains(state.level))
        if CoreAudioVolume.defaultOutputName() == "Mac mini Speakers" {
            #expect(state.available)
        }
    }
}
