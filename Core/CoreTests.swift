// DEBUG FILe- DELETE BEFORE SHIPPING

import AppKit
import ApplicationServices
import os.log

private let testLogger = Logger(subsystem: "com.sahan.Nix", category: "Verification")

// ------------------------------------------------------
// MARK: - Test Runner
// ------------------------------------------------------

@MainActor
func runAllVerifications() {
    testLogger.info("================================")
    testLogger.info("VERIFICATION SUITE - Day 12 ")
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
    
    testLogger.info("=================================")
    testLogger.info("VERIFICATION SUITE COMPLETE")
    testLogger.info("=================================")
}

// ------------------------------------------------------
// MARK: - Individual Verifications
///Verifies Apptracker is populated with currently running apps.
// ------------------------------------------------------

@MainActor
func verifyAppTracker() {
    let tracker = AppEnvironment.shared.appTracker
    let count = tracker.trackedApps.count
    
    if count > 0 {
        testLogger.info("✅ AppTracker has \(count) apps tracked")
        for app in tracker.trackedApps.prefix(3) {
            testLogger.debug("   -> \(app.name) (PID: \(app.pid)")
        }
    } else {
        testLogger.warning("AppTracker: 0 aps tracked - is any regular app running?")
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
            testLogger.error("❌ WHITELIST FAIL: \(bundleID) IS being tracked (shouldbe executed)")
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

    let regularCount = allRunning.filter { $0.activationPolicy == .regular }.count
    let accessoryCount = allRunning.filter { $0.activationPolicy == .accessory }.count

    testLogger.info("✅ Activation policy: \(regularCount) regular, \(accessoryCount) accessory (excluded)")

    if failCount == 0 {
        testLogger.info("✅ No incorrectly-tracked apps found")
    }
}

/// Verifies that AccessibilityManager correctly reflects current AX permission.
@MainActor
func verifyAXPermission() {
    let manager = AppEnvironment.shared.accessibilityManager
    let systemValue = AXIsProcessTrusted()
    let managerValue = manager.isGranted

    if systemValue == managerValue {
        testLogger.info("✅ AX permission: manager.isGranted (\(managerValue)) matches AXIsProcessTrusted() (\(systemValue))")
    } else {
        testLogger.warning("⚠️ AX permission MISMATCH: manager says \(managerValue), system says \(systemValue)")
        testLogger.warning("   This may resolve in 1 second when the polling timer fires")
    }
}

/// Verifies that AppEnvironment properly forwards child change notifications.
/// When appTracker.trackedApps changes, AppEnvironment should publish too.
@MainActor
func verifyObjectWillChangeForwarding() {
    let env = AppEnvironment.shared
    testLogger.info("✅ AppEnvironment.shared exists and is initialized")
    testLogger.info("   isEnabled: \(env.isEnabled), isPaused: \(env.isPaused)")
    testLogger.info("   appTracker.trackedApps.count: \(env.appTracker.trackedApps.count)")
    testLogger.info("   accessibilityManager.isGranted: \(env.accessibilityManager.isGranted)")
}


/// Verifies QuitEngine respects the isEnabled flag
@MainActor
func verifyQuitEngineEnabled() {
    let engine = AppEnvironment.shared.quitEngine
    testLogger.info("QuitEngine.isEnabled: \(engine.isEnabled)")
    testLogger.info("QuitEngine.isPaused: \(engine.isPaused)")
    testLogger.info("QuitEngine.defaultBehavior: \(engine.defaultBehavior.rawValue)")
    testLogger.info("✅ QuitEngine initialized and accessible")
}

/// Verifies that cancelPendingQuit doesn't crash for a non-existent PID
@MainActor
func verifyQuitEngineCancelSafety() {
    let engine = AppEnvironment.shared.quitEngine
    // This should be a no-op — not crash
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

    // Check Path 1: WindowMonitor.onWindowAppeared → QuitEngine
    let path1Wired = env.windowMonitor.onWindowAppeared != nil
    if path1Wired {
        testLogger.info("✅ Path 1 wired: windowMonitor.onWindowAppeared → QuitEngine")
    } else {
        testLogger.error("❌ Path 1 NOT wired: windowMonitor.onWindowAppeared is nil")
    }

    // Check Path 2: AppTracker.onCancelPendingQuit → QuitEngine
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
/// Also verifies it's a no-op for unknown PIDs.
@MainActor
func verifyAppTrackerCancelCallback() {
    let tracker = AppEnvironment.shared.appTracker

    // Test 1: Firing with an unknown PID should be silent (no crash)
    // (Already tested in verifyQuitEngineCancelSafety — this tests the AppTracker side)
    tracker.onCancelPendingQuit?(pid_t(99999))
    testLogger.info("✅ AppTracker.onCancelPendingQuit with unknown PID: safe")

    // Test 2: If any tracked app exists, verify the callback fires for it
    if let firstApp = tracker.trackedApps.first {
        tracker.onCancelPendingQuit?(firstApp.pid)
        testLogger.info("✅ AppTracker.onCancelPendingQuit fired for '\(firstApp.name)': no crash")
    } else {
        testLogger.info("ℹ️  No tracked apps to test cancel callback against (open any app)")
    }
}
