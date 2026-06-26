import Foundation
import Combine
import os.log

final class RuleStore: ObservableObject {
    
    // MARK: - Published State
    @Published private(set) var rules: [String: AppRule] = [:]
    
    
    // MARK: - Contacts
    private let storageKey = "nix.appRules"
    static let permanentWhitelist: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.SystemUIServer",
        "com.apple.NotificationCenter"
    ]
    
    private let logger = Logger(subsystem: "com.sahan.Nix", category: "RuleStore")
    
    // MARK: - LifeCycle
    init() {
    loadRules()
    logger.info("RuleStore initialized -\(self.rules.count) rule(s) loaded")
    }
    
    // MARK: - Public Query API
    func rule(for bundleID: String) -> AppRule? {
        rules[bundleID]
    }
    func behavior(for bundleID: String) -> AppBehavior? {
        // Layer 1: Permanent whitelist - non-negotiable
        if Self.permanentWhitelist.contains(bundleID) {
            return .ignore
        }
        guard let rule = rules[bundleID] else {
            return nil
        }
        // Layer 2: User-managed whitelist
        if rule.isWhitelisted {
            return .ignore
        }
        // Layer 3: Explicit per-app behavior
        return rule.behavior
    }
    func gracePeriod(for bundleID: String) -> Int? {
        guard let rule = rules[bundleID] else { return nil }
        // -1 is the sentinel value for "use global default"
        return rule.gracePeriodSeconds >= 0 ? rule.gracePeriodSeconds : nil
    }
    func isWhitelisted(_ bundleID: String) -> Bool {
        Self.permanentWhitelist.contains(bundleID) ||
        rules[bundleID]?.isWhitelisted == true
    }

    // MARK: - Public Mutation API
    
    /// Saves or updates a rule for an app.
    func setRule(_ rule: AppRule) {
        var updated = rule
        updated.lastModified = Date()      // always stamp the modification time
        rules[rule.bundleIdentifier] = updated
        saveRules()
        logger.info("Rule set for \(rule.bundleIdentifier): \(rule.behavior.rawValue)")
    }

    /// Convenience: set only the behavior for an app (creates rule if none exists).
    func setBehavior(_ behavior: AppBehavior, for bundleID: String, appName: String) {
        // Load existing rule or create a fresh one
        var rule = rules[bundleID] ?? AppRule(bundleIdentifier: bundleID, appName: appName)
        rule.behavior = behavior
        setRule(rule)
    }

    /// Convenience: set only the grace period for an app.
    func setGracePeriod(_ seconds: Int, for bundleID: String, appName: String) {
        var rule = rules[bundleID] ?? AppRule(bundleIdentifier: bundleID, appName: appName)
        rule.gracePeriodSeconds = seconds
        setRule(rule)
    }

    /// Convenience: toggle whitelist status for an app.
    func setWhitelisted(_ whitelisted: Bool, for bundleID: String, appName: String) {
        var rule = rules[bundleID] ?? AppRule(bundleIdentifier: bundleID, appName: appName)
        rule.isWhitelisted = whitelisted
        setRule(rule)
    }

    /// Remove a rule entirely — app returns to global default behavior.
    func removeRule(for bundleID: String) {
        rules.removeValue(forKey: bundleID)
        saveRules()
        logger.info("Rule removed for \(bundleID)")
    }

    /// Wipe all user-configured rules. Useful for a "Reset to Defaults" button.
    func resetAllRules() {
        rules = [:]
        UserDefaults.standard.removeObject(forKey: storageKey)
        logger.info("All rules reset")
    }

    // MARK: - Persistence (Private)

    private func saveRules() {
        do {
            // Step 1: Convert dictionary values to an array for encoding.
            let array = Array(rules.values)

            // Step 2: Encode the array to JSON Data
            let data = try JSONEncoder().encode(array)

            // Step 3: Write to UserDefaults
            UserDefaults.standard.set(data, forKey: storageKey)

            logger.debug("Rules saved: \(array.count) rule(s)")
        } catch {
            logger.error("Failed to save rules: \(error.localizedDescription)")
        }
    }

    private func loadRules() {
        // Step 1: Try to read the raw Data from UserDefaults
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            rules = [:]
            logger.info("No saved rules found — fresh install")
            return
        }

        do {
            // Step 2: Decode the JSON Data back into an array of AppRule
            let array = try JSONDecoder().decode([AppRule].self, from: data)

            // Step 3: Rebuild the dictionary from the array.
            rules = Dictionary(array.map { ($0.bundleIdentifier, $0) }, uniquingKeysWith: { _, latest in latest })
            logger.info("Loaded \(array.count) rule(s) from UserDefaults")
        } catch {
            logger.error("Failed to decode rules: \(error.localizedDescription) — resetting to empty")
            rules = [:]
        }
    }
}
