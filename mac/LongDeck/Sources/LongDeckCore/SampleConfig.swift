public enum SampleConfig {
    public static let dev: DeckConfig = {
        func key(_ id: String, _ col: Int, _ row: Int, _ label: String, _ icon: IconRef?,
                 _ background: String, _ action: DeckAction, long: DeckAction? = nil) -> KeyConfig {
            KeyConfig(id: id, col: col, row: row, w: 1, h: 1, label: label, icon: icon,
                      background: background, action: action, longAction: long)
        }
        func app(_ path: String) -> IconRef { .app(path: path) }
        func symbol(_ name: String) -> IconRef { .symbol(name: name) }
        let keys = [
            key("vscode", 0, 0, "VS Code", app("/Applications/Visual Studio Code.app"), "#1F3A5F",
                .openApp(path: "/Applications/Visual Studio Code.app")),
            key("iterm", 1, 0, "iTerm", app("/Applications/iTerm.app"), "#1E1E1E",
                .openApp(path: "/Applications/iTerm.app")),
            key("chrome", 2, 0, "Chrome", app("/Applications/Google Chrome.app"), "#3B3B3B",
                .openApp(path: "/Applications/Google Chrome.app")),
            key("spotlight", 3, 0, "Spotlight", symbol("magnifyingglass"), "#444B6E",
                .hotkey(keyCode: 49, modifiers: [.command])),
            key("screenshot", 4, 0, "Shot", symbol("camera.viewfinder"), "#5A3E6B",
                .hotkey(keyCode: 21, modifiers: [.command, .shift])),
            key("github", 5, 0, "GitHub", symbol("globe"), "#24292E",
                .openURL("https://github.com")),
            key("work", 6, 0, "WORK", symbol("terminal"), "#2E4A3A",
                .shell("open ~/WORK")),
            key("shortcut", 7, 0, "Shortcut", symbol("bolt.fill"), "#6B4E1F",
                .shortcut("LongDeck Demo")),
            key("prev", 0, 1, "Prev", symbol("backward.fill"), "#2B2B2B", .media(.previous)),
            key("play", 1, 1, "Play", symbol("playpause.fill"), "#2B2B2B", .media(.playPause)),
            key("next", 2, 1, "Next", symbol("forward.fill"), "#2B2B2B", .media(.next)),
            key("mute", 3, 1, "Mute", symbol("speaker.slash.fill"), "#4A2B2B", .volume(.mute)),
            key("voldown", 4, 1, "Vol -", symbol("speaker.wave.1.fill"), "#2B3A4A", .volume(.down)),
            key("volup", 5, 1, "Vol +", symbol("speaker.wave.3.fill"), "#2B3A4A", .volume(.up)),
            key("text", 6, 1, "Text", symbol("text.cursor"), "#3A3A2B",
                .typeText("Hello from LongDeck")),
            key("finder", 7, 1, "Finder", app("/System/Library/CoreServices/Finder.app"), "#1F4A5F",
                .openApp(path: "/System/Library/CoreServices/Finder.app"),
                long: .openURL("file:///Applications")),
        ]
        func live(_ id: String, _ col: Int, _ row: Int, _ w: Int, _ kind: LiveKind) -> LiveWidgetConfig {
            LiveWidgetConfig(id: id, col: col, row: row, w: w, h: 1, kind: kind)
        }
        let macLive = [
            live("cpu", 0, 0, 2, .stat(.cpu, .sparkline)),
            live("gpu", 2, 0, 2, .stat(.gpu, .sparkline)),
            live("ram", 4, 0, 2, .stat(.ram, .bar)),
            live("clock", 6, 0, 2, .clock),
            live("temp", 0, 1, 1, .stat(.temp, .number)),
            live("netdown", 1, 1, 1, .stat(.netDown, .number)),
            live("netup", 2, 1, 1, .stat(.netUp, .number)),
            live("diskio", 3, 1, 1, .stat(.diskIO, .sparkline)),
            live("diskfree", 4, 1, 1, .stat(.diskFree, .bar)),
            live("volume", 5, 1, 3, .volume),
        ]
        return DeckConfig(version: 1, pages: [
            PageConfig(name: "Dev", keys: keys),
            PageConfig(name: "Mac", keys: [], live: macLive),
        ])
    }()
}
