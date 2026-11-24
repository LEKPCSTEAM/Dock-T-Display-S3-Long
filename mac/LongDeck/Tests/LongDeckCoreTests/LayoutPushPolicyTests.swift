import Testing
@testable import LongDeckCore

@Suite struct LayoutPushPolicyTests {
    @Test func boundary() {
        #expect(LayoutPushPolicy.fits(frameBytes: 15360))
        #expect(!LayoutPushPolicy.fits(frameBytes: 15361))
    }
}
