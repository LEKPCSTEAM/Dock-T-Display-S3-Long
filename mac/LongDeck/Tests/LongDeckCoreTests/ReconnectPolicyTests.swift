import Testing
@testable import LongDeckCore

@Suite struct ReconnectPolicyTests {
    @Test func sequenceAndReset() {
        var policy = ReconnectPolicy()
        #expect((0..<7).map { _ in policy.nextDelay() } == [1, 2, 4, 8, 15, 15, 15])
        policy.reset()
        #expect(policy.nextDelay() == 1)
    }
}
