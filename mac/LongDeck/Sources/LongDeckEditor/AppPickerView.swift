import AppKit
import LongDeckCore
import SwiftUI
import UniformTypeIdentifiers

final class AppPickerState: ObservableObject {
    @Published var query = ""
    @Published var selection: String?
}

struct AppPickerView: View {
    let apps: [AppEntry]
    let onPick: (AppEntry) -> Void
    let onCancel: () -> Void
    @StateObject private var state: AppPickerState

    init(apps: [AppEntry], onPick: @escaping (AppEntry) -> Void, onCancel: @escaping () -> Void) {
        self.init(apps: apps, state: AppPickerState(), onPick: onPick, onCancel: onCancel)
    }

    init(apps: [AppEntry], state: AppPickerState, onPick: @escaping (AppEntry) -> Void,
         onCancel: @escaping () -> Void) {
        self.apps = apps
        self.onPick = onPick
        self.onCancel = onCancel
        _state = StateObject(wrappedValue: state)
    }

    private var rows: [AppEntry] { AppCatalog.filter(apps, query: state.query) }

    var body: some View {
        VStack(spacing: 12) {
            TextField("Search apps", text: $state.query)
                .textFieldStyle(.roundedBorder)
            List(rows, selection: $state.selection) { app in
                row(app)
            }
            HStack {
                Button("Other…") { chooseOther() }
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Choose") { pickSelection() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedEntry == nil)
            }
        }
        .padding(16)
        .frame(width: 420, height: 480)
    }

    private var selectedEntry: AppEntry? {
        guard let path = state.selection else { return nil }
        return apps.first { $0.path == path }
    }

    private func row(_ app: AppEntry) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: AppIconCache.shared.icon(path: app.path))
                .resizable()
                .frame(width: 24, height: 24)
            Text(app.name).lineLimit(1)
            Spacer(minLength: 8)
            Text(app.folder)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onPick(app) }
        .tag(app.path)
    }

    private func pickSelection() {
        if let entry = selectedEntry { onPick(entry) }
    }

    private func chooseOther() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let entry = AppCatalog.entry(forApp: url) else { return }
        onPick(entry)
    }
}

final class AppChooserState: ObservableObject {
    @Published var showing = false
    @Published var apps: [AppEntry] = []
    private var loaded = false

    @MainActor func open() {
        showing = true
        guard !loaded else { return }
        loaded = true
        Task { [weak self] in
            let found = await AppCatalog.scan(AppCatalog.standardRoots)
            self?.apps = found
        }
    }
}

struct AppChooser: View {
    let path: String?
    let onPick: (AppEntry) -> Void
    @StateObject private var chooser = AppChooserState()

    var body: some View {
        HStack(spacing: 8) {
            if let path, !path.isEmpty {
                Image(nsImage: AppIconCache.shared.icon(path: path))
                    .resizable()
                    .frame(width: 20, height: 20)
                Text(AppCatalog.name(forPath: path)).lineLimit(1)
            } else {
                Text("No app chosen").foregroundColor(.secondary)
            }
            Spacer(minLength: 4)
            Button("Choose…") { chooser.open() }
        }
        .sheet(isPresented: $chooser.showing) {
            AppPickerView(apps: chooser.apps, onPick: { app in
                chooser.showing = false
                onPick(app)
            }, onCancel: { chooser.showing = false })
        }
    }
}
