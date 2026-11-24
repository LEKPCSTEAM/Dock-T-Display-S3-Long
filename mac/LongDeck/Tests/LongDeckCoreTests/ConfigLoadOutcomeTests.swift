import Foundation
import Testing
@testable import LongDeckCore

@Suite struct ConfigLoadOutcomeTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("longdeck-\(UUID().uuidString)/config.json")
    }

    @Test func missingFileIsMissing() {
        #expect(ConfigLoadOutcome.read(from: tempURL()) == .missing)
    }

    @Test func invalidFileIsInvalid() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ nope".utf8).write(to: url)
        guard case .invalid = ConfigLoadOutcome.read(from: url) else {
            Issue.record("expected invalid")
            return
        }
    }

    @Test func validFileIsLoaded() throws {
        let url = tempURL()
        try SampleConfig.dev.save(to: url)
        #expect(ConfigLoadOutcome.read(from: url) == .loaded(SampleConfig.dev))
    }
}
