import os

public enum Log {
    public static let subsystem = "tech.teensy.kotoba"
    static let pipeline = Logger(subsystem: subsystem, category: "pipeline")
    /// One line per dictation with the latency offsets; the providers add one line per upload.
    public static let latency = Logger(subsystem: subsystem, category: "latency")
    /// Points of interest: the latency marks, and the providers' `bodyReady`.
    public static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)
}
