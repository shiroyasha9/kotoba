import os

enum Log {
    static let subsystem = "tech.teensy.kotoba"
    static let pipeline = Logger(subsystem: subsystem, category: "pipeline")
    static let latency = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)
}
