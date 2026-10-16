import Foundation
import KotobaCore
import Testing

@testable import KotobaProviders

/// The upload's metrics moved onto the pipeline clock, and the interface the connection used.
struct UploadMetricsTests {
    private let wall = Date(timeIntervalSince1970: 1_800_000_000)
    private let now = ContinuousClock.now

    @Test func metricsDatesLandOnThePipelineClockAtTheSameDistanceFromNow() throws {
        let timing = try #require(
            UploadMetrics.timing(
                requestEnd: wall - 0.6, responseStart: wall - 0.05, isReused: false, connected: wall - 0.7,
                at: (wall, now)))

        #expect(magnitude(timing.uploadSent - (now - .milliseconds(600))) < .microseconds(1))
        #expect(magnitude(timing.firstByte - (now - .milliseconds(50))) < .microseconds(1))
        let connected = try #require(timing.connected)
        #expect(magnitude(connected - (now - .milliseconds(700))) < .microseconds(1))
    }

    @Test func aReusedConnectionHasNoConnectedMoment() throws {
        let timing = try #require(
            UploadMetrics.timing(
                requestEnd: wall - 0.6, responseStart: wall, isReused: true, connected: wall - 0.7, at: (wall, now)))

        #expect(timing.connected == nil)
    }

    @Test func aRequestWithNoAnswerHasNoTiming() {
        #expect(
            UploadMetrics.timing(
                requestEnd: wall - 0.6, responseStart: nil, isReused: false, connected: nil, at: (wall, now))
                == nil)
        #expect(
            UploadMetrics.timing(
                requestEnd: nil, responseStart: nil, isReused: false, connected: nil, at: (wall, now)) == nil)
    }

    @Test func theLoopbackAddressIsOnTheLoopbackInterface() {
        #expect(UploadMetrics.interface(holding: "127.0.0.1") == "lo0")
        #expect(UploadMetrics.interface(holding: "::1") == "lo0")
    }

    @Test func theMemoAnswersLikeTheLookupAsTheAddressChanges() {
        let memo = InterfaceMemo()
        #expect(memo.name(holding: "127.0.0.1") == "lo0")
        #expect(memo.name(holding: "127.0.0.1") == "lo0")
        #expect(memo.name(holding: "192.0.2.77") == nil)
        #expect(memo.name(holding: "::1") == "lo0")
    }

    @Test func anAddressNoInterfaceHoldsHasNoInterface() {
        #expect(UploadMetrics.interface(holding: "192.0.2.77") == nil)
    }

    /// Guards a system behaviour the fixture tests rely on: a `URLProtocol` load yields no `NetworkTiming`, so a
    /// stubbed transcript equals one built without `network`.
    @Test func aStubbedAnswerCarriesNoNetworkTiming() async throws {
        let stub = StubHost(reply: .fixture("xai-success"))
        stub.settings.route = .xaiGrok

        let transcript = try await stub.provider().transcribe(stub.request(terms: []))

        #expect(transcript.network == nil)
    }
}

/// Distance between two instants either way round.
private func magnitude(_ duration: Duration) -> Duration {
    duration < .zero ? .zero - duration : duration
}
