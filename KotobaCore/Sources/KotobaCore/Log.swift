import Foundation
import os

public enum Log {
    /// The app's bundle id, so the release (`tech.teensy.kotoba`) and a development build (`tech.teensy.kotoba.dev`)
    /// log apart (App/Install.swift). Package tests log under their runner's id.
    public static let subsystem = Bundle.main.bundleIdentifier ?? "kotoba"
    static let pipeline = Logger(subsystem: subsystem, category: "pipeline")
    /// The mic input's lifecycle (`AudioCapture`), in the same category as the app's capture adapters.
    static let audio = Logger(subsystem: subsystem, category: "audio")
    /// One line per dictation with the latency offsets; the providers add one line per upload.
    public static let latency = Logger(subsystem: subsystem, category: "latency")
    /// Points of interest: the latency marks, and the providers' `bodyReady`.
    public static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)
}
