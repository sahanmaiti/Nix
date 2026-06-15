import ApplicationServices
import AppKit
import os.log


// ─────────────────────────────────────────────────────────────────────────────
// MARK: - AX Notification Constants
// ─────────────────────────────────────────────────────────────────────────────

private let kAXWindowClosedStr       = "AXWindowClosed"
private let kAXWindowCreatedStr      = "AXWindowCreated"
private let kAXMainWindowChangedStr  = "AXMainWindowChanged"


// ─────────────────────────────────────────────────────────────────────────────
// MARK: - WindowMonitor
// ─────────────────────────────────────────────────────────────────────────────

final class WindowMonitor {

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Outbound Callbacks
    // ─────────────────────────────────────────────────────────────────

    var onZeroWindows:    ((NSRunningApplication) -> Void)?
    var onWindowAppeared: ((pid_t) -> Void)?


    // ─────────────────────────────────────────────────────────────────
    // MARK: - Internal State
    // ─────────────────────────────────────────────────────────────────

    private var observers:           [pid_t: AXObserver]      = [:]
    private var lastWindowCount:     [pid_t: Int]              = [:]
    private var pendingPhase1Checks: [pid_t: DispatchWorkItem] = [:]
    private var pendingPhase2PIDs:   Set<pid_t>                = []

    private let debounceInterval: TimeInterval = 0.30

    private let logger = Logger(subsystem: "com.sahan.Nix", category: "WindowMonitor")


    // ─────────────────────────────────────────────────────────────────
    // MARK: - Known Hiders
    // ─────────────────────────────────────────────────────────────────

    private let knownHiders: Set<String> = [
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
        "com.apple.MobileSMS",
    ]


    // ─────────────────────────────────────────────────────────────────
    // MARK: - Public Interface
    // ─────────────────────────────────────────────────────────────────

    func startMonitoring(app: NSRunningApplication) {
        let pid = app.processIdentifier

        guard observers[pid] == nil else {
            logger.debug("Already monitoring '\(app.localizedName ?? "?")' — skipping")
            return
        }
        guard AXIsProcessTrusted() else {
            logger.warning("No AX permission — cannot monitor '\(app.localizedName ?? "?")'")
            return
        }

        createObserver(for: app)
    }

    func stopMonitoring(app: NSRunningApplication) {
        let pid = app.processIdentifier

        pendingPhase1Checks[pid]?.cancel()
        pendingPhase1Checks.removeValue(forKey: pid)
        pendingPhase2PIDs.remove(pid)
        removeObserver(for: pid)
        lastWindowCount.removeValue(forKey: pid)

        logger.info("Stopped monitoring '\(app.localizedName ?? "?")'")
    }


    // ─────────────────────────────────────────────────────────────────
    // MARK: - Observer Creation
    // ─────────────────────────────────────────────────────────────────

    private func createObserver(for app: NSRunningApplication) {
        let pid  = app.processIdentifier
        let name = app.localizedName ?? "unknown"

        var axObserver: AXObserver?
        let createErr = AXObserverCreate(pid, axWindowEventCallback, &axObserver)

        guard createErr == .success, let observer = axObserver else {
            logger.error("AXObserverCreate failed for '\(name)': \(createErr.rawValue)")
            return
        }

        let appElement = AXUIElementCreateApplication(pid)
        let selfPtr    = Unmanaged.passUnretained(self).toOpaque()

        // Register exactly three events. See the MARK comment at the top for
        // the full reasoning behind this specific selection.
        registerNotification(kAXWindowClosedStr,      on: appElement, observer: observer, context: selfPtr, appName: name)
        registerNotification(kAXWindowCreatedStr,     on: appElement, observer: observer, context: selfPtr, appName: name)
        registerNotification(kAXMainWindowChangedStr, on: appElement, observer: observer, context: selfPtr, appName: name)

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)

        observers[pid]       = observer
        lastWindowCount[pid] = currentWindowCount(for: pid)

