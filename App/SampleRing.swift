import Foundation
import Synchronization

/// Single-producer, single-consumer ring of mono samples. The IO thread pushes; the writer thread
/// reads. `written` publishes frames with release/acquire ordering, so neither side locks.
final class SampleRing: Sendable {
    /// About 1.4 s at 48 kHz; the writer drains it every hardware cycle (about 10 ms).
    static let capacity = 1 << 16

    /// Total frames pushed since launch; the writer keeps its own read position.
    let written = Atomic<Int>(0)
    /// Host time of the first sample pushed after `beginCapture`, 0 until then.
    let firstHostTime = Atomic<UInt64>(0)
    /// Host time just after the last pushed sample.
    let lastEndHostTime = Atomic<UInt64>(0)
    /// Signalled once per push, and by stop requests.
    let wake = DispatchSemaphore(value: 0)
    // Only the IO thread writes slots, only past `written`; the writer reads only before it.
    nonisolated(unsafe) private let storage: UnsafeMutablePointer<Float>

    /// Not zero-filled: a slot is read only after `push` wrote it, and untouched pages stay out of
    /// the footprint (2 MiB less idle than the zero-filled 1 << 19 ring, measured with `footprint`).
    init() {
        storage = .allocate(capacity: Self.capacity)
    }

    deinit {
        storage.deallocate()
    }

    /// Clears the first-sample time and returns the position a new writer starts reading from.
    func beginCapture() -> Int {
        firstHostTime.store(0, ordering: .relaxed)
        return written.load(ordering: .acquiring)
    }

    func push(_ samples: UnsafePointer<Float>, count: Int, startHostTime: UInt64, endHostTime: UInt64) {
        let start = written.load(ordering: .relaxed)
        let slot = start & (Self.capacity - 1)
        let head = min(count, Self.capacity - slot)
        (storage + slot).update(from: samples, count: head)
        storage.update(from: samples + head, count: count - head)
        _ = firstHostTime.compareExchange(expected: 0, desired: startHostTime, ordering: .relaxed)
        lastEndHostTime.store(endHostTime, ordering: .relaxed)
        written.store(start + count, ordering: .releasing)
        wake.signal()
    }

    func copy(from position: Int, count: Int, into destination: UnsafeMutablePointer<Float>) {
        let slot = position & (Self.capacity - 1)
        let head = min(count, Self.capacity - slot)
        destination.update(from: storage + slot, count: head)
        (destination + head).update(from: storage, count: count - head)
    }
}
