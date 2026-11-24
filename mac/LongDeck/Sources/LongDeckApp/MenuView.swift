import SwiftUI

struct MenuView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.status.text)
        if let error = model.configError {
            Text("Config error: \(error)")
        }
        if let error = model.lastError {
            Text(error)
        }
        Divider()
        Button("Pair with board…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "pair")
        }
        Button("Reload config") { model.reloadConfig() }
        Button("Open config folder") { model.openConfigFolder() }
        if !model.isTrusted {
            Button("Grant Accessibility…") { model.openAccessibilitySettings() }
        }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}
