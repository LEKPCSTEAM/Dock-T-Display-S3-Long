import AppKit
import Foundation
import LongDeckCore

enum DeckStatus: Equatable {
    case offline
    case connecting
    case pairing
    case connected(String)

    var text: String {
        switch self {
        case .offline: return "Offline"
        case .connecting: return "Connecting"
        case .pairing: return "Pairing"
        case .connected(let id): return "Connected to \(id)"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var status: DeckStatus = .offline
    @Published private(set) var configError: String?
    @Published private(set) var lastError: String?
    @Published private(set) var awaitingCode = false
    @Published private(set) var codeRejected = false
    @Published private(set) var currentPage = -1

    let discovery = Discovery()
    let system = RealSystemControl()

    static let configURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LongDeck/config.json")
    private static let lastBoardKey = "lastBoardId"

    private var config: DeckConfig = SampleConfig.dev
    private var connection: DeckConnection?
    private var policy = ReconnectPolicy()
    private var retryTask: Task<Void, Never>?
    private var watcher: DispatchSourceFileSystemObject?
    private var debounce: Task<Void, Never>?

    var isTrusted: Bool { system.isTrusted }

    func start() {
        reloadConfig()
        watchConfig()
        discovery.onChange = { [weak self] in self?.connectIfPossible() }
        discovery.start()
    }

    func reloadConfig() {
        do {
            let loaded = try DeckConfig.load(from: Self.configURL)
            config = loaded
            configError = nil
            connection?.push(config: loaded)
        } catch {
            configError = "\(error)"
        }
    }

    func openConfigFolder() {
        let dir = Self.configURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: Self.configURL.path) {
            try? SampleConfig.dev.save(to: Self.configURL)
        }
        NSWorkspace.shared.activateFileViewerSelecting([Self.configURL])
    }

    func openAccessibilitySettings() {
        let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }

    func startPairing(_ board: DiscoveredBoard) {
        retryTask?.cancel()
        awaitingCode = false
        codeRejected = false
        connect(board, pairing: true)
    }

    func submitPairCode(_ code: String) {
        codeRejected = false
        connection?.submitPairCode(code)
    }

    func cancelPairing() {
        guard status == .pairing else { return }
        connection?.close()
        connection = nil
        awaitingCode = false
        status = .offline
        connectIfPossible()
    }

    private func connectIfPossible() {
        guard connection == nil,
              let id = UserDefaults.standard.string(forKey: Self.lastBoardKey),
              KeyStore.load(boardId: id) != nil,
              let board = discovery.boards.first(where: { $0.id == id })
        else { return }
        connect(board, pairing: false)
    }

    private func connect(_ board: DiscoveredBoard, pairing: Bool) {
        connection?.close()
        status = pairing ? .pairing : .connecting
        let conn = DeckConnection(
            board: board, pairing: pairing, runner: ActionRunner(system: system),
            configProvider: { [weak self] in self?.config ?? SampleConfig.dev },
            onEvent: { [weak self] event in self?.handle(event, from: board) }
        )
        connection = conn
        conn.connect()
    }

    private func handle(_ event: ConnectionEvent, from board: DiscoveredBoard) {
        switch event {
        case .needPairCode:
            awaitingCode = true
        case .codeRejected:
            codeRejected = true
        case .ready(let boardId):
            UserDefaults.standard.set(boardId, forKey: Self.lastBoardKey)
            policy.reset()
            awaitingCode = false
            lastError = nil
            status = .connected(boardId)
        case .pageChanged(let index):
            currentPage = index
        case .actionFailed(let message):
            lastError = message
        case .closed(let reason):
            connection = nil
            awaitingCode = false
            status = .offline
            if let reason { lastError = "Link closed: \(reason)" }
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        let delay = policy.nextDelay()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.connectIfPossible()
        }
    }

    private func watchConfig() {
        let dir = Self.configURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            self?.debounce?.cancel()
            self?.debounce = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                self?.reloadConfig()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }
}
