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
    @Published private(set) var needsPairing = false

    let discovery = Discovery()
    let system = RealSystemControl()
    let volume = CoreAudioVolume()
    private var sampler = StatsSampler(source: MacStatsSource())
    private var statsTimer: Timer?

    static let configURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LongDeck/config.json")
    private static let lastBoardKey = "lastBoardId"

    private var config: DeckConfig?
    private var connection: DeckConnection?
    private var policy = ReconnectPolicy()
    private var retryTask: Task<Void, Never>?
    private var dirWatcher: DispatchSourceFileSystemObject?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var debounce: Task<Void, Never>?
    private var trustTimer: Timer?

    @Published private(set) var isTrusted = true

    func start() {
        reloadConfig()
        watchConfig()
        observeSleep()
        refreshTrust()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshTrust() }
        }
        discovery.onChange = { [weak self] in self?.connectIfPossible() }
        discovery.start()
        volume.onChange = { [weak self] in
            guard let self else { return }
            self.connection?.sendVolume(self.volume.read())
        }
        volume.start()
        startStatsTimer()
    }

    private func startStatsTimer() {
        guard statsTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sendStatsTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        statsTimer = timer
    }

    private func stopStatsTimer() {
        statsTimer?.invalidate()
        statsTimer = nil
    }

    private func sendStatsTick() {
        guard let connection, connection.isReady else { return }
        connection.sendStats(sampler.sample(now: ProcessInfo.processInfo.systemUptime))
    }

    private func refreshTrust() {
        let trusted = system.isTrusted
        if trusted != isTrusted { isTrusted = trusted }
    }

    func reloadConfig() {
        switch ConfigLoadOutcome.read(from: Self.configURL) {
        case .missing:
            try? SampleConfig.dev.save(to: Self.configURL)
            apply(SampleConfig.dev)
        case .loaded(let loaded):
            apply(loaded)
        case .invalid(let message):
            configError = message
        }
    }

    private func apply(_ loaded: DeckConfig) {
        config = loaded
        configError = nil
        connection?.push(config: loaded)
    }

    private func observeSleep() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.dropConnection() }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.startStatsTimer()
                self?.policy.reset()
                self?.scheduleRetry()
            }
        }
    }

    private func dropConnection() {
        stopStatsTimer()
        retryTask?.cancel()
        connection?.close()
        connection = nil
        awaitingCode = false
        status = .offline
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
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }

    func startPairing(_ board: DiscoveredBoard) {
        retryTask?.cancel()
        awaitingCode = false
        codeRejected = false
        needsPairing = false
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
            configProvider: { [weak self] in self?.config }, volume: volume,
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
        case .boardForgotMac:
            KeyStore.delete(boardId: board.id)
            retryTask?.cancel()
            connection = nil
            awaitingCode = false
            status = .offline
            needsPairing = true
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
        dirWatcher = makeWatcher(path: dir.path, mask: [.write, .rename, .delete])
        armFileWatcher()
    }

    private func armFileWatcher() {
        fileWatcher?.cancel()
        fileWatcher = makeWatcher(path: Self.configURL.path, mask: [.write, .extend, .delete, .rename])
    }

    private func makeWatcher(path: String, mask: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: mask, queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleReload() }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private func scheduleReload() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.reloadConfig()
            self?.armFileWatcher()
        }
    }
}
