import LongDeckCore
import SwiftUI

extension EditorIssue {
    var stableId: String { "\(page.map(String.init) ?? "-")|\(widget ?? "-")|\(message)" }
}

struct IssueListView: View {
    @ObservedObject var store: EditorStore

    init(store: EditorStore) {
        self.store = store
    }

    private var sorted: [EditorIssue] {
        store.issues.filter { $0.severity == .error } + store.issues.filter { $0.severity == .warning }
    }

    var body: some View {
        Group {
            if store.issues.isEmpty {
                Text("No issues").foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(sorted, id: \.stableId) { issue in
                            Text(line(issue))
                                .font(.system(size: 12))
                                .foregroundColor(issue.severity == .error ? BoardColors.err : BoardColors.warn)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture { store.reveal(issue) }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 140)
    }

    private func line(_ issue: EditorIssue) -> String {
        var parts = issue.severity == .error ? "\u{26D4}\u{FE0E} " : "\u{26A0}\u{FE0E} "
        if let page = issue.page, page < store.model.document.pages.count {
            let name = store.model.document.pages[page].name
            parts += name.isEmpty ? "Untitled" : name
            if issue.widget != nil { parts += " \u{00B7} " }
        }
        if let widget = issue.widget { parts += widget }
        if issue.page != nil || issue.widget != nil { parts += ": " }
        return parts + issue.message
    }
}
