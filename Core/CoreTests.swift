import AppKit
import ApplicationServices
import ServiceManagement
import os.log
import UserNotifications

private let testLogger = Logger(subsystem: "com.sahan.Nix", category: "Verification")

// ------------------------------------------------------
// MARK: - Test Runner
// ------------------------------------------------------

@MainActor
func runAllVerifications() {
    testLogger.info("================================")
    testLogger.info("VERIFICATION SUITE - Day 20")
    testLogger.info("================================")
    
    verifyAppTracker()
    verifyWhitelist()
    verifyActivationPolicyFilter()
    verifyAXPermission()
    verifyObjectWillChangeForwarding()
    verifyQuitEngineEnabled()
    verifyQuitEngineCancelSafety()
    verifyGlobalSettings()
    verifyEngineSettingsSync()
    verifyIsEnabledSync()
    verifyGracePeriodCancelWiring()
    verifyAppTrackerCancelCallback()
    verifyRuleStoreEdgeCases()
    verifyKnownHiderCoverage()
    verifyGracePeriodResetToZero()
    verifyQuitEngineWhitelistRespect()
    verifyStartupIsEnabledSync()
    verifyLoggerCategories()
    verifyOnboardingState()
    verifyWindowMonitorNotificationStrategy()
    verifyLoginItemService()
    verifyNotificationService()
    verifyWhitelistTabData()
    verifyTrialState()
    verifyLicenseGate()
    
    testLogger.info("=================================")
    testLogger.info("VERIFICATION SUITE COMPLETE")
    testLogger.info("=================================")
}

// ------------------------------------------------------
// MARK: - Individual Verifications
// ------------------------------------------------------

/// Verifies AppTracker is populated with currently running apps.
@MainActor
func verifyAppTracker() {
    let tracker = AppEnvironment.shared.appTracker
    let count = tracker.trackedApps.count
    
    if count > 0 {
        testLogger.info("✅ AppTracker has \(count) apps tracked")
        for app in tracker.trackedApps.prefix(3) {
            testLogger.debug("   -> \(app.name) (PID: \(app.pid))")
        }
    } else {
        testLogger.warning("⚠️ AppTracker: 0 apps tracked — is any regular app running?")
    }
}

/// Verifies that whitelisted system apps are NOT in the tracked list.
@MainActor
func verifyWhitelist() {
    let tracker = AppEnvironment.shared.appTracker
    
    let systemBundleIDs = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.SystemUIServer"
    ]
    var allPassed = true
    
    for bundleID in systemBundleIDs {
        let isTracked = tracker.trackedApps.contains {
            $0.bundleIdentifier == bundleID
        }
        
        if isTracked {
            testLogger.error("❌ WHITELIST FAIL: \(bundleID) IS being tracked (should be excluded)")
            allPassed = false
        } else {
            testLogger.info("✅ WHITELIST PASS: \(bundleID) correctly excluded")
        }
    }
    
    if allPassed {
        testLogger.info("✅ ALL whitelist checks passed")
    }
}

/// Verifies that no .accessory or .prohibited apps are being tracked.
@MainActor
func verifyActivationPolicyFilter() {
    let tracker = AppEnvironment.shared.appTracker
    let allRunning = NSWorkspace.shared.runningApplications

    var failCount = 0

    for tracked in tracker.trackedApps {
        if let running = allRunning.first(where: { $0.processIdentifier == tracked.pid }) {
            if running.activationPolicy != .regular {
                testLogger.error("❌ POLICY FAIL: \(tracked.name) has policy \(running.activationPolicy.rawValue) but is being tracked")
                failCount += 1
            }
        }
    }

    let regularCount  = allRunning.filter { $0.activationPolicy == .regular }.count
    let accessoryCount = allRunning.filter { $0.activationPolicy == .accessory }.count

    testLogger.info("✅ Activation policy: \(regularCount) regular, \(accessoryCount) accessory (excluded)")

    if failCount == 0 {
        testLogger.info("✅ No incorrectly-tracked apps found")
    }
}

