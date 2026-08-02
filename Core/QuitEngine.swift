import AppKit
import os.log

// ---------------------------------------
// MARK: - AppBehavior Enum
// ---------------------------------------

enum AppBehavior: String, Codable, CaseIterable {
    case quit    = "quit"    // Terminate the app cleanly (like Cmd+Q)
    case hide    = "hide"    // Hide the app (like Cmd+H) — it stays running but invisible
    case ignore  = "ignore"  // Do nothing — macOS default behavior
    case prompt  = "prompt"  // Show a dialog asking the user what to do
}

// ------------------------------------------------
// MARK: - QuitEngine
// ------------------------------------------------

@MainActor
final class QuitEngine {

    // --- Configuration -----------------------------------
    var isEnabled: Bool = true
    var isPaused: Bool = false
    var defaultBehavior: AppBehavior = .quit
    var globalGracePeriodSeconds: Int = 0

    // MARK: - Dependencies
    private let ruleStore: RuleStore

    // MARK: - Internal State
    private var pendingQuits: [pid_t: DispatchWorkItem] = [:]
    
    private var pendingNotifications: [pid_t: String] = [:]

    private let logger = Logger(subsystem: "com.sahan.Nix", category: "QuitEngine")

    // MARK: - Init
    init(ruleStore: RuleStore) {
        self.ruleStore = ruleStore
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Main Entry Point
    // ─────────────────────────────────────────────────────────

    func evaluate(app: NSRunningApplication) {

        guard isEnabled && !isPaused else {
            logger.debug("Engine inactive — skipping \(app.localizedName ?? "?")")
            return
        }

        guard !app.isTerminated else {
            logger.debug("\(app.localizedName ?? "?") already terminated — skipping")
            return
        }

        guard !app.isHidden else {
            logger.debug("\(app.localizedName ?? "?") is hidden — skipping")
            return
        }

        let bundleID = app.bundleIdentifier ?? ""
        let behavior = ruleStore.behavior(for: bundleID) ?? defaultBehavior
        let gracePeriod = ruleStore.gracePeriod(for: bundleID) ?? globalGracePeriodSeconds

        logger.info("Evaluating '\(app.localizedName ?? bundleID)': behavior=\(behavior.rawValue), grace=\(gracePeriod)s")

        switch behavior {
        case .quit:
            scheduleQuit(app: app, afterSeconds: gracePeriod)
        case .hide:
            logger.info("Hiding '\(app.localizedName ?? "")'")
            app.hide()
        case .ignore:
            logger.info("Ignoring '\(app.localizedName ?? "")' — behavior is .ignore")
        case .prompt:
            showQuitPrompt(for: app)
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Scheduled Quit
    // ─────────────────────────────────────────────────────────

    private func scheduleQuit(app: NSRunningApplication, afterSeconds: Int) {
        let pid = app.processIdentifier

        pendingQuits[pid]?.cancel()
        pendingQuits.removeValue(forKey: pid)

        if afterSeconds == 0 {
            performQuit(app: app)
            return
        }

        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            guard !app.isTerminated else {
                self.logger.debug("'\(app.localizedName ?? "?")' terminated on its own during grace period")
                return
            }
            guard !app.isHidden else {
                self.logger.debug("'\(app.localizedName ?? "?")' was hidden during grace period — skipping quit")
                self.pendingQuits.removeValue(forKey: pid)
                return
            }

            self.performQuit(app: app)
            self.pendingQuits.removeValue(forKey: pid)
        }

        pendingQuits[pid] = item

        DispatchQueue.main.asyncAfter(
            deadline: .now() + .seconds(afterSeconds),
            execute: item
        )

        logger.info("⏱ Grace period started for '\(app.localizedName ?? "")' — \(afterSeconds)s")
    }

    func cancelPendingQuit(for pid: pid_t) {
        guard let item = pendingQuits[pid] else { return }
        item.cancel()
        pendingQuits.removeValue(forKey: pid)
        logger.info("✅ Cancelled pending quit for PID \(pid) — window re-appeared")
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Perform Quit
    // ─────────────────────────────────────────────────────────

    private func performQuit(app: NSRunningApplication) {
        guard !app.isTerminated else { return }

        let name = app.localizedName ?? "unknown"
        let pid  = app.processIdentifier
        logger.info("🔴 Quitting '\(name)' (PID \(pid))")

        let success = app.terminate()

        if !success {
            logger.warning("terminate() returned false for '\(name)' — app resisted (unsaved data?)")
            return
        }

        pendingNotifications[pid] = name
        logger.debug("Notification queued for '\(name)' — awaiting confirmed termination")
    }

    func confirmedTermination(pid: pid_t) {
        guard let name = pendingNotifications.removeValue(forKey: pid) else { return }

        logger.info("Confirmed termination for '\(name)' (PID \(pid))")

        let notifyEnabled = GlobalSettings.shared.showNotifications
        logger.debug("GlobalSettings.showNotifications = \(notifyEnabled)")

        guard notifyEnabled else {
            logger.debug("Notifications disabled in settings — skipping for '\(name)'")
            return
        }

        NotificationService.show(
            title: "Nix",
            body:  "\(name) quit — no windows remaining"
        )
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Prompt Mode
    // ─────────────────────────────────────────────────────────

    private func showQuitPrompt(for app: NSRunningApplication) {
        let name = app.localizedName ?? "This app"

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let alert = NSAlert()
            alert.messageText = "Quit \(name)?"
            alert.informativeText = "\(name) has no open windows. Quit it to free memory?"
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Keep Running")
            alert.alertStyle = .informational

            let response = alert.runModal()

            if response == .alertFirstButtonReturn {
                self.performQuit(app: app)
            } else {
                self.logger.info("User chose to keep '\(name)' running")
            }
        }
    }
}
