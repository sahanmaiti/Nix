import AppKit
import Combine
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
// MARK: - Pending grace
// ------------------------------------------------

struct PendingGrace: Identifiable, Equatable {
    var id: pid_t { pid }
    let pid: pid_t
    let appName: String
    let deadline: Date
}

// ------------------------------------------------
// MARK: - QuitEngine
// ------------------------------------------------

@MainActor
final class QuitEngine: ObservableObject {

    // --- Configuration -----------------------------------
    var isEnabled: Bool = true
    var isPaused: Bool = false
    var defaultBehavior: AppBehavior = .quit
    var globalGracePeriodSeconds: Int = 0

    // MARK: - Dependencies
    private let ruleStore: RuleStore

    // MARK: - Internal State
    /// In-flight grace periods, soonest deadline first. The popover reads this;
    /// `pendingQuits` stays private and is updated in the same methods.
    @Published private(set) var pendingGracePeriods: [PendingGrace] = []

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
            logger.debug("Engine inactive — skipping \(app.localizedName ?? "?", privacy: .public)")
            return
        }

        guard !app.isTerminated else {
            logger.debug("\(app.localizedName ?? "?", privacy: .public) already terminated — skipping")
            return
        }

        guard !app.isHidden else {
            logger.debug("\(app.localizedName ?? "?", privacy: .public) is hidden — skipping")
            return
        }

        let bundleID = app.bundleIdentifier ?? ""
        let behavior = ruleStore.behavior(for: bundleID) ?? defaultBehavior
        let gracePeriod = ruleStore.gracePeriod(for: bundleID) ?? globalGracePeriodSeconds

        logger.info("Evaluating '\(app.localizedName ?? bundleID, privacy: .public)': behavior=\(behavior.rawValue), grace=\(gracePeriod)s")

        switch behavior {
        case .quit:
            scheduleQuit(app: app, afterSeconds: gracePeriod)
        case .hide:
            logger.info("Hiding '\(app.localizedName ?? "", privacy: .public)'")
            app.hide()
        case .ignore:
            logger.info("Ignoring '\(app.localizedName ?? "", privacy: .public)' — behavior is .ignore")
        case .prompt:
            showQuitPrompt(for: app)
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Scheduled Quit
    // ─────────────────────────────────────────────────────────

    private func scheduleQuit(app: NSRunningApplication, afterSeconds: Int) {
        let pid = app.processIdentifier
        let appName = app.localizedName ?? "Unknown App"

        removePendingQuit(for: pid)

        if afterSeconds == 0 {
            performQuit(app: app)
            return
        }

        let deadline = Date().addingTimeInterval(TimeInterval(afterSeconds))
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            guard !app.isTerminated else {
                self.logger.debug("'\(appName, privacy: .public)' terminated on its own during grace period")
                self.removePendingQuit(for: pid, cancelWorkItem: false)
                return
            }
            guard !app.isHidden else {
                self.logger.debug("'\(appName, privacy: .public)' was hidden during grace period — skipping quit")
                self.removePendingQuit(for: pid, cancelWorkItem: false)
                return
            }

            self.performQuit(app: app)
            self.removePendingQuit(for: pid, cancelWorkItem: false)
        }

        pendingQuits[pid] = item
        pendingGracePeriods.append(PendingGrace(pid: pid, appName: appName, deadline: deadline))
        pendingGracePeriods.sort { $0.deadline < $1.deadline }

        DispatchQueue.main.asyncAfter(
            deadline: .now() + .seconds(afterSeconds),
            execute: item
        )

        logger.info("⏱ Grace period started for '\(appName, privacy: .public)' — \(afterSeconds)s")
    }

    func cancelPendingQuit(for pid: pid_t) {
        guard pendingQuits[pid] != nil else { return }
        removePendingQuit(for: pid)
        logger.info("✅ Cancelled pending quit for PID \(pid) — window re-appeared")
    }

    /// Drops an in-flight grace period. No-op when Nix never scheduled this PID,
    /// so a termination Nix did not initiate still reaches `confirmedTermination`.
    func clearPendingGrace(for pid: pid_t) {
        guard pendingQuits[pid] != nil else { return }
        removePendingQuit(for: pid)
        logger.debug("Cleared pending grace for PID \(pid)")
    }

    private func removePendingQuit(for pid: pid_t, cancelWorkItem: Bool = true) {
        if cancelWorkItem {
            pendingQuits[pid]?.cancel()
        }
        pendingQuits.removeValue(forKey: pid)
        pendingGracePeriods.removeAll { $0.pid == pid }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Perform Quit
    // ─────────────────────────────────────────────────────────

    private func performQuit(app: NSRunningApplication) {
        guard !app.isTerminated else { return }

        let name = app.localizedName ?? "unknown"
        let pid  = app.processIdentifier
        logger.info("🔴 Quitting '\(name, privacy: .public)' (PID \(pid))")

        let success = app.terminate()

        if !success {
            logger.warning("terminate() returned false for '\(name, privacy: .public)' — app resisted (unsaved data?)")
            return
        }

        pendingNotifications[pid] = name
        logger.debug("Notification queued for '\(name, privacy: .public)' — awaiting confirmed termination")
    }

    func confirmedTermination(pid: pid_t) {
        guard let name = pendingNotifications.removeValue(forKey: pid) else { return }

        logger.info("Confirmed termination for '\(name, privacy: .public)' (PID \(pid))")

        let notifyEnabled = GlobalSettings.shared.showNotifications
        logger.debug("GlobalSettings.showNotifications = \(notifyEnabled)")

        guard notifyEnabled else {
            logger.debug("Notifications disabled in settings — skipping for '\(name, privacy: .public)'")
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
                self.logger.info("User chose to keep '\(name, privacy: .public)' running")
            }
        }
    }
}
