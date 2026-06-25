import Foundation
import Combine
import os.log

enum TrialKey {
    static let firstLaunchDate = "nix.trial.firstLaunchDate"
}

@MainActor
final class TrialManager: ObservableObject {

    // ── Duration constants ────────────────────────────────────────────────────
    // DEBUG: 1 unit = 1 minute  →  trial expires after 1 minute
    // RELEASE: 1 unit = 1 day   →  trial expires after 7 days
    // Switching back to production requires zero code changes — just build Release.
    #if DEBUG
    static let trialDurationDays = 7
    private static let trialUnitSeconds: Double = 86_400
    #else
    static let trialDurationDays = 7            // 7 units in release
    private static let trialUnitSeconds: Double = 86_400  // 1 day per unit
    #endif

    @Published private(set) var daysRemaining: Int = TrialManager.trialDurationDays
    @Published private(set) var isExpired: Bool = false

    private let logger = Logger(subsystem: "com.sahan.Nix", category: "TrialManager")

    static let shared = TrialManager()

    private init() {
        stampFirstLaunchIfNeeded()
        refresh()
        logger.info("TrialManager initialized — \(self.daysRemaining) unit(s) remaining, expired: \(self.isExpired)")
    }

    private func stampFirstLaunchIfNeeded() {
        guard UserDefaults.standard.object(forKey: TrialKey.firstLaunchDate) == nil else { return }
        UserDefaults.standard.set(Date(), forKey: TrialKey.firstLaunchDate)
        logger.info("Trial started — first launch stamped")
    }

    func refresh() {
        guard let firstLaunch = UserDefaults.standard.object(forKey: TrialKey.firstLaunchDate) as? Date else {
            daysRemaining = Self.trialDurationDays
            isExpired = false
            return
        }

        // Uses Self.trialUnitSeconds: 60s in Debug, 86400s in Release
        let elapsed  = Int(Date().timeIntervalSince(firstLaunch) / Self.trialUnitSeconds)
        let remaining = Self.trialDurationDays - elapsed

        daysRemaining = max(0, remaining)
        isExpired     = remaining <= 0
    }

    #if DEBUG
    func debugForceExpire() {
        let expired = Date().addingTimeInterval(-(Double(Self.trialDurationDays + 1) * Self.trialUnitSeconds))
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
