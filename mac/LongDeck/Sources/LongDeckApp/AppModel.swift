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
    let claude = ClaudeController()
    private var sampler = StatsSampler(source: MacStatsSource())
    private var statsTimer: Timer?

    static let configURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LongDeck/config.json")
    static let spritesDir = configURL.deletingLastPathComponent().appendingPathComponent("sprites", isDirectory: true)
    private static let spriteFiles = ["claude-agent.json", "claude-agent.png", "claude-hats.json", "claude-hats.png"]
    private static let lastBoardKey = "lastBoardId"

    private var config: DeckConfig?
    private var sprites: AgentSprites?
    private var spriteWatchers: [DispatchSourceFileSystemObject] = []
    private var spriteDebounce: Task<Void, Never>?
    private var connection: DeckConnection?
    private var policy = ReconnectPolicy()
    private var retryTask: Task<Void, Never>?
    private var dirWatcher: DispatchSourceFileSystemObject?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var debounce: Task<Void, Never>?
    private var trustTimer: Timer?
    private var writeGuard = ConfigWriteGuard()
    var onConfigApplied: ((DeckConfig) -> Void)?
    var onConfigInvalid: ((String) -> Void)?
    lazy var editorWindow = EditorWindowController(model: self)

    @Published private(set) var isTrusted = true

    func start() {
        sprites = Self.loadSprites()
        reloadConfig()
        watchConfig()
        armSpriteWatchers()
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
        claude.onBody = { [weak self] in self?.connection?.sendClaude($0) }
        claude.start()
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
        writeGuard.reset()
        switch ConfigLoadOutcome.read(from: Self.configURL) {
        case .missing:
            if let data = try? SampleConfig.dev.save(to: Self.configURL) { writeGuard.recordWrite(data) }
            apply(SampleConfig.dev)
        case .loaded(let loaded):
            apply(loaded)
        case .invalid(let message):
            configError = message
            onConfigInvalid?(message)
        }
    }

    private func apply(_ loaded: DeckConfig) {
        config = loaded
        configError = nil
        connection?.push(config: loaded)
        onConfigApplied?(loaded)
    }

    func openEditor() {
        editorWindow.show()
    }

    func editorDocument() -> (config: DeckConfig, onDisk: Bool, diskError: String?) {
        (config ?? SampleConfig.dev, config != nil && configError == nil, configError)
    }

    func editorEnvironment() -> IssueEnvironment {
        IssueEnvironment(
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            symbolExists: { SymbolCatalog.exists($0) },
            sprites: sprites)
    }

    private static func loadSprites() -> AgentSprites? {
        AgentSprites.loadFiles(in: spritesDir) ?? AgentSprites.bundled()
    }

    private func armSpriteWatchers() {
        spriteWatchers.forEach { $0.cancel() }
        spriteWatchers = []
        try? FileManager.default.createDirectory(at: Self.spritesDir, withIntermediateDirectories: true)
        let paths = [Self.spritesDir.path] + Self.spriteFiles.map { Self.spritesDir.appendingPathComponent($0).path }
        spriteWatchers = paths.compactMap {
            makeWatcher(path: $0, mask: [.write, .extend, .delete, .rename]) { [weak self] in self?.scheduleSpriteReload() }
        }
    }

    private func scheduleSpriteReload() {
        spriteDebounce?.cancel()
        spriteDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.reloadSprites()
            self?.armSpriteWatchers()
        }
    }

    private func reloadSprites() {
        let loaded = Self.loadSprites()
        guard loaded != sprites else { return }
        sprites = loaded
        if let config { connection?.push(config: config) }
    }

    func saveFromEditor(_ config: DeckConfig) -> SaveOutcome {
        do {
            let data = try ConfigSaver.prepare(config, sprites: sprites)
            try ConfigSaver.write(data, to: Self.configURL)
            writeGuard.recordWrite(data)
            apply(config)
            return connection?.isReady == true ? .sent : .savedOffline
        } catch {
            return .failed("\(error)")
        }
    }

    private func reloadFromWatcher() {
        if let data = try? Data(contentsOf: Self.configURL), writeGuard.matches(data) { return }
        reloadConfig()
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
            if let data = try? SampleConfig.dev.save(to: Self.configURL) { writeGuard.recordWrite(data) }
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
            configProvider: { [weak self] in self?.config }, spritesProvider: { [weak self] in self?.sprites },
            volume: volume,
            claudeBody: { [weak self] in self?.claude.currentBody.isEmpty == false ? self?.claude.currentBody : nil },
            onClaudeAction: { [weak self] body in
                self?.claude.handleAction(body) { [weak self] ack in self?.connection?.sendClaudeAck(ack) }
            },
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

    private func makeWatcher(
        path: String, mask: DispatchSource.FileSystemEvent, onChange: (@MainActor () -> Void)? = nil
    ) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: mask, queue: .main)
        source.setEventHandler { [weak self] in
            if let onChange { onChange() } else { self?.scheduleReload() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private func scheduleReload() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.reloadFromWatcher()
            self?.armFileWatcher()
        }
    }
}
