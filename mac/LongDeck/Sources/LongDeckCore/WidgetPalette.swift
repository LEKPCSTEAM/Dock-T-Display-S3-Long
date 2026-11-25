public enum LiveTitles {
    public static func metricName(_ m: StatMetric) -> String {
        switch m {
        case .cpu: return "CPU"
        case .ram: return "RAM"
        case .gpu: return "GPU"
        case .temp: return "Temp"
        case .netDown: return "Net down"
        case .netUp: return "Net up"
        case .diskFree: return "Disk free"
        case .diskIO: return "Disk I/O"
        case .battery: return "Battery"
        }
    }

    public static func styleName(_ s: StatStyle) -> String {
        switch s {
        case .bar: return "Bar"
        case .number: return "Number"
        case .sparkline: return "Sparkline"
        }
    }

    public static func title(_ kind: LiveKind) -> String {
        switch kind {
        case .stat(let m, let s): return "\(metricName(m)) · \(styleName(s).lowercased())"
        case .volume: return "Volume"
        case .clock: return "Clock"
        case .claudeSessions: return "Claude sessions"
        case .claudeUsage: return "Claude usage"
        case .claudeAgents: return "Claude agents"
        }
    }
}

public enum PaletteItem: String, CaseIterable, Sendable {
    case key, stat, volume, clock
    case claudeSessions = "claude_sessions"
    case claudeUsage = "claude_usage"
    case claudeAgents = "claude_agents"

    public var title: String {
        switch self {
        case .key: return "Key"
        case .stat: return "Stat"
        case .volume: return "Volume"
        case .clock: return "Clock"
        case .claudeSessions: return "Claude sessions"
        case .claudeUsage: return "Claude usage"
        case .claudeAgents: return "Claude agents"
        }
    }

    public var symbol: String {
        switch self {
        case .key: return "button.programmable"
        case .stat: return "chart.bar.fill"
        case .volume: return "speaker.wave.2.fill"
        case .clock: return "clock"
        case .claudeSessions: return "list.bullet.rectangle"
        case .claudeUsage: return "gauge.with.dots.needle.33percent"
        case .claudeAgents: return "person.3.sequence"
        }
    }

    public var defaultSize: CellSize {
        switch self {
        case .key: return CellSize(w: 1, h: 1)
        case .stat: return CellSize(w: 2, h: 1)
        case .volume: return CellSize(w: 3, h: 1)
        case .clock: return CellSize(w: 2, h: 1)
        case .claudeSessions: return CellSize(w: 4, h: 2)
        case .claudeUsage: return CellSize(w: 4, h: 1)
        case .claudeAgents: return CellSize(w: 8, h: 2)
        }
    }

    public var minSize: CellSize {
        self == .claudeSessions || self == .claudeAgents ? CellSize(w: 2, h: 1) : CellSize(w: 1, h: 1)
    }

    public var idBase: String {
        switch self {
        case .key: return "key"
        case .stat: return "cpu"
        case .volume: return "volume"
        case .clock: return "clock"
        case .claudeSessions: return "ccsessions"
        case .claudeUsage: return "ccusage"
        case .claudeAgents: return "ccagents"
        }
    }

    public func makeWidget(id: String, rect: CellRect) -> EditorWidget {
        func live(_ kind: LiveKind) -> EditorWidget {
            .live(LiveWidgetConfig(id: id, col: rect.col, row: rect.row, w: rect.w, h: rect.h, kind: kind))
        }
        switch self {
        case .key:
            return .key(KeyConfig(id: id, col: rect.col, row: rect.row, w: rect.w, h: rect.h,
                                  label: "Key", icon: nil, background: "#2B2B2B",
                                  action: .openApp(path: ""), longAction: nil, foreground: nil))
        case .stat: return live(.stat(.cpu, .sparkline))
        case .volume: return live(.volume)
        case .clock: return live(.clock)
        case .claudeSessions: return live(.claudeSessions)
        case .claudeUsage: return live(.claudeUsage)
        case .claudeAgents: return live(.claudeAgents)
        }
    }
}
