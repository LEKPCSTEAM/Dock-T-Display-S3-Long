import SwiftUI
import Testing

@Suite(.serialized) @MainActor struct HarnessSnapshotTests {
    @Test func harnessRendersControls() throws {
        let view = HStack {
            Toggle("On", isOn: .constant(true))
            Button("Save") {}
            Text("LongDeck")
        }.padding()
        let rep = Snapshot.render(view, size: CGSize(width: 360, height: 80))
        #expect(rep.pixelsWide == 720)
        #expect(rep.pixelsHigh == 160)
        #expect(!Snapshot.isUniform(rep))
        try Snapshot.save(rep, "harness")
    }
}
