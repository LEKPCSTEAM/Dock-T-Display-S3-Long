import Foundation
import Network

struct DiscoveredBoard: Identifiable, Equatable {
    let name: String
    let id: String
    let endpoint: NWEndpoint
}

@MainActor
final class Discovery: ObservableObject {
    @Published private(set) var boards: [DiscoveredBoard] = []
    var onChange: (() -> Void)?
    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_longdeck._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap(Self.board)
            Task { @MainActor in
                self?.boards = found.sorted { $0.name < $1.name }
                self?.onChange?()
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    private nonisolated static func board(_ result: NWBrowser.Result) -> DiscoveredBoard? {
        guard case .service(let name, _, _, _) = result.endpoint,
              case .bonjour(let txt) = result.metadata,
              let id = txt["id"], !id.isEmpty
        else { return nil }
        return DiscoveredBoard(name: name, id: id, endpoint: result.endpoint)
    }
}
