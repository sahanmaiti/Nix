import ApplicationServices
import AppKit
import os.log


// ─────────────────────────────────────────────────────────────────────────────
// MARK: - AX Notification Constants
// ─────────────────────────────────────────────────────────────────────────────

private let kAXWindowCreatedStr          = "AXWindowCreated"
private let kAXMainWindowChangedStr      = "AXMainWindowChanged"
private let kAXFocusedWindowChangedStr   = "AXFocusedWindowChanged"

private let kAXWindowClosedStr           = "AXWindowClosed"
private let kAXUIElementDestroyedStr     = "AXUIElementDestroyed"

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

    /// NSWorkspace fallback: apps reliably lose OS focus when their last window closes.
    /// Triggered by AppTracker when didDeactivateApplicationNotification fires.
    /// This is an indirect/ambiguous signal (also fires on plain app/Space switches),
    /// so it always routes through Phase 2 confirmation — never decides on one reading.
    func checkOnDeactivation(for pid: pid_t) {
        guard observers[pid] != nil else { return }
        logger.debug("Deactivation check for PID \(pid)")

        pendingPhase1Checks[pid]?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            pendingPhase1Checks.removeValue(forKey: pid)
            phaseOneCheck(pid: pid, isWeakSignal: true)
        }
        pendingPhase1Checks[pid] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: item)
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

        // ── App-level notifications ───────────────────────────────────────
        registerNotification(kAXWindowCreatedStr,        on: appElement, observer: observer, context: selfPtr, appName: name)
        registerNotification(kAXMainWindowChangedStr,    on: appElement, observer: observer, context: selfPtr, appName: name)
        registerNotification(kAXFocusedWindowChangedStr, on: appElement, observer: observer, context: selfPtr, appName: name)

        // ── Window-level close notification ───────────────────────────────
        registerWindowClosedOnAllCurrentWindows(pid: pid, observer: observer, context: selfPtr, appName: name)

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)

        observers[pid]       = observer
        // Best-effort baseline only — an inconclusive read here just means 0 to start with.
        lastWindowCount[pid] = currentWindowCount(for: pid) ?? 0

        logger.info("✅ Monitoring '\(name)' (PID \(pid)) — \(self.lastWindowCount[pid] ?? 0) window(s)")
    }

    private func registerWindowClosedOnAllCurrentWindows(
        pid:      pid_t,
        observer: AXObserver,
        context:  UnsafeMutableRawPointer,
        appName:  String
    ) {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?

        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
            logger.debug("'\(appName)': no windows yet — will register on first kAXWindowCreated")
            return
        }

        var registered = 0
        for window in windows {
            let result = AXObserverAddNotification(observer, window, kAXWindowClosedStr as CFString, context)
            switch result {
            case .success:                       registered += 1
            case .notificationAlreadyRegistered: registered += 1
            default:
                logger.warning("AXWindowClosed window-registration failed for '\(appName)': \(result.rawValue)")
            }
            AXObserverAddNotification(observer, window, kAXUIElementDestroyedStr as CFString, context)
        }

        logger.debug("AXWindowClosed registered on \(registered)/\(windows.count) window element(s) for '\(appName)'")
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
            logger.debug("Registered '\(notification)' on app element for '\(appName)'")
            return true
        case .notificationAlreadyRegistered:
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
        logger.debug("AX event '\(notification)' for PID \(pid) — debounce reset")

        if notification == kAXWindowCreatedStr, let observer = observers[pid] {
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            let appName = NSWorkspace.shared.runningApplications
                .first(where: { $0.processIdentifier == pid })?
                .localizedName ?? "unknown"
            registerWindowClosedOnAllCurrentWindows(pid: pid, observer: observer, context: selfPtr, appName: appName)
        }

        pendingPhase1Checks[pid]?.cancel()

        // Only AXWindowClosed / AXUIElementDestroyed are direct evidence a window closed.
        // WindowCreated / MainWindowChanged / FocusedWindowChanged ALSO fire on minimize,
        // refocus, and app/Space switches — those must be treated as weak signals too,
        // same as the deactivation fallback, or they bypass Phase 2 confirmation.
        let isStrongCloseSignal = (notification == kAXWindowClosedStr || notification == kAXUIElementDestroyedStr)

        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.pendingPhase1Checks.removeValue(forKey: pid)
            self.phaseOneCheck(pid: pid, isWeakSignal: !isStrongCloseSignal)
        }

        pendingPhase1Checks[pid] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: item)
    }


    // ─────────────────────────────────────────────────────────────────
    // MARK: - Phase 1: Count Check
    // ─────────────────────────────────────────────────────────────────

    private func phaseOneCheck(pid: pid_t, isWeakSignal: Bool = false) {
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

        guard let count = currentWindowCount(for: pid) else {
            // AX query failed (busy/transitioning — common right after minimize + app/Space switch).
            // Never treat a failed read as zero. Defer to Phase 2 for a clean re-read.
            logger.debug("Phase 1: inconclusive AX read for '\(app.localizedName ?? "?")' — deferring to Phase 2")
            schedulePhaseTwoCheck(pid: pid)
            return
        }

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

        if isKnownHider || isWeakSignal {
            logger.debug("Phase 1: deferring to Phase 2 (weakSignal=\(isWeakSignal), knownHider=\(isKnownHider)) for '\(app.localizedName ?? "?")'")
            schedulePhaseTwoCheck(pid: pid)
        } else {
            logger.info("🎯 Phase 1 confirmed: zero windows — firing onZeroWindows for '\(app.localizedName ?? "?")'")
            onZeroWindows?(app)
        }
    }


    // ─────────────────────────────────────────────────────────────────
    // MARK: - Phase 2 (Known Hiders + Weak-Signal Confirmation)
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

        guard let count = currentWindowCount(for: pid) else {
            // Still inconclusive — do NOT quit on a failed read. The next real AX event
            // (focus change, activation, close) will re-trigger evaluation.
            logger.debug("Phase 2: inconclusive AX read for '\(app.localizedName ?? "?")' — skipping quit")
            return
        }

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

    /// Returns nil if the AX query could not be completed (app busy/transitioning/backgrounded
    /// mid-transition). Callers MUST treat nil as "unknown," never as "zero windows" — conflating
    /// the two is what causes apps to be incorrectly quit right after minimize + app/Space switch.
    private func currentWindowCount(for pid: pid_t) -> Int? {
        let appElement = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsRef
        )

        guard result == .success else {
            logger.debug("AX windows query failed (error \(result.rawValue)) for PID \(pid) — inconclusive, not zero")
            return nil
        }

        guard let windows = windowsRef as? [AXUIElement] else {
            return 0
        }

        return windows.filter { !isNonPrimaryWindow($0) }.count
    }

    private func isNonPrimaryWindow(_ window: AXUIElement) -> Bool {
        var subroleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef) == .success,
              let subrole = subroleRef as? String else {
            return false
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