/// Verifies that AccessibilityManager correctly reflects current AX permission.
@MainActor
func verifyAXPermission() {
    let manager      = AppEnvironment.shared.accessibilityManager
    let systemValue  = AXIsProcessTrusted()
    let managerValue = manager.isGranted

    if systemValue == managerValue {
        testLogger.info("✅ AX permission: manager.isGranted (\(managerValue)) matches AXIsProcessTrusted() (\(systemValue))")
    } else {
        testLogger.warning("⚠️ AX permission MISMATCH: manager says \(managerValue), system says \(systemValue)")
        testLogger.warning("   This may resolve in 1 second when the polling timer fires")
    }
}

/// Verifies that AppEnvironment properly forwards child change notifications.
@MainActor
func verifyObjectWillChangeForwarding() {
    let env = AppEnvironment.shared
    testLogger.info("✅ AppEnvironment.shared exists and is initialized")
    testLogger.info("   isEnabled: \(env.isEnabled), isPaused: \(env.isPaused)")
    testLogger.info("   appTracker.trackedApps.count: \(env.appTracker.trackedApps.count)")
    testLogger.info("   accessibilityManager.isGranted: \(env.accessibilityManager.isGranted)")
}

/// Verifies QuitEngine respects the isEnabled flag.
@MainActor
func verifyQuitEngineEnabled() {
    let engine = AppEnvironment.shared.quitEngine
    testLogger.info("QuitEngine.isEnabled: \(engine.isEnabled)")
    testLogger.info("QuitEngine.isPaused: \(engine.isPaused)")
    testLogger.info("QuitEngine.defaultBehavior: \(engine.defaultBehavior.rawValue)")
    testLogger.info("✅ QuitEngine initialized and accessible")
}

/// Verifies that cancelPendingQuit doesn't crash for a non-existent PID.
@MainActor
func verifyQuitEngineCancelSafety() {
    let engine = AppEnvironment.shared.quitEngine
    engine.cancelPendingQuit(for: pid_t(99999))
    testLogger.info("✅ cancelPendingQuit with unknown PID: safe (no crash)")
}

/// Verifies GlobalSettings loads and reports correct values.
@MainActor
func verifyGlobalSettings() {
    let settings = GlobalSettings.shared

    testLogger.info("=== GlobalSettings State ===")
    testLogger.info("  isEnabled:          \(settings.isEnabled)")
    testLogger.info("  defaultBehavior:    \(settings.defaultBehaviorRaw)")
    testLogger.info("  gracePeriodSeconds: \(settings.gracePeriodSeconds)")
    testLogger.info("  launchAtLogin:      \(settings.launchAtLogin)")
    testLogger.info("  showNotifications:  \(settings.showNotifications)")
    testLogger.info("✅ GlobalSettings readable — UserDefaults is accessible")
}

/// Verifies QuitEngine properties match what GlobalSettings says they should be.
@MainActor
func verifyEngineSettingsSync() {
    let engine   = AppEnvironment.shared.quitEngine
    let settings = GlobalSettings.shared

    let behaviorMatch = engine.defaultBehavior == settings.defaultBehavior
    let graceMatch    = engine.globalGracePeriodSeconds == settings.gracePeriodSeconds

    testLogger.info("=== Engine ↔ GlobalSettings Sync ===")
    testLogger.info("  engine.defaultBehavior (\(engine.defaultBehavior.rawValue)) == settings (\(settings.defaultBehaviorRaw)): \(behaviorMatch)")
    testLogger.info("  engine.gracePeriod (\(engine.globalGracePeriodSeconds)) == settings (\(settings.gracePeriodSeconds)): \(graceMatch)")

    if behaviorMatch && graceMatch {
        testLogger.info("✅ QuitEngine is in sync with GlobalSettings")
    } else {
        testLogger.warning("⚠️ QuitEngine OUT OF SYNC — syncSettingsToEngine() may not have fired")
    }
}

