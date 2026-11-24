import Foundation

public struct StatsSample: Equatable, Sendable {
    public var cpu, ram, gpu: Double
    public var tempC: Double?
    public var netDownBps, netUpBps: Double
    public var diskFreePct: Double
    public var diskIOBps: Double
    public var battery: Int

    public init(cpu: Double, ram: Double, gpu: Double, tempC: Double?,
                netDownBps: Double, netUpBps: Double,
                diskFreePct: Double, diskIOBps: Double, battery: Int) {
        self.cpu = cpu
        self.ram = ram
        self.gpu = gpu
        self.tempC = tempC
        self.netDownBps = netDownBps
        self.netUpBps = netUpBps
        self.diskFreePct = diskFreePct
        self.diskIOBps = diskIOBps
        self.battery = battery
    }

    public var jsonBody: String {
        func percent(_ v: Double) -> Int { v.isFinite ? Int(min(max(v, 0), 100).rounded()) : 0 }
        func rate(_ v: Double) -> Int { v.isFinite ? Int(min(max(v, 0), 1e15).rounded()) : 0 }
        var temp: Any = NSNull()
        if let tempC, tempC.isFinite { temp = Int(tempC.rounded()) }
        let object: [String: Any] = [
            "cpu": percent(cpu),
            "ram": percent(ram),
            "gpu": percent(gpu),
            "temp_c": temp,
            "net_down_bps": rate(netDownBps),
            "net_up_bps": rate(netUpBps),
            "disk_free_pct": percent(diskFreePct),
            "disk_io_bps": rate(diskIOBps),
            "battery": battery < 0 ? -1 : min(battery, 100),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
