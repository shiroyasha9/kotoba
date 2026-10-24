import Testing

@testable import KotobaCore

/// The page the main window opens at from the stored name, across releases.
struct PaneIDTests {
    @Test func aStoredPageOpensAsItself() {
        for page in PaneID.allCases {
            #expect(PaneID(saved: page.rawValue) == page)
        }
    }

    /// 0.4.6 had Insights and Usage; 0.5.0 has Activity in their place.
    @Test func zeroFourInsightsAndUsageOpenActivity() {
        #expect(PaneID(saved: "insights") == .activity)
        #expect(PaneID(saved: "usage") == .activity)
    }

    @Test func noStoredPageOrAnUnknownOneHasNone() {
        #expect(PaneID(saved: nil) == nil)
        #expect(PaneID(saved: "somethingElse") == nil)
    }
}
