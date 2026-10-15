import KotobaCore
import os

/// The app's loggers, one per category, under the core's subsystem.
enum Log {
    static let app = Logger(subsystem: KotobaCore.Log.subsystem, category: "app")
    static let audio = Logger(subsystem: KotobaCore.Log.subsystem, category: "audio")
    static let dictionary = Logger(subsystem: KotobaCore.Log.subsystem, category: "dictionary")
}
