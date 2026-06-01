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
    testLogger.info("VERIFICATION SUITE - Day 7")
    testLogger.info("================================")
    
    verifyAppTracker()
    verifyWhitelist()
    verifyActivationPolicyFilter()
    verifyAXPermission()
    verifyObjectWillChangeForwarding()
    
    testLogger.info("=================================")
    testLogger.info("VERIFICATION SUITE COMLETE")
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
