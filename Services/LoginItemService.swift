import ServiceManagement
import os.log

enum LoginItemService {

    private static let logger = Logger(subsystem: "com.sahan.Nix", category: "LoginItemService")

    // ─────────────────────────────────────────────────────────────
    // MARK: - Current System State
    // ─────────────────────────────────────────────────────────────
    
    static var isEnabled: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - Set State
    // ─────────────────────────────────────────────────────────────

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                logger.info("Login item registered — Nix will launch at login")
            } else {
                try SMAppService.mainApp.unregister()
                logger.info("Login item unregistered — Nix will not launch at login")
            }
            return true
        } catch {
            logger.error("Login item \(enabled ? "registration" : "unregistration") failed: \(error.localizedDescription)")
            return false
        }
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - Startup Reconciliation
    // ─────────────────────────────────────────────────────────────

    @MainActor
    static func syncWithSystemState() {
        let actual = isEnabled
        guard GlobalSettings.shared.launchAtLogin != actual else {
            logger.debug("Launch-at-login already in sync (\(actual)) — no correction needed")
            return
        }
        GlobalSettings.shared.launchAtLogin = actual
        logger.info("Startup sync: launchAtLogin corrected → \(actual) (system state was authoritative)")
    }
}
