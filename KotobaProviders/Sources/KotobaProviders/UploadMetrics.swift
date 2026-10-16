import Foundation
import KotobaCore
import Synchronization
import os

/// Reads one upload's network metrics: logs how it connected, next to the pipeline's latency line (a reused
/// connection means the key-down warm-up worked; a new one shows its connect and TLS cost; the interface shows a VPN
/// tunnel), and keeps the moments the transcript hands to the latency log.
final class UploadMetrics: NSObject, URLSessionTaskDelegate, Sendable {
    private let label: String
    private let interfaces: InterfaceMemo
    private let measured = Mutex<NetworkTiming?>(nil)

    init(_ label: String, interfaces: InterfaceMemo) {
        self.label = label
        self.interfaces = interfaces
    }

    /// The upload's moments, read once `upload` returned; nil when the metrics had not come. URLSession does not
    /// document the order of the metrics and the answer; in a probe (2026-10-16, 14 uploads of 300 KB over HTTP/1.1
    /// and HTTP/2) the metrics came 50-1,000 µs before `upload` returned every time. The answer never waits for
    /// them: late metrics only leave the marks out.
    var timing: NetworkTiming? { measured.withLock { $0 } }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        // Runs before `upload` returns, so on the stop path: date arithmetic, a log line, and an interface lookup only
        // when the local address changed.
        let now = ContinuousClock.now
        let wall = Date()
        guard let last = metrics.transactionMetrics.last else { return }
        let connected = last.isReusedConnection ? nil : last.secureConnectionEndDate ?? last.connectEndDate
        measured.withLock {
            $0 = Self.timing(
                requestEnd: last.requestEndDate, responseStart: last.responseStartDate, connected: connected,
                wall: wall, now: now)
        }
        let interface = last.localAddress.flatMap(interfaces.name(holding:)) ?? "unknown"
        Log.latency.notice(
            """
            upload \(self.label, privacy: .public): reused \(last.isReusedConnection, privacy: .public), \
            protocol \(last.networkProtocolName ?? "unknown", privacy: .public), \
            interface \(interface, privacy: .public), \
            sent \(last.countOfRequestBodyBytesSent, privacy: .public) bytes, \
            connect \(Self.milliseconds(last.connectStartDate, last.connectEndDate), privacy: .public), \
            tls \(Self.milliseconds(last.secureConnectionStartDate, last.secureConnectionEndDate), privacy: .public), \
            upload \(Self.milliseconds(last.requestStartDate, last.requestEndDate), privacy: .public), \
            wait \(Self.milliseconds(last.requestEndDate, last.responseStartDate), privacy: .public)
            """
        )
    }

    /// The metrics' wall-clock dates moved onto the pipeline clock: `now` and `wall` are the same moment on each.
    /// Nil without both request end and response start (a failed or cancelled request).
    static func timing(
        requestEnd: Date?, responseStart: Date?, connected: Date?, wall: Date, now: ContinuousClock.Instant
    ) -> NetworkTiming? {
        guard let requestEnd, let responseStart else { return nil }
        func instant(_ date: Date) -> ContinuousClock.Instant { now - .seconds(wall.timeIntervalSince(date)) }
        return NetworkTiming(
            connected: connected.map(instant), uploadSent: instant(requestEnd), firstByte: instant(responseStart))
    }

    /// The name of the interface whose address is `address` (the connection's local address): `en0` for Wi-Fi, a
    /// `utun` for a VPN tunnel. Nil when no interface has it, or for a link-local IPv6 address (the system stores its
    /// scope inside the address bytes; an upload to a public host never uses one). Compares the binary addresses:
    /// formatting each interface's address with `getnameinfo` cost about 90 µs on 26 interfaces.
    static func interface(holding address: String) -> String? {
        let host = String(address.prefix(while: { $0 != "%" }))
        var ipv4 = in_addr()
        var ipv6 = in6_addr()
        let family: Int32
        if inet_pton(AF_INET, host, &ipv4) == 1 {
            family = AF_INET
        } else if inet_pton(AF_INET6, host, &ipv6) == 1 {
            family = AF_INET6
        } else {
            return nil
        }
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let socket = entry.pointee.ifa_addr, Int32(socket.pointee.sa_family) == family else { continue }
            let isMatch =
                family == AF_INET
                ? socket.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    $0.pointee.sin_addr.s_addr == ipv4.s_addr
                }
                : socket.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { candidate in
                    withUnsafeBytes(of: candidate.pointee.sin6_addr) { lhs in
                        withUnsafeBytes(of: ipv6) { lhs.elementsEqual($0) }
                    }
                }
            if isMatch { return String(cString: entry.pointee.ifa_name) }
        }
        return nil
    }

    private static func milliseconds(_ start: Date?, _ end: Date?) -> String {
        guard let start, let end else { return "none" }
        return "\(Int((end.timeIntervalSince(start) * 1000).rounded())) ms"
    }
}

/// The interface of one connection's last local address. The address changes only with the network, so most uploads
/// skip the lookup (about 28 µs, mostly `getifaddrs`). One per `ProviderConnection`, so two hosts reached over
/// different interfaces (a split tunnel) do not evict each other.
final class InterfaceMemo: Sendable {
    private let last = Mutex<(address: String, name: String?)?>(nil)

    func name(holding address: String) -> String? {
        if let last = last.withLock({ $0 }), last.address == address { return last.name }
        let name = UploadMetrics.interface(holding: address)
        last.withLock { $0 = (address, name) }
        return name
    }
}
