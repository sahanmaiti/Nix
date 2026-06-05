import SwiftUI
import Combine

// MARK: - Settings Keys

enum SettingsKey {
    static let isEnabled           = "nix.isEnabled"
    static let defaultBehavior     = "nix.defaultBehavior"     // stored as String raw value
    static let gracePeriodSeconds  = "nix.gracePeriodSeconds"
    static let launchAtLogin       = "nix.launchAtLogin"
    static let showNotifications   = "nix.showNotifications"
}

// MARK: - GlobalSettings

@MainActor
final class GlobalSettings: ObservableObject {

    @AppStorage(SettingsKey.isEnabled)
    var isEnabled: Bool = true

    @AppStorage(SettingsKey.defaultBehavior)
    var defaultBehaviorRaw: String = AppBehavior.quit.rawValue

    @AppStorage(SettingsKey.gracePeriodSeconds)
    var gracePeriodSeconds: Int = 0

    @AppStorage(SettingsKey.launchAtLogin)
    var launchAtLogin: Bool = false

    @AppStorage(SettingsKey.showNotifications)
    var showNotifications: Bool = true

    // MARK: - Computed Properties

    var defaultBehavior: AppBehavior {
        get { AppBehavior(rawValue: defaultBehaviorRaw) ?? .quit }
        set { defaultBehaviorRaw = newValue.rawValue }
    }

    // MARK: - Singleton

    static let shared = GlobalSettings()
    private init() { }
}
