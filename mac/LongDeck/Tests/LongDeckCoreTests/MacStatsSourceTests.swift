import Foundation
import Testing
@testable import LongDeckCore

@Suite struct MacStatsSourceTests {
    @Test func smcReadsCpuTemperature() throws {
        let smc = try #require(SMCReader())
        let value = try #require(smc.readFloat("TCMz"))
        #expect((20.0...110.0).contains(value))
    }

    @Test func cpuTicksAdvance() throws {
        let source = MacStatsSource()
        let a = try #require(source.cpuTicks())
        Thread.sleep(forTimeInterval: 0.2)
        let b = try #require(source.cpuTicks())
        #expect(b.total > a.total)
    }

    @Test func memoryUsedPlausible() throws {
        let value = try #require(MacStatsSource().memoryUsedPct())
        #expect((5.0...100.0).contains(value))
    }

    @Test func gpuUtilizationReadable() throws {
        let value = try #require(MacStatsSource().gpuUtilizationPct())
        #expect((0.0...100.0).contains(value))
    }

    @Test func netCountersListAnEnInterface() {
        let names = MacStatsSource().netCounters().keys
        #expect(names.contains { $0.hasPrefix("en") })
    }

    @Test func diskFreeAndIOReadable() throws {
        let source = MacStatsSource()
        let free = try #require(source.diskFreePct())
        #expect((1.0...100.0).contains(free))
        let io = try #require(source.diskIOBytes())
        #expect(io > 0)
    }

    @Test func noBatteryOnThisMac() {
        #expect(MacStatsSource().batteryPct() == nil)
    }

    @Test func samplerEndToEnd() async throws {
        var sampler = StatsSampler(source: MacStatsSource())
        _ = sampler.sample(now: 0)
        try await Task.sleep(for: .seconds(1))
        let s = sampler.sample(now: 1)
        #expect((0.0...100.0).contains(s.cpu))
        #expect((5.0...100.0).contains(s.ram))
        let temp = try #require(s.tempC)
        #expect((20.0...110.0).contains(temp))
        #expect(s.battery == -1)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(s.jsonBody.utf8)) as? [String: Any])
        #expect(Set(object.keys) == ["cpu", "ram", "gpu", "temp_c", "net_down_bps", "net_up_bps",
                                     "disk_free_pct", "disk_io_bps", "battery"])
    }
}
