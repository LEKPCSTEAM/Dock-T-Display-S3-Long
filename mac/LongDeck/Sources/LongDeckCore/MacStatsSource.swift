import Darwin
import Foundation
import IOKit
import IOKit.ps

public final class MacStatsSource: StatsSource {
    public static let temperatureKey = "TCMz"
    private let smc = SMCReader()

    public init() {}

    public func cpuTicks() -> CPUTicks? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let states = Int(CPU_STATE_MAX)
        var busy: UInt64 = 0
        var total: UInt64 = 0
        for cpu in 0..<Int(cpuCount) {
            let base = cpu * states
            let user = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]))
            let system = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]))
            let nice = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            let idle = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]))
            busy += user + system + nice
            total += user + system + nice + idle
        }
        return CPUTicks(busy: busy, total: total)
    }

    public func memoryUsedPct() -> Double? {
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let status = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }
        let pages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        let physical = Double(ProcessInfo.processInfo.physicalMemory)
        guard physical > 0 else { return nil }
        return 100 * Double(pages) * Double(pageSize) / physical
    }

    public func gpuUtilizationPct() -> Double? {
        for properties in registryProperties(matching: "IOAccelerator", key: "PerformanceStatistics") {
            if let value = properties["Device Utilization %"] as? NSNumber { return value.doubleValue }
        }
        return nil
    }

    public func temperatureC() -> Double? {
        guard let value = smc?.readFloat(Self.temperatureKey), (10.0...130.0).contains(value) else { return nil }
        return value
    }

    public func netCounters() -> [String: NetCounters] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [:] }
        defer { freeifaddrs(head) }
        var result: [String: NetCounters] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        let required = UInt32(IFF_UP | IFF_RUNNING)
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let name = String(cString: entry.pointee.ifa_name)
            guard name.hasPrefix("en"),
                  let address = entry.pointee.ifa_addr, Int32(address.pointee.sa_family) == AF_LINK,
                  entry.pointee.ifa_flags & required == required,
                  let raw = entry.pointee.ifa_data else { continue }
            let data = raw.assumingMemoryBound(to: if_data.self).pointee
            result[name] = NetCounters(rx: data.ifi_ibytes, tx: data.ifi_obytes)
        }
        return result
    }

    public func diskFreePct() -> Double? {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
              let free = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity, total > 0 else { return nil }
        return 100 * Double(free) / Double(total)
    }

    public func diskIOBytes() -> UInt64? {
        var sum: UInt64 = 0
        var found = false
        for stats in registryProperties(matching: "IOBlockStorageDriver", key: "Statistics") {
            guard let read = stats["Bytes (Read)"] as? NSNumber,
                  let write = stats["Bytes (Write)"] as? NSNumber else { continue }
            sum &+= read.uint64Value &+ write.uint64Value
            found = true
        }
        return found ? sum : nil
    }

    public func batteryPct() -> Int? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            return current * 100 / maximum
        }
        return nil
    }

    private func registryProperties(matching className: String, key: String) -> [[String: Any]] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [[String: Any]] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            if let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
               let dictionary = value as? [String: Any] {
                result.append(dictionary)
            }
        }
        return result
    }
}
