import Foundation
import Combine
import os.log

enum TrialKey {
    static let firstLaunchDate = "nix.trial.firstLaunchDate"
}

@MainActor
final class TrialManager: ObservableObject {

    static let trialDurationDays = 7

    @Published private(set) var daysRemaining: Int = TrialManager.trialDurationDays
    @Published private(set) var isExpired: Bool = false

    private let logger = Logger(subsystem: "com.sahan.Nix", category: "TrialManager")

    static let shared = TrialManager()

    private init() {
        stampFirstLaunchIfNeeded()
        refresh()
        logger.info("TrialManager initialized — \(self.daysRemaining)d remaining, expired: \(self.isExpired)")
    }

    private func stampFirstLaunchIfNeeded() {
        guard UserDefaults.standard.object(forKey: TrialKey.firstLaunchDate) == nil else { return }
        UserDefaults.standard.set(Date(), forKey: TrialKey.firstLaunchDate)
        logger.info("Trial started — first launch stamped")
    }

    /// Call on launch and on app activation — cheap, no I/O beyond UserDefaults.
    func refresh() {
        guard let firstLaunch = UserDefaults.standard.object(forKey: TrialKey.firstLaunchDate) as? Date else {
            // Should be unreachable post-init, but fail OPEN — never lock a user
            // out of a feature because a stamp went missing.
            daysRemaining = Self.trialDurationDays
            isExpired = false
            return
        }

        let elapsedDays = Int(Date().timeIntervalSince(firstLaunch) / 86400)
        let remaining = Self.trialDurationDays - elapsedDays

        daysRemaining = max(0, remaining)
        isExpired = remaining <= 0
    }

    #if DEBUG
    /// QA helper — force the paywall to appear without waiting 7 days.
    func debugForceExpire() {
        let expired = Date().addingTimeInterval(-Double(Self.trialDurationDays + 1) * 86400)
        UserDefaults.standard.set(expired, forKey: TrialKey.firstLaunchDate)
        refresh()
        logger.warning("DEBUG: trial force-expired")
    }

    func debugResetTrial() {
        UserDefaults.standard.removeObject(forKey: TrialKey.firstLaunchDate)
        stampFirstLaunchIfNeeded()
        refresh()
        logger.warning("DEBUG: trial reset")
    }
    #endif
}
