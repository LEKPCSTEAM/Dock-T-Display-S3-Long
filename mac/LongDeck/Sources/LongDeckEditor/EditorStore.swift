import Foundation
import LongDeckCore

@MainActor
public final class EditorStore: ObservableObject {
    @Published public private(set) var model: EditorModel {
        didSet { issues = model.issues(environment) }
    }
    @Published public private(set) var issues: [EditorIssue]
    @Published public var status: String
    @Published public private(set) var diskError: String?
    public var onSave: ((DeckConfig) -> SaveOutcome)?
    @Published private var pendingExternal: DeckConfig?
    private var overwriteArmed = false

    public var externalConflict: Bool { pendingExternal != nil }

    public var closePromptDetail: String {
        let base = "If you don't save, your changes are lost."
        return externalConflict ? "config.json changed on disk — Save will overwrite it. " + base : base
    }

    private let appRoots: [AppRoot]
    private let environment: IssueEnvironment
    private var cachedApps: [AppEntry]?

    public init(config: DeckConfig, onDisk: Bool, diskError: String?,
                appRoots: [AppRoot] = AppCatalog.standardRoots, environment: IssueEnvironment = .live) {
        let model = EditorModel(document: config, saved: onDisk ? config : nil)
        self.model = model
        self.environment = environment
        self.appRoots = appRoots
        self.issues = model.issues(environment)
        self.diskError = diskError
        if let diskError {
            self.status = "config.json on disk is invalid: \(diskError). Saving replaces it."
        } else {
            self.status = ""
        }
    }

    public var apps: [AppEntry] {
        if let cachedApps { return cachedApps }
        let scanned = AppCatalog.scan(appRoots)
        cachedApps = scanned
        return scanned
    }

    var sprites: AgentSprites? { environment.sprites }
    public var isDirty: Bool { model.isDirty }
    public var canSave: Bool { model.isDirty && !issues.contains { $0.severity == .error } }

    public func issues(forWidget id: String) -> [EditorIssue] {
        issues.filter { $0.widget == id }
    }

    public func pageHasErrors(_ index: Int) -> Bool {
        issues.contains { $0.severity == .error && $0.page == index }
    }

    public func selectPage(_ index: Int) { model.selectPage(index) }
    public func select(_ id: String?) { model.select(id) }

    public func reveal(_ issue: EditorIssue) {
        if let page = issue.page { model.selectPage(page) }
        if let widget = issue.widget { model.select(widget) }
    }

    public func addPage() { model.addPage() }
    public func removePage(at index: Int) { model.removePage(at: index) }
    public func movePage(from: Int, to: Int) { model.movePage(from: from, to: to) }
    public func renamePage(at index: Int, to name: String) { model.renamePage(at: index, to: name) }

    @discardableResult
    public func add(_ item: PaletteItem) -> String? {
        let id = model.add(item)
        status = id == nil ? "No room there" : ""
        return id
    }

    @discardableResult
    public func add(_ item: PaletteItem, col: Int, row: Int) -> String? {
        let id = model.add(item, col: col, row: row)
        status = id == nil ? "No room there" : ""
        return id
    }

    @discardableResult
    public func setFrame(_ id: String, _ rect: CellRect) -> Bool {
        let ok = model.setFrame(id, rect)
        status = ok ? "" : "No room there"
        return ok
    }

    public func remove(_ id: String) { model.remove(id) }

    public func updateKey(_ id: String, coalesce: String?, _ change: (inout KeyConfig) -> Void) {
        model.updateKey(id, coalesce: coalesce, change)
    }

    public func setStat(_ id: String, metric: StatMetric, style: StatStyle) {
        model.setStat(id, metric: metric, style: style)
    }

    public func setAction(_ action: DeckAction?, slot: ActionSlot, for id: String, coalesce: String?) {
        model.setAction(action, slot: slot, for: id, coalesce: coalesce)
    }

    public func chooseApp(_ app: AppEntry, slot: ActionSlot, for id: String) {
        model.chooseApp(app, slot: slot, for: id)
    }

    public func undo() { model.undo() }
    public func redo() { model.redo() }

    @discardableResult
    public func save(overwriteConfirmed: Bool = false) -> Bool {
        let errors = issues.filter { $0.severity == .error }.count
        guard errors == 0 else {
            status = "Fix \(errors) error(s) before saving"
            return false
        }
        if externalConflict && !overwriteArmed && !overwriteConfirmed {
            overwriteArmed = true
            status = "config.json changed on disk. Save again to overwrite it."
            return false
        }
        let outcome = onSave?(model.document) ?? .failed("Saving is not available")
        switch outcome {
        case .sent:
            markSaved("Saved. Sending to the board.")
            return true
        case .savedOffline:
            markSaved("Saved. The board updates when it connects.")
            return true
        case .failed(let message):
            status = "Not saved: \(message)"
            return false
        }
    }

    public func externalChange(_ config: DeckConfig) {
        diskError = nil
        if model.matchesSaved(config) {
            pendingExternal = nil
            overwriteArmed = false
            return
        }
        model.externalChange(config)
        if model.isDirty && config != model.document {
            pendingExternal = config
            overwriteArmed = false
        } else {
            pendingExternal = nil
        }
    }

    public func externalInvalid(_ message: String) {
        diskError = message
    }

    public func reloadFromDisk() {
        guard let config = pendingExternal else { return }
        model.load(config)
        pendingExternal = nil
        diskError = nil
        status = ""
    }

    private func markSaved(_ message: String) {
        model.markSaved()
        pendingExternal = nil
        diskError = nil
        status = message
    }
}
