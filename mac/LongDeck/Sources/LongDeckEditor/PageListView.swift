import LongDeckCore
import SwiftUI

final class RemoveConfirmation: ObservableObject {
    @Published var isPresented = false
}

struct PageListView: View {
    @ObservedObject var store: EditorStore
    @StateObject private var confirm = RemoveConfirmation()

    init(store: EditorStore) {
        self.store = store
    }

    private var count: Int { store.model.document.pages.count }
    private var index: Int { store.model.pageIndex }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding<Int?>(get: { store.model.pageIndex }, set: { if let i = $0 { store.selectPage(i) } })) {
                ForEach(0..<count, id: \.self) { i in
                    row(i).tag(i)
                }
            }
            Divider()
            HStack(spacing: 6) {
                Button("+") { store.addPage() }
                    .disabled(count >= DeckConfig.maxPages)
                    .help("Add page")
                Button("\u{2212}") {
                    if store.model.widgets(onPage: index).isEmpty {
                        store.removePage(at: index)
                    } else {
                        confirm.isPresented = true
                    }
                }
                    .disabled(count <= 1)
                    .help("Remove page")
                Button("\u{2191}") { store.movePage(from: index, to: index - 1) }
                    .disabled(index <= 0)
                    .help("Move page up")
                Button("\u{2193}") { store.movePage(from: index, to: index + 1) }
                    .disabled(index >= count - 1)
                    .help("Move page down")
            }
            .padding(8)
        }
        .frame(width: 200)
        .alert("Remove this page and its widgets?", isPresented: $confirm.isPresented) {
            Button("Remove", role: .destructive) { store.removePage(at: index) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func row(_ i: Int) -> some View {
        let page = store.model.document.pages[i]
        let widgets = store.model.widgets(onPage: i).count
        return HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(page.name.isEmpty ? "Untitled" : page.name).lineLimit(1)
                Text("\(widgets) widgets").font(.caption).foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
            if store.pageHasErrors(i) {
                Circle().fill(BoardColors.err).frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 2)
    }
}