        logger.info("✅ Monitoring started: '\(name)' (PID \(pid)) — \(self.lastWindowCount[pid] ?? 0) window(s)")
    }

    @discardableResult
    private func registerNotification(
        _ notification: String,
        on element:     AXUIElement,
        observer:       AXObserver,
        context:        UnsafeMutableRawPointer,
        appName:        String
    ) -> Bool {
        let result = AXObserverAddNotification(observer, element, notification as CFString, context)
        switch result {
        case .success:
            logger.debug("Registered '\(notification)' for '\(appName)'")
            return true
        case .notificationAlreadyRegistered:
            logger.debug("'\(notification)' already registered for '\(appName)' — OK")
            return true
        default:
            logger.warning("Failed to register '\(notification)' for '\(appName)': \(result.rawValue)")
            return false
        }
    }


    // ─────────────────────────────────────────────────────────────────
    // MARK: - Observer Removal
    // ─────────────────────────────────────────────────────────────────

    private func removeObserver(for pid: pid_t) {
        guard let observer = observers[pid] else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers.removeValue(forKey: pid)
    }


    // ─────────────────────────────────────────────────────────────────
    // MARK: - Unified Event Entry Point
    // ─────────────────────────────────────────────────────────────────

    func handlePossibleWindowChange(pid: pid_t, notification: String) {
        // Log which event triggered this — valuable for diagnosing future issues
        logger.debug("AX event '\(notification)' for PID \(pid) — debounce reset")

        pendingPhase1Checks[pid]?.cancel()

        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.pendingPhase1Checks.removeValue(forKey: pid)
            self.phaseOneCheck(pid: pid)
        }

        pendingPhase1Checks[pid] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: item)
    }


    // ─────────────────────────────────────────────────────────────────
    // MARK: - Phase 1: Count Check
    // ─────────────────────────────────────────────────────────────────

    private func phaseOneCheck(pid: pid_t) {
        guard let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.processIdentifier == pid }),
              !app.isTerminated else {
            logger.debug("Phase 1: PID \(pid) no longer running — skipping")
            return
        }

        guard !app.isHidden else {
            logger.debug("Phase 1: '\(app.localizedName ?? "?")' is hidden — skipping")
            return
        }

        let count    = currentWindowCount(for: pid)
        let previous = lastWindowCount[pid] ?? 0
        lastWindowCount[pid] = count

        logger.info("'\(app.localizedName ?? "?")': \(count) visible window(s) (was \(previous))")

        if count > 0 {
            pendingPhase2PIDs.remove(pid)
            onWindowAppeared?(pid)
            return
        }

        let bundleID     = app.bundleIdentifier ?? ""
        let isKnownHider = knownHiders.contains(bundleID)

        if isKnownHider {
            logger.debug("Phase 1: '\(app.localizedName ?? "?")' is a known hider — deferring to Phase 2")
            schedulePhaseTwoCheck(pid: pid)
        } else {
            logger.info("🎯 Phase 1 confirmed: zero windows — firing onZeroWindows for '\(app.localizedName ?? "?")'")
            onZeroWindows?(app)
        }
    }


    // ─────────────────────────────────────────────────────────────────
    // MARK: - Phase 2 (Known Hiders Only)
    // ─────────────────────────────────────────────────────────────────

    private func schedulePhaseTwoCheck(pid: pid_t) {
        guard !pendingPhase2PIDs.contains(pid) else {
            logger.debug("Phase 2 already pending for PID \(pid) — skipping duplicate")
            return
        }

        pendingPhase2PIDs.insert(pid)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            self.pendingPhase2PIDs.remove(pid)
            self.phaseTwoCheck(pid: pid)
        }
    }

    private func phaseTwoCheck(pid: pid_t) {
        guard let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.processIdentifier == pid }),
              !app.isTerminated else {
            logger.debug("Phase 2: PID \(pid) no longer running — skipping")
            return
        }

        guard !app.isHidden else {
            logger.debug("Phase 2: '\(app.localizedName ?? "?")' is hidden — hide-on-close confirmed, not quitting")
            return
        }

        let count = currentWindowCount(for: pid)
        logger.info("'\(app.localizedName ?? "?")': \(count) window(s) at Phase 2 (800ms total from event)")

        guard count == 0 else {
            logger.debug("Phase 2: '\(app.localizedName ?? "?")' has windows now — skipping quit")
            return
        }

        logger.info("🎯 Phase 2 confirmed: zero windows — firing onZeroWindows for '\(app.localizedName ?? "?")'")
        onZeroWindows?(app)
    }


    // ─────────────────────────────────────────────────────────────────
    // MARK: - Window Count Query
    // ─────────────────────────────────────────────────────────────────

    private func currentWindowCount(for pid: pid_t) -> Int {
        let appElement = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsRef
        )

        guard result == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return 0
        }

        return windows.filter { !isNonPrimaryWindow($0) }.count
    }

    private func isNonPrimaryWindow(_ window: AXUIElement) -> Bool {

        var minimizedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
           let isMinimized = minimizedRef as? Bool,
           isMinimized {
            return true
        }

        var subroleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef) == .success,
              let subrole = subroleRef as? String else {
            return false  // unknown subrole → assume primary (safe: prefer not quitting)
        }

        let nonPrimarySubroles: Set<String> = [
            "AXSheet",
            "AXDialog",
            "AXFloatingWindow",
            "AXSystemDialog",
        ]

        return nonPrimarySubroles.contains(subrole)
    }
}


// ─────────────────────────────────────────────────────────────────────────────
// MARK: - C Callback
// ─────────────────────────────────────────────────────────────────────────────

private func axWindowEventCallback(
    observer:         AXObserver,
    element:          AXUIElement,
    notificationName: CFString,
    refcon:           UnsafeMutableRawPointer?
) {
    guard let refcon = refcon else { return }

    let monitor = Unmanaged<WindowMonitor>.fromOpaque(refcon).takeUnretainedValue()

    var pid: pid_t = 0
    guard AXUIElementGetPid(element, &pid) == .success, pid != 0 else { return }

    let notifName = notificationName as String

    DispatchQueue.main.async {
        monitor.handlePossibleWindowChange(pid: pid, notification: notifName)
    }
}
