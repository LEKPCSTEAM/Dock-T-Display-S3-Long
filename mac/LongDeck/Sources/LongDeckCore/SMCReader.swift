import Foundation
import IOKit

public final class SMCReader {
    private var connection: io_connect_t = 0
    private static let bufferSize = 80
    private static let selector: UInt32 = 2

    public init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
    }

    deinit {
        IOServiceClose(connection)
    }

    public func readFloat(_ key: String) -> Double? {
        let scalars = Array(key.utf8)
        guard scalars.count == 4 else { return nil }
        let code = scalars.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }

        var request = [UInt8](repeating: 0, count: Self.bufferSize)
        store(code, at: 0, in: &request)
        request[42] = 9
        guard let info = call(request), info[40] == 0 else { return nil }
        let size = load(at: 28, in: info)
        let type = load(at: 32, in: info)
        guard type == 0x666C_7420, size == 4 else { return nil }

        store(size, at: 28, in: &request)
        request[42] = 5
        guard let reply = call(request), reply[40] == 0 else { return nil }
        let bits = UInt32(reply[48]) | UInt32(reply[49]) << 8 | UInt32(reply[50]) << 16 | UInt32(reply[51]) << 24
        return Double(Float(bitPattern: bits))
    }

    private func call(_ request: [UInt8]) -> [UInt8]? {
        var reply = [UInt8](repeating: 0, count: Self.bufferSize)
        var replySize = Self.bufferSize
        let status = request.withUnsafeBytes { input in
            reply.withUnsafeMutableBytes { output in
                IOConnectCallStructMethod(connection, Self.selector, input.baseAddress, Self.bufferSize,
                                          output.baseAddress, &replySize)
            }
        }
        return status == KERN_SUCCESS ? reply : nil
    }

    private func store(_ value: UInt32, at offset: Int, in buffer: inout [UInt8]) {
        buffer.withUnsafeMutableBytes { $0.storeBytes(of: value, toByteOffset: offset, as: UInt32.self) }
    }

    private func load(at offset: Int, in buffer: [UInt8]) -> UInt32 {
        buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
    }
}
