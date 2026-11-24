import Foundation

public struct CPUTicks: Equatable, Sendable {
    public var busy: UInt64
    public var total: UInt64

    public init(busy: UInt64, total: UInt64) {
        self.busy = busy
        self.total = total
    }
}

public struct NetCounters: Equatable, Sendable {
    public var rx: UInt32
    public var tx: UInt32

    public init(rx: UInt32, tx: UInt32) {
        self.rx = rx
        self.tx = tx
    }
}

public protocol StatsSource: AnyObject {
    func cpuTicks() -> CPUTicks?
    func memoryUsedPct() -> Double?
    func gpuUtilizationPct() -> Double?
    func temperatureC() -> Double?
    func netCounters() -> [String: NetCounters]
    func diskFreePct() -> Double?
    func diskIOBytes() -> UInt64?
    func batteryPct() -> Int?
}

public struct StatsSampler {
    private let source: StatsSource
    private var previousTicks: CPUTicks?
    private var previousNet: [String: NetCounters]?
    private var previousIO: UInt64?
    private var previousNow: TimeInterval?
    private var lastCPU: Double = 0

    public init(source: StatsSource) {
        self.source = source
    }

    public mutating func sample(now: TimeInterval) -> StatsSample {
        let elapsed = previousNow.map { now - $0 } ?? 0
        let ticks = source.cpuTicks()
        if let ticks, let previous = previousTicks, ticks.total > previous.total {
            let busy = Double(ticks.busy &- previous.busy)
            lastCPU = 100 * busy / Double(ticks.total - previous.total)
        }
        if ticks != nil { previousTicks = ticks }

        var down = 0.0, up = 0.0
        let net = source.netCounters()
        if let previous = previousNet {
            for (name, current) in net {
                guard let old = previous[name] else { continue }
                down += Double(current.rx &- old.rx)
                up += Double(current.tx &- old.tx)
            }
        }
        previousNet = net

        var ioDelta = 0.0
        if let io = source.diskIOBytes() {
            if let previous = previousIO, io >= previous { ioDelta = Double(io - previous) }
            previousIO = io
        }

        previousNow = now
        let perSecond: (Double) -> Double = { elapsed > 0 ? $0 / elapsed : 0 }
        return StatsSample(
            cpu: lastCPU,
            ram: source.memoryUsedPct() ?? 0,
            gpu: source.gpuUtilizationPct() ?? 0,
            tempC: source.temperatureC(),
            netDownBps: perSecond(down),
            netUpBps: perSecond(up),
            diskFreePct: source.diskFreePct() ?? 0,
            diskIOBps: perSecond(ioDelta),
            battery: source.batteryPct() ?? -1)
    }
}
