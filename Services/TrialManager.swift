import Foundation
import Combine
import os.log

enum TrialKey {
    static let firstLaunchDate = "nix.trial.firstLaunchDate"
}

@MainActor
final class TrialManager: ObservableObject {

    // ── Duration constants ────────────────────────────────────────────────────
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
