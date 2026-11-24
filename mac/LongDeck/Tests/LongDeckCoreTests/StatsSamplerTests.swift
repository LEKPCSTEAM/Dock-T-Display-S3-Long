import Testing
@testable import LongDeckCore

final class FakeSource: StatsSource, @unchecked Sendable {
    var ticks: CPUTicks?
    var ram: Double?
    var gpu: Double?
    var temp: Double?
    var net: [String: NetCounters] = [:]
    var free: Double?
    var io: UInt64?
    var battery: Int?

    func cpuTicks() -> CPUTicks? { ticks }
    func memoryUsedPct() -> Double? { ram }
    func gpuUtilizationPct() -> Double? { gpu }
    func temperatureC() -> Double? { temp }
    func netCounters() -> [String: NetCounters] { net }
    func diskFreePct() -> Double? { free }
    func diskIOBytes() -> UInt64? { io }
    func batteryPct() -> Int? { battery }
}

@Suite struct StatsSamplerTests {
    @Test func firstSampleHasZeroRates() {
        let source = FakeSource()
        source.ticks = CPUTicks(busy: 100, total: 1000)
        source.net = ["en0": NetCounters(rx: 5, tx: 5)]
        source.io = 12345
        var sampler = StatsSampler(source: source)
        let s = sampler.sample(now: 10)
        #expect(s.cpu == 0)
        #expect(s.netDownBps == 0)
        #expect(s.netUpBps == 0)
        #expect(s.diskIOBps == 0)
    }

    @Test func cpuPercentFromTickDeltas() {
        let source = FakeSource()
        source.ticks = CPUTicks(busy: 100, total: 1000)
        var sampler = StatsSampler(source: source)
        _ = sampler.sample(now: 0)
        source.ticks = CPUTicks(busy: 350, total: 1500)
        #expect(sampler.sample(now: 1).cpu == 50)
    }

    @Test func cpuRepeatsWhenTotalUnchanged() {
        let source = FakeSource()
        source.ticks = CPUTicks(busy: 100, total: 1000)
        var sampler = StatsSampler(source: source)
        _ = sampler.sample(now: 0)
        source.ticks = CPUTicks(busy: 350, total: 1500)
        _ = sampler.sample(now: 1)
        #expect(sampler.sample(now: 2).cpu == 50)
    }

    @Test func netRateSumsInterfacesAndHandlesWrap() {
        let source = FakeSource()
        source.net = ["en0": NetCounters(rx: UInt32.max - 999, tx: 0),
                      "en1": NetCounters(rx: 0, tx: 0)]
        var sampler = StatsSampler(source: source)
        _ = sampler.sample(now: 0)
        source.net = ["en0": NetCounters(rx: 1000, tx: 500),
                      "en1": NetCounters(rx: 1000, tx: 0)]
        let s = sampler.sample(now: 1)
        #expect(s.netDownBps == 3000)
        #expect(s.netUpBps == 500)

        var slow = StatsSampler(source: source)
        source.net = ["en0": NetCounters(rx: UInt32.max - 999, tx: 0),
                      "en1": NetCounters(rx: 0, tx: 0)]
        _ = slow.sample(now: 0)
        source.net = ["en0": NetCounters(rx: 1000, tx: 0),
                      "en1": NetCounters(rx: 1000, tx: 0)]
        #expect(slow.sample(now: 2).netDownBps == 1500)
    }

    @Test func newInterfaceContributesZero() {
        let source = FakeSource()
        source.net = ["en0": NetCounters(rx: 100, tx: 100)]
        var sampler = StatsSampler(source: source)
        _ = sampler.sample(now: 0)
        source.net = ["en0": NetCounters(rx: 200, tx: 100),
                      "en5": NetCounters(rx: 9_000_000, tx: 9_000_000)]
        let s = sampler.sample(now: 1)
        #expect(s.netDownBps == 100)
        #expect(s.netUpBps == 0)
    }

    @Test func diskIORateAndCounterReset() {
        let source = FakeSource()
        source.io = 1_000_000
        var sampler = StatsSampler(source: source)
        _ = sampler.sample(now: 0)
        source.io = 3_000_000
        #expect(sampler.sample(now: 2).diskIOBps == 1_000_000)
        source.io = 500
        #expect(sampler.sample(now: 3).diskIOBps == 0)
    }

    @Test func nonPositiveElapsedGivesZeroRates() {
        let source = FakeSource()
        source.io = 0
        var sampler = StatsSampler(source: source)
        _ = sampler.sample(now: 5)
        source.io = 1000
        #expect(sampler.sample(now: 5).diskIOBps == 0)
    }

    @Test func passesThroughLevelsAndBattery() {
        let source = FakeSource()
        source.ram = 62
        source.gpu = 12
        source.temp = 67
        source.free = 58
        source.battery = nil
        var sampler = StatsSampler(source: source)
        let a = sampler.sample(now: 0)
        #expect(a.ram == 62)
        #expect(a.gpu == 12)
        #expect(a.tempC == 67)
        #expect(a.diskFreePct == 58)
        #expect(a.battery == -1)
        source.battery = 80
        #expect(sampler.sample(now: 1).battery == 80)
        source.ram = nil
        source.gpu = nil
        source.temp = nil
        source.free = nil
        let b = sampler.sample(now: 2)
        #expect(b.ram == 0)
        #expect(b.gpu == 0)
        #expect(b.tempC == nil)
        #expect(b.diskFreePct == 0)
    }
}
