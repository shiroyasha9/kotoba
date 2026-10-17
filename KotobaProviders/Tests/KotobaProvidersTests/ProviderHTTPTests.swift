import Foundation
import Testing

@testable import KotobaProviders

struct ProviderHTTPTests {
    static let now = Date(timeIntervalSince1970: 784_111_747)  // Sun, 06 Nov 1994 08:49:07 GMT

    /// RFC 9110 section 10.2.3: seconds, or an HTTP date.
    @Test(arguments: [
        ("120", Duration.seconds(120)),
        ("Sun, 06 Nov 1994 08:49:37 GMT", .seconds(30)),
        ("Sun, 06 Nov 1994 08:48:37 GMT", .zero),
        ("soon", nil),
        ("-5", nil),
    ])
    func retryAfterReadsSecondsOrADate(header: String, expected: Duration?) {
        #expect(ProviderHTTP.retryAfter(header, now: Self.now) == expected)
    }
}