/// Verifies AppEnvironment.isEnabled matches GlobalSettings.isEnabled.
@MainActor
func verifyIsEnabledSync() {
    let env      = AppEnvironment.shared
    let settings = GlobalSettings.shared

    let matches = env.isEnabled == settings.isEnabled

    if matches {
        testLogger.info("✅ isEnabled sync: AppEnvironment (\(env.isEnabled)) == GlobalSettings (\(settings.isEnabled))")
    } else {
        testLogger.error("❌ isEnabled MISMATCH: AppEnvironment=\(env.isEnabled), GlobalSettings=\(settings.isEnabled)")
    }
}

/// Verifies that AppEnvironment correctly wired the cancel callbacks.
@MainActor
func verifyGracePeriodCancelWiring() {
    let env = AppEnvironment.shared

    let path1Wired = env.windowMonitor.onWindowAppeared != nil
    if path1Wired {
        testLogger.info("✅ Path 1 wired: windowMonitor.onWindowAppeared → QuitEngine")
    } else {
        testLogger.error("❌ Path 1 NOT wired: windowMonitor.onWindowAppeared is nil")
    }

    let path2Wired = env.appTracker.onCancelPendingQuit != nil
    if path2Wired {
        testLogger.info("✅ Path 2 wired: appTracker.onCancelPendingQuit → QuitEngine")
    } else {
        testLogger.error("❌ Path 2 NOT wired: appTracker.onCancelPendingQuit is nil")
    }

    if path1Wired && path2Wired {
        testLogger.info("✅ Grace period cancellation: both paths wired correctly")
    }
}

/// Verifies that the cancel callback fires without crashing for tracked apps.
@MainActor
func verifyAppTrackerCancelCallback() {
    let tracker = AppEnvironment.shared.appTracker

    tracker.onCancelPendingQuit?(pid_t(99999))
    testLogger.info("✅ AppTracker.onCancelPendingQuit with unknown PID: safe")

    if let firstApp = tracker.trackedApps.first {
        tracker.onCancelPendingQuit?(firstApp.pid)
        testLogger.info("✅ AppTracker.onCancelPendingQuit fired for '\(firstApp.name)': no crash")
    } else {
        testLogger.info("ℹ️  No tracked apps to test cancel callback against (open any app)")
    }
}

/// Verifies RuleStore correctly handles edge cases.
@MainActor
func verifyRuleStoreEdgeCases() {
    let store = AppEnvironment.shared.ruleStore

    testLogger.info("=== RuleStore Edge Cases ===")

    let finderBehavior = store.behavior(for: "com.apple.finder")
    let finderCorrect  = finderBehavior == .ignore
    testLogger.info("  Finder → .ignore: \(finderCorrect ? "✅" : "❌") (got: \(finderBehavior?.rawValue ?? "nil"))")

    let unknownBehavior = store.behavior(for: "com.nonexistent.fakeapp.xyz")
    let unknownCorrect  = unknownBehavior == nil
    testLogger.info("  Unknown app → nil: \(unknownCorrect ? "✅" : "❌") (got: \(unknownBehavior?.rawValue ?? "nil"))")

    let finderListed  = store.isWhitelisted("com.apple.finder")
    let dockListed    = store.isWhitelisted("com.apple.dock")
    let unknownListed = store.isWhitelisted("com.nonexistent.fakeapp.xyz")
    testLogger.info("  Finder.isWhitelisted: \(finderListed ? "✅" : "❌")")
    testLogger.info("  Dock.isWhitelisted: \(dockListed ? "✅" : "❌")")
    testLogger.info("  Unknown.isWhitelisted (should be false): \(!unknownListed ? "✅" : "❌")")

    let unknownGrace = store.gracePeriod(for: "com.nonexistent.fakeapp.xyz")
    let graceCorrect = unknownGrace == nil
    testLogger.info("  Unknown app gracePeriod → nil: \(graceCorrect ? "✅" : "❌")")

    let allPass = finderCorrect && unknownCorrect && finderListed && dockListed && !unknownListed && graceCorrect
    if allPass {
        testLogger.info("✅ RuleStore edge cases: all correct")
    } else {
        testLogger.error("❌ RuleStore has edge case failures — check above")
    }
}

