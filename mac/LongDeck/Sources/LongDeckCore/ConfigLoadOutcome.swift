import Foundation

public enum ConfigLoadOutcome: Equatable {
    case missing
    case loaded(DeckConfig)
    case invalid(String)

    public static func read(from url: URL) -> ConfigLoadOutcome {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do {
            let config = try JSONDecoder().decode(DeckConfig.self, from: Data(contentsOf: url))
            try config.validate()
            return .loaded(config)
        } catch {
            return .invalid("\(error)")
        }
    }
}
