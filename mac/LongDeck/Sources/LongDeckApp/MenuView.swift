import SwiftUI

struct MenuView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var claude: ClaudeController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.status.text)
        if let error = model.configError {
            Text("Config error: \(error)")
        }
        if model.needsPairing {
            Text("Board forgot this Mac. Pair again")
        }
        if let error = model.lastError {
            Text(error)
        }
        Divider()
        Button("Pair with board…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "pair")
        }
        Button("Edit layout…") { model.openEditor() }
        Button("Reload config") { model.reloadConfig() }
        Button("Open config folder") { model.openConfigFolder() }
        if !model.isTrusted {
            Button("Grant Accessibility…") { model.openAccessibilitySettings() }
        }
        Divider()
        Text(claude.statusText)
        if claude.installed {
            if !claude.hooksCurrent {
                Button("Reinstall Claude hooks (adds subagent count)") { claude.install() }
            }
            Button("Uninstall Claude Code integration…") { claude.uninstall() }
        } else {
            Button("Install Claude Code integration…") { claude.install() }
        }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}