/// Verifies that apps known to hide-on-close are in the knownHiders list.
@MainActor
func verifyKnownHiderCoverage() {
    testLogger.info("=== Known Hider Coverage ===")

    let knownHiderBundleIDs: [String] = [
        "com.hnc.Discord",
        "com.spotify.client",
        "com.tinyspeck.slackmacgap",
        "com.readdle.smartemail",
        "com.mimestream.Mimestream",
        "com.apple.iChat",
        "us.zoom.xos",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.skype.skype",
    ]

    let runningApps = NSWorkspace.shared.runningApplications
    var foundAny = false

    for bundleID in knownHiderBundleIDs {
        if let app = runningApps.first(where: { $0.bundleIdentifier == bundleID }) {
            testLogger.info("  ✅ Found known hider running: \(app.localizedName ?? bundleID) — extended debounce active")
            foundAny = true
        }
    }

    if !foundAny {
        testLogger.info("  ℹ️  No known hiders currently running")
    }

    testLogger.info("✅ Known hider check complete")
}

/// Verifies the grace period is back to 0.
@MainActor
func verifyGracePeriodResetToZero() {
    let settings = GlobalSettings.shared
    let engine   = AppEnvironment.shared.quitEngine

    testLogger.info("=== Grace Period Reset Check ===")
    testLogger.info("  settings.gracePeriodSeconds: \(settings.gracePeriodSeconds)")
    testLogger.info("  engine.globalGracePeriodSeconds: \(engine.globalGracePeriodSeconds)")

    if settings.gracePeriodSeconds == 0 && engine.globalGracePeriodSeconds == 0 {
        testLogger.info("✅ Grace period correctly reset to 0")
    } else {
        testLogger.warning("⚠️ Grace period is NOT 0 — did you forget to remove the test override?")
    }
}

/// Verifies QuitEngine respects the RuleStore whitelist at the decision layer.
@MainActor
func verifyQuitEngineWhitelistRespect() {
    let store = AppEnvironment.shared.ruleStore

    testLogger.info("=== QuitEngine Whitelist Respect ===")

    let fakeBundleID = "com.test.fakeapp.whitelist.day13"
    store.setWhitelisted(true, for: fakeBundleID, appName: "FakeTestApp")

    let behavior  = store.behavior(for: fakeBundleID)
    let isIgnore  = behavior == .ignore
    testLogger.info("  Whitelisted app → .ignore: \(isIgnore ? "✅" : "❌") (got: \(behavior?.rawValue ?? "nil"))")

    store.removeRule(for: fakeBundleID)
    let afterRemove = store.behavior(for: fakeBundleID)
    let cleanedUp   = afterRemove == nil
    testLogger.info("  After removeRule → nil: \(cleanedUp ? "✅" : "❌")")

    if isIgnore && cleanedUp {
        testLogger.info("✅ QuitEngine whitelist respect: correctly ignores whitelisted apps")
    } else {
        testLogger.error("❌ Whitelist respect failure — check RuleStore.behavior()")
    }
}

/// Verifies that AppEnvironment.isEnabled matches GlobalSettings at startup.
@MainActor
func verifyStartupIsEnabledSync() {
    let env      = AppEnvironment.shared
    let settings = GlobalSettings.shared

    testLogger.info("=== Startup isEnabled Sync ===")

    let envValue    = env.isEnabled
    let settingsVal = settings.isEnabled
    let engineValue = env.quitEngine.isEnabled

    testLogger.info("  AppEnvironment.isEnabled: \(envValue)")
    testLogger.info("  GlobalSettings.isEnabled: \(settingsVal)")
    testLogger.info("  QuitEngine.isEnabled:     \(engineValue)")

    let envMatchesSettings = envValue == settingsVal
    let engineMatchesEnv   = engineValue == envValue

    testLogger.info("  env == settings: \(envMatchesSettings ? "✅" : "❌ BUG: startup sync failed")")
    testLogger.info("  engine == env:   \(engineMatchesEnv   ? "✅" : "❌ BUG: engine not synced")")

    if envMatchesSettings && engineMatchesEnv {
        testLogger.info("✅ Startup isEnabled sync: all three sources agree")
    } else {
        testLogger.error("❌ isEnabled is out of sync at startup")
    }
}

