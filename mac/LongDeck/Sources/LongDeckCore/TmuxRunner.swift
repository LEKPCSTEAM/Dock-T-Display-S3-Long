import Foundation

public protocol TmuxRunner: Sendable {
    func run(_ args: [String]) throws -> String
}

public enum TmuxError: Error, Equatable {
    case notFound, timeout, failed(Int32, String)
}

public struct ProcessTmuxRunner: TmuxRunner {
    public static let candidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
    private static let killGrace: TimeInterval = 0.5

    private let path: String?
    private let timeout: TimeInterval

    public init(path: String? = nil, timeout: TimeInterval = 2) {
        self.path = path
        self.timeout = timeout
    }

    public func run(_ args: [String]) throws -> String {
        let fm = FileManager.default
        guard let exe = path.map({ fm.isExecutableFile(atPath: $0) ? $0 : nil })
                ?? Self.candidates.first(where: { fm.isExecutableFile(atPath: $0) })
        else { throw TmuxError.notFound }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = args
        process.standardInput = FileHandle.nullDevice
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { throw TmuxError.notFound }
        let stdout = PipeDrain(out.fileHandleForReading)
        let stderr = PipeDrain(err.fileHandleForReading)
        let deadline = DispatchTime.now() + timeout
        if exited.wait(timeout: deadline) == .timedOut {
            if process.isRunning { process.terminate() }
            if exited.wait(timeout: .now() + Self.killGrace) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
            }
            throw TmuxError.timeout
        }
        // A forked child may hold the pipe open after exit.
        guard let output = stdout.wait(until: deadline + Self.killGrace),
              let errors = stderr.wait(until: deadline + Self.killGrace)
        else { throw TmuxError.timeout }
        guard process.terminationStatus == 0 else {
            throw TmuxError.failed(process.terminationStatus, String(decoding: errors, as: UTF8.self))
        }
        return String(decoding: output, as: UTF8.self)
    }
}

private final class PipeDrain: @unchecked Sendable {
    private var data = Data()
    private let done = DispatchSemaphore(value: 0)

    init(_ handle: FileHandle) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.data = (try? handle.readToEnd()) ?? Data()
            self.done.signal()
        }
    }

    func wait(until deadline: DispatchTime) -> Data? {
        done.wait(timeout: deadline) == .success ? data : nil
    }
}
