import Testing
@testable import LongDeckCore

@Suite struct StatsSampleTests {
    @Test func bodyMatchesS1() {
        let sample = StatsSample(cpu: 36.6, ram: 62.4, gpu: 12.0, tempC: 67.4,
                                 netDownBps: 125_000.2, netUpBps: 2_048,
                                 diskFreePct: 57.5, diskIOBps: 1_048_576, battery: -1)
        #expect(sample.jsonBody == #"{"battery":-1,"cpu":37,"disk_free_pct":58,"disk_io_bps":1048576,"gpu":12,"net_down_bps":125000,"net_up_bps":2048,"ram":62,"temp_c":67}"#)
    }

    @Test func bodyMatchesS2() {
        let sample = StatsSample(cpu: -0.2, ram: 100.4, gpu: 250, tempC: nil,
                                 netDownBps: 0, netUpBps: -1,
                                 diskFreePct: 100, diskIOBps: -3, battery: -7)
        #expect(sample.jsonBody == #"{"battery":-1,"cpu":0,"disk_free_pct":100,"disk_io_bps":0,"gpu":100,"net_down_bps":0,"net_up_bps":0,"ram":100,"temp_c":null}"#)
    }
}