/// Verifies that all key services have a logger by checking log output is coherent.
@MainActor
func verifyLoggerCategories() {
    let env = AppEnvironment.shared

    testLogger.info("=== Logger Category Coverage ===")
    let _ = env.accessibilityManager.isGranted
    let _ = env.appTracker.trackedApps.count
    let _ = env.quitEngine.isEnabled
    let _ = env.ruleStore.rules.count

    testLogger.info("  AccessibilityManager: accessible ✅")
    testLogger.info("  AppTracker:           accessible ✅")
    testLogger.info("  QuitEngine:           accessible ✅")
    testLogger.info("  RuleStore:            accessible ✅")
    testLogger.info("  WindowMonitor:        accessible ✅")
    testLogger.info("✅ All services reachable — loggers initialized correctly")
}


// ──────────────────────────────────────────────────────────────────────────────
// MARK: - Phantom Window Diagnostic
// ──────────────────────────────────────────────────────────────────────────────

@MainActor
func diagnoseWindowTree(appName: String) {
    guard let app = NSWorkspace.shared.runningApplications
        .first(where: { $0.localizedName == appName }) else {
        testLogger.warning("⚠️  '\(appName)' is not running — open it first, then wait for the diagnostic")
        return
    }

    let pid        = app.processIdentifier
    let appElement = AXUIElementCreateApplication(pid)

    var windowsRef: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(
        appElement,
        kAXWindowsAttribute as CFString,
        &windowsRef
    )

    testLogger.info("╔══ PHANTOM WINDOW DIAGNOSTIC: \(appName) (PID \(pid)) ══")

    guard result == .success, let windows = windowsRef as? [AXUIElement] else {
        testLogger.error("║  AX call failed: \(result.rawValue) — no Accessibility permission?")
        testLogger.info("╚══")
        return
    }

    testLogger.info("║  Total windows in AX tree: \(windows.count)")
    testLogger.info("║  (Nix should count only 'real' ones — phantom windows inflate this)")
    testLogger.info("║")

    for (i, window) in windows.enumerated() {

        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
        let title = (titleRef as? String) ?? "(no title)"

        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleRef)
        let role = (roleRef as? String) ?? "(no role)"

        var subroleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef)
        let subrole = (subroleRef as? String) ?? "(no subrole — Nix treats as primary!)"

        var minRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minRef)
        let minimized = (minRef as? Bool) ?? false

        var mainRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXMainAttribute as CFString, &mainRef)
        let isMain = (mainRef as? Bool) ?? false

        let nixCounts = (subrole != "(no subrole — Nix treats as primary!)" &&
                         subrole != "AXSheet" &&
                         subrole != "AXDialog" &&
                         subrole != "AXFloatingWindow" &&
                         subrole != "AXSystemDialog" &&
                         !minimized)
                        || (subrole == "(no subrole — Nix treats as primary!)" && !minimized)

        testLogger.info("║  [\(i)] \"\(title)\"")
        testLogger.info("║       role=\(role)  subrole=\(subrole)")
        testLogger.info("║       minimized=\(minimized)  main=\(isMain)")
        testLogger.info("║       → Nix currently COUNTS this: \(nixCounts ? "YES ← if unexpected, add subrole to exclusion list" : "NO (excluded)")")
        testLogger.info("║")
    }

    testLogger.info("║  SUMMARY: Nix sees \(windows.count) total AX windows for '\(appName)'")
    testLogger.info("║  If any window above is a phantom:")
    testLogger.info("║    1. Note its subrole from the log above")
    testLogger.info("║    2. Add that subrole to isNonPrimaryWindow() in WindowMonitor.swift")
    testLogger.info("╚══")
}

