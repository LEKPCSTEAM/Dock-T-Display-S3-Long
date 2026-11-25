import Foundation

public struct EditorIssue: Equatable, Sendable {
    public enum Severity: String, Sendable { case error, warning }
    public var severity: Severity
    public var page: Int?
    public var widget: String?
    public var message: String

    public init(severity: Severity, page: Int?, widget: String?, message: String) {
        self.severity = severity
        self.page = page
        self.widget = widget
        self.message = message
    }
}

public struct IssueEnvironment: Sendable {
    public var fileExists: @Sendable (String) -> Bool
    public var symbolExists: @Sendable (String) -> Bool
    public var sprites: AgentSprites?

    public init(fileExists: @escaping @Sendable (String) -> Bool,
                symbolExists: @escaping @Sendable (String) -> Bool,
                sprites: AgentSprites? = nil) {
        self.fileExists = fileExists
        self.symbolExists = symbolExists
        self.sprites = sprites
    }

    public static let live = IssueEnvironment(
        fileExists: { FileManager.default.fileExists(atPath: $0) },
        symbolExists: { SymbolCatalog.exists($0) },
        sprites: AgentSprites.bundled())

    public static let permissive = IssueEnvironment(fileExists: { _ in true }, symbolExists: { _ in true })
}

public enum EditorIssues {
    public static func check(_ config: DeckConfig, _ env: IssueEnvironment) -> [EditorIssue] {
        var out: [EditorIssue] = []
        if config.pages.count > DeckConfig.maxPages {
            out.append(EditorIssue(severity: .error, page: nil, widget: nil,
                                   message: "\(config.pages.count) pages, the board takes at most \(DeckConfig.maxPages)"))
        }
        let bytes = LayoutSize.sealedBytes(config, sprites: env.sprites)
        if !LayoutPushPolicy.fits(frameBytes: bytes) {
            out.append(EditorIssue(
                severity: .error, page: nil, widget: nil,
                message: "Layout is \(bytes) bytes, the board takes at most \(LayoutPushPolicy.maxWebSocketFrame). Remove widgets or pages."))
        }
        var usedIds = Set<String>()
        for (index, page) in config.pages.enumerated() {
            func error(_ widget: String?, _ message: String) {
                out.append(EditorIssue(severity: .error, page: index, widget: widget, message: message))
            }
            let nameBytes = page.name.utf8.count
            if nameBytes > DeckConfig.maxPageNameBytes {
                error(nil, "Page name is \(nameBytes) bytes, at most \(DeckConfig.maxPageNameBytes)")
            }
            let widgets = EditorGrid.widgets(of: page)
            if widgets.count > DeckConfig.maxWidgetsPerPage {
                error(nil, "\(widgets.count) widgets, at most \(DeckConfig.maxWidgetsPerPage) per page")
            }
            for (i, widget) in widgets.enumerated() {
                let id = widget.id
                if id.isEmpty {
                    error(id, "Widget id is empty")
                } else {
                    if id.utf8.count > DeckConfig.maxKeyIdBytes {
                        error(id, "Widget id is \(id.utf8.count) bytes, at most \(DeckConfig.maxKeyIdBytes)")
                    }
                    if !usedIds.insert(id).inserted { error(id, "Widget id \(id) is used twice") }
                }
                let frame = widget.frame
                if !frame.isInGrid { error(id, "Outside the 8x2 grid") }
                if let earlier = widgets[..<i].first(where: { $0.frame.intersects(frame) }) {
                    error(id, "Overlaps \(earlier.id)")
                }
                switch widget {
                case .live(let l):
                    if l.kind == .claudeSessions && l.w < 2 {
                        error(id, "Claude sessions needs at least 2 columns")
                    }
                    if l.kind == .claudeAgents && l.w < 2 {
                        error(id, "claude_agents needs at least 2 columns")
                    }
                case .key(let k):
                    out += keyIssues(k, page: index, env: env)
                }
            }
        }
        return out
    }

    private static func keyIssues(_ k: KeyConfig, page: Int, env: IssueEnvironment) -> [EditorIssue] {
        var out: [EditorIssue] = []
        func add(_ severity: EditorIssue.Severity, _ message: String) {
            out.append(EditorIssue(severity: severity, page: page, widget: k.id, message: message))
        }
        if HexColor.parse(k.background) == nil { add(.error, "Background must be #RRGGBB") }
        if let fg = k.foreground, HexColor.parse(fg) == nil { add(.error, "Text colour must be #RRGGBB") }
        for (action, prefix) in [(k.action, ""), (k.longAction, "Long press: ")] {
            guard let action else { continue }
            for message in actionErrors(action) { add(.error, prefix + message) }
        }
        for (action, prefix) in [(k.action, ""), (k.longAction, "Long press: ")] {
            if case .openApp(let path)? = action, !path.isEmpty, !env.fileExists(path) {
                add(.warning, prefix + "App not found: \(path)")
            }
        }
        switch k.icon {
        case .app(let path)?:
            if path.isEmpty {
                add(.warning, "Choose an app for the icon")
            } else if !env.fileExists(path) {
                add(.warning, "Icon app not found: \(path)")
            }
        case .symbol(let name)?:
            if !env.symbolExists(name) { add(.warning, "Unknown SF Symbol \(name)") }
        case nil:
            if k.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                add(.warning, "Key shows nothing: add a label or an icon")
            }
        }
        return out
    }

    private static func actionErrors(_ action: DeckAction) -> [String] {
        func blank(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        switch action {
        case .openApp(let path): return path.isEmpty ? ["Choose an app"] : []
        case .openURL(let s):
            if blank(s) { return ["Enter a URL"] }
            if let url = URL(string: s), let scheme = url.scheme, !scheme.isEmpty { return [] }
            return ["URL is not valid, include a scheme like https://"]
        case .hotkey(let code, _): return code == ActionKind.unsetKeyCode ? ["Record a hotkey"] : []
        case .typeText(let s): return s.isEmpty ? ["Enter text to type"] : []
        case .shell(let s): return blank(s) ? ["Enter a shell command"] : []
        case .shortcut(let s): return blank(s) ? ["Enter a Shortcut name"] : []
        case .media, .volume: return []
        }
    }
}
