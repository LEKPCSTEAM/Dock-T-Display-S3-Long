import SwiftUI

@main
struct LongDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel

    init() {
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        DispatchQueue.main.async { model.start() }
    }

    var body: some Scene {
        MenuBarExtra("LongDeck", systemImage: "square.grid.3x3") {
            MenuView(model: model, claude: model.claude)
        }
        Window("Pair with board", id: "pair") {
            PairView(model: model, discovery: model.discovery)
        }
        .windowResizability(.contentSize)
    }
}