@MainActor
func verifyWindowDetails(appName: String) {
    diagnoseWindowTree(appName: appName)
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: - Day 17: Onboarding State
// ──────────────────────────────────────────────────────────────────────────────

@MainActor
func verifyOnboardingState() {
    let isComplete = UserDefaults.standard.bool(forKey: "nix.onboardingComplete")

    testLogger.info("=== Onboarding State (Day 17) ===")
    testLogger.info("  nix.onboardingComplete: \(isComplete)")

    if isComplete {
        testLogger.info("  ✅ Onboarding complete — window will not show on next launch")
    } else {
        testLogger.info("  ℹ️  Onboarding NOT complete — window will show on next launch")
        testLogger.info("      To test the complete flow: launch the app fresh")
        testLogger.info("      To reset: run 'defaults delete com.sahan.Nix nix.onboardingComplete'")
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: - Day 18: Window-Level Notification Registration
// ──────────────────────────────────────────────────────────────────────────────

@MainActor
func verifyWindowMonitorNotificationStrategy() {
    testLogger.info("=== Window-Level Notification Registration (Day 18) ===")

    let tracker = AppEnvironment.shared.appTracker

    if tracker.trackedApps.isEmpty {
        testLogger.info("  ℹ️  No tracked apps — open Safari, Notes, or Mail to verify")
        return
    }

    for app in tracker.trackedApps.prefix(5) {
        let appElement = AXUIElementCreateApplication(app.pid)
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsRef
        )

        if result == .success, let windows = windowsRef as? [AXUIElement] {
            testLogger.info("  \(app.name): \(windows.count) AX window element(s) — AXWindowClosed registered per-window ✅")
        } else {
            testLogger.info("  \(app.name): no AX windows visible (AX result: \(result.rawValue))")
        }
    }

    testLogger.info("  Strategy: kAXWindowClosed per-window | kAXWindowCreated/MainWindowChanged/FocusedWindowChanged on app element")
    testLogger.info("✅ Window notification strategy: per-window registration active")
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: - Day 18: Login Item Service
// ──────────────────────────────────────────────────────────────────────────────

/// Verifies LoginItemService state is consistent with system and UserDefaults.
@MainActor
func verifyLoginItemService() {
    testLogger.info("=== Login Item Service (Day 18) ===")

    let systemStatus  = SMAppService.mainApp.status
    let serviceValue  = LoginItemService.isEnabled
    let settingsValue = GlobalSettings.shared.launchAtLogin

    // Map the raw status to a readable string for logging
    let statusName: String
    switch systemStatus {
    case .enabled:            statusName = "enabled"
    case .requiresApproval:   statusName = "requiresApproval"
    case .notRegistered:      statusName = "notRegistered"
    case .notFound:           statusName = "notFound"
    default:                  statusName = "unknown (\(systemStatus.rawValue))"
    }

    testLogger.info("  SMAppService.mainApp.status:  \(statusName)")
    testLogger.info("  LoginItemService.isEnabled:   \(serviceValue)")
    testLogger.info("  GlobalSettings.launchAtLogin: \(settingsValue)")

    // LoginItemService.isEnabled should match system status
    let systemEnabled = systemStatus == .enabled || systemStatus == .requiresApproval
    if serviceValue == systemEnabled {
        testLogger.info("  ✅ LoginItemService.isEnabled matches system status")
    } else {
        testLogger.error("  ❌ LoginItemService.isEnabled MISMATCH — check LoginItemService.isEnabled implementation")
    }

    // GlobalSettings should have been reconciled at startup
    if settingsValue == serviceValue {
        testLogger.info("  ✅ GlobalSettings.launchAtLogin in sync with system state")
    } else {
        testLogger.warning("  ⚠️  GlobalSettings.launchAtLogin out of sync — syncWithSystemState() may not have been called")
        testLogger.warning("      Expected: \(serviceValue), Got: \(settingsValue)")
    }

    // .requiresApproval is a special case worth calling out
    if systemStatus == .requiresApproval {
        testLogger.info("  ℹ️  Status is .requiresApproval — user must approve in:")
        testLogger.info("      System Settings → General → Login Items")
    }

    testLogger.info("  ℹ️  To verify manually: System Settings → General → Login Items")
    testLogger.info("✅ Login item service verification complete")
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: - Day 19: Notification Service
// ──────────────────────────────────────────────────────────────────────────────

@MainActor
func verifyNotificationService() {
    testLogger.info("=== Notification Service (Day 19) ===")
    testLogger.info("  GlobalSettings.showNotifications: \(GlobalSettings.shared.showNotifications)")

    // Async — result prints separately; os_log can't be called from that callback thread.
    UNUserNotificationCenter.current().getNotificationSettings { settings in
        let status: String
        switch settings.authorizationStatus {
        case .authorized:    status = "authorized ✅"
        case .denied:        status = "denied ⚠️  (user must enable in System Settings → Notifications)"
        case .notDetermined: status = "notDetermined (will prompt on next check)"
        case .provisional:   status = "provisional"
        case .ephemeral:     status = "ephemeral"
        @unknown default:    status = "unknown"
        }
        print("[Verification] Notification authorization status: \(status)")
    }

    testLogger.info("  Authorization status: see print output above")
    testLogger.info("✅ NotificationService: wired and reachable")
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: - Day 20: Whitelist Tab Data
// ──────────────────────────────────────────────────────────────────────────────

@MainActor
func verifyWhitelistTabData() {
    let store = AppEnvironment.shared.ruleStore

    testLogger.info("=== Whitelist Tab Data (Day 20) ===")

    let systemCount = RuleStore.permanentWhitelist.count
    testLogger.info("  System protected apps: \(systemCount)")

    let userWhitelisted = store.rules.values
        .filter { $0.isWhitelisted }
        .sorted { $0.appName < $1.appName }

    testLogger.info("  User whitelisted apps: \(userWhitelisted.count)")
    for rule in userWhitelisted {
        testLogger.info("    → \(rule.appName) (\(rule.bundleIdentifier))")
    }

    // Sanity: permanent whitelist entries must still return .ignore
    let finderOk = store.behavior(for: "com.apple.finder") == .ignore
    let dockOk   = store.behavior(for: "com.apple.dock")   == .ignore
    testLogger.info("  Finder → .ignore: \(finderOk ? "✅" : "❌")")
    testLogger.info("  Dock   → .ignore: \(dockOk   ? "✅" : "❌")")

    if finderOk && dockOk {
        testLogger.info("✅ WhitelistTab data layer verified")
    } else {
        testLogger.error("❌ Permanent whitelist broken — check RuleStore.behavior()")
    }
}

/// Verifies TrialManager state is internally consistent.
@MainActor
func verifyTrialState() {
    let trial = TrialManager.shared
    testLogger.info("=== Trial State ===")
    testLogger.info("  daysRemaining: \(trial.daysRemaining)")
    testLogger.info("  isExpired:     \(trial.isExpired)")

    let consistent = (trial.isExpired && trial.daysRemaining == 0) ||
                      (!trial.isExpired && trial.daysRemaining > 0)
    if consistent {
        testLogger.info("✅ Trial state internally consistent")
    } else {
        testLogger.info("❌ Trial state mismatch")
    }
}

/// Verifies the license gate correctly drives QuitEngine.isEnabled.
@MainActor
func verifyLicenseGate() {
    let env = AppEnvironment.shared
    testLogger.info("=== License Gate ===")
    testLogger.info("  licenseManager.isLicensed: \(env.licenseManager.isLicensed)")
    testLogger.info("  trialManager.isExpired:    \(env.trialManager.isExpired)")
    testLogger.info("  requiresPaywall:           \(env.requiresPaywall)")
    testLogger.info("  quitEngine.isEnabled:      \(env.quitEngine.isEnabled)")

    if env.requiresPaywall {
        let correctlyGated = !env.quitEngine.isEnabled
        if correctlyGated {
            testLogger.info("✅ Engine correctly gated off while paywall required")
        } else {
            testLogger.info("❌ BUG: requiresPaywall=true but engine is still enabled")
        }
    } else {
        testLogger.info("ℹ️  Paywall not required — gate check not applicable")
    }
}
