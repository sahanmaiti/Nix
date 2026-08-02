import Foundation
import Combine
import os.log

enum TrialKey {
    static let firstLaunchDate = "nix.trial.firstLaunchDate"
    static let keychainAccount = "nix.trial.firstLaunchDate"
}

@MainActor
final class TrialManager: ObservableObject {

    #if DEBUG
    static let trialDurationDays = 7
    private static let trialUnitSeconds: Double = 60
    #else
    static let trialDurationDays = 7
    private static let trialUnitSeconds: Double = 86_400
    #endif

    @Published private(set) var daysRemaining: Int = TrialManager.trialDurationDays
    @Published private(set) var isExpired: Bool = false

    private let logger = Logger(subsystem: "com.sahan.Nix", category: "TrialManager")

    static let shared = TrialManager()

    private init() {
        migrateLegacyUserDefaultsDateIfNeeded()
        stampFirstLaunchIfNeeded()
        refresh()
        logger.info("TrialManager initialized — \(self.daysRemaining) unit(s) remaining, expired: \(self.isExpired)")
    }

    private func migrateLegacyUserDefaultsDateIfNeeded() {
        guard KeychainHelper.load(account: TrialKey.keychainAccount) == nil else { return }
        guard let legacyDate = UserDefaults.standard.object(forKey: TrialKey.firstLaunchDate) as? Date else { return }
        KeychainHelper.save(String(legacyDate.timeIntervalSince1970), account: TrialKey.keychainAccount)
        UserDefaults.standard.removeObject(forKey: TrialKey.firstLaunchDate)
        logger.info("Migrated trial start date from UserDefaults → Keychain")
    }

    private func firstLaunchDate() -> Date? {
        guard let raw = KeychainHelper.load(account: TrialKey.keychainAccount),
              let interval = Double(raw) else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    private func stampFirstLaunchIfNeeded() {
        guard firstLaunchDate() == nil else { return }
        let now = Date()
        KeychainHelper.save(String(now.timeIntervalSince1970), account: TrialKey.keychainAccount)
        logger.info("Trial started — first launch stamped in Keychain")
    }

    func refresh() {
        guard let firstLaunch = firstLaunchDate() else {
            daysRemaining = Self.trialDurationDays
            isExpired = false
            return
        }

        let elapsed   = Int(Date().timeIntervalSince(firstLaunch) / Self.trialUnitSeconds)
        let remaining = Self.trialDurationDays - elapsed

        daysRemaining = max(0, remaining)
        isExpired     = remaining <= 0
    }

    #if DEBUG
    func debugForceExpire() {
        let expired = Date().addingTimeInterval(-(Double(Self.trialDurationDays + 1) * Self.trialUnitSeconds))
        KeychainHelper.save(String(expired.timeIntervalSince1970), account: TrialKey.keychainAccount)
        refresh()
        logger.warning("DEBUG: trial force-expired")
    }

    func debugResetTrial() {
        KeychainHelper.delete(account: TrialKey.keychainAccount)
        stampFirstLaunchIfNeeded()
        refresh()
        logger.warning("DEBUG: trial reset")
    }
    #endif
}
