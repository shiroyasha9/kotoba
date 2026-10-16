import Foundation

/// Which install runs: the release (`tech.teensy.kotoba`) or a development build (`tech.teensy.kotoba.dev`, the
/// Debug configuration in project.yml). Every name that two installs must not share derives from the bundle id here,
/// so a development build, a `make check` or a `--snapshots` run never reads or writes the release's data: the data
/// folder (`AppFiles`), the Keychain service (`KeychainStore`), and the log subsystem (`KotobaCore.Log.subsystem`, the
/// same bundle id). UserDefaults, TCC grants and the login item (`SMAppService.mainApp`) follow the bundle id by
/// themselves. Lint flags these names anywhere else (`per_install_ids` and `per_install_locations` in .swiftlint.yml).
enum Install {
    static let releaseBundleID = "tech.teensy.kotoba"
    /// The release's `APP_DISPLAY_NAME` in project.yml.
    static let releaseDisplayName = "kotoba"

    static let bundleID: String = {
        guard let id = Bundle.main.bundleIdentifier else { preconditionFailure("kotoba runs without its app bundle") }
        return id
    }()

    static var isRelease: Bool { bundleID == releaseBundleID }

    /// "kotoba", or "kotoba Dev" for a development build (`APP_DISPLAY_NAME` in project.yml).
    static let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? bundleID

    /// In Application Support: `kotoba` for the release (where 0.1.0 keeps its data), `kotoba-dev` for a development
    /// build. Any other bundle id gets its own folder too, never the release's.
    static let dataFolderName: String = {
        let prefix = releaseBundleID + "."
        if isRelease { return "kotoba" }
        guard bundleID.hasPrefix(prefix) else { return bundleID }
        return "kotoba-" + bundleID.dropFirst(prefix.count).replacing(".", with: "-")
    }()

    /// The API keys' generic-password service: `tech.teensy.kotoba` for the release, as 0.1.0 saved them.
    static var keychainService: String { bundleID }
}
