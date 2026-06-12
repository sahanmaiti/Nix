import ApplicationServices
import AppKit
import os.log


// ─────────────────────────────────────────────────────────────────────────────
// MARK: - AX Notification Constants
// ─────────────────────────────────────────────────────────────────────────────

private let kAXWindowCreatedStr        = "AXWindowCreated"
private let kAXMainWindowChangedStr    = "AXMainWindowChanged"
private let kAXFocusedWindowChangedStr = "AXFocusedWindowChanged"


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

    private var observers: [pid_t: AXObserver] = [:]
    private var lastWindowCount: [pid_t: Int] = [:]
    private var pendingPhase1Checks: [pid_t: DispatchWorkItem] = [:]
    private var pendingPhase2PIDs: Set<pid_t> = []
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

            logger.debug("Already monitoring '\(app.localizedName ?? "?")' — skipping duplicate")
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

        // ── Step 1: Create the AXObserver ───────────────────────────
 
        var axObserver: AXObserver?
        let createErr = AXObserverCreate(pid, axWindowEventCallback, &axObserver)

        guard createErr == .success, let observer = axObserver else {
            logger.error("AXObserverCreate failed for '\(name)': \(createErr.rawValue)")
            return
        }

        // ── Step 2: Get the application-level AX element ────────────

        let appElement = AXUIElementCreateApplication(pid)

        // ── Step 3: Capture 'self' as an opaque context pointer ─────

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // ── Step 4: Register notifications (all on the APP element) ─

        registerNotification(
            kAXWindowCreatedStr,
            on:      appElement,
            observer: observer,
            context:  selfPtr,
            appName:  name
        )


        registerNotification(
            kAXMainWindowChangedStr,
            on:      appElement,
            observer: observer,
            context:  selfPtr,
            appName:  name
        )


        registerNotification(
            kAXFocusedWindowChangedStr,
            on:      appElement,
            observer: observer,
            context:  selfPtr,
            appName:  name
        )

        // ── Step 5: Attach observer to the main run loop ─────────────

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

        // ── Step 6: Store observer and initial window count ──────────
        observers[pid]       = observer
        lastWindowCount[pid] = currentWindowCount(for: pid)

        logger.info("✅ Monitoring started: '\(name)' (PID \(pid)) — \(self.lastWindowCount[pid] ?? 0) window(s)")
    }

    @discardableResult
    private func registerNotification(
        _ notification: String,
        on element:    AXUIElement,
        observer:      AXObserver,
        context:       UnsafeMutableRawPointer,
        appName:       String
    ) -> Bool {
        let result = AXObserverAddNotification(
            observer,
            element,
            notification as CFString,
            context
        )

        switch result {
        case .success:
            logger.debug("Registered '\(notification)' for '\(appName)'")
            return true

        case .notificationAlreadyRegistered:

            logger.debug("'\(notification)' already registered for '\(appName)' — OK")
            return true

        default:

            logger.warning("Failed to register '\(notification)' for '\(appName)': error \(result.rawValue)")
            return false
        }
    }


    // ─────────────────────────────────────────────────────────────────
    // MARK: - Observer Removal
    // ─────────────────────────────────────────────────────────────────

    private func removeObserver(for pid: pid_t) {
        guard let observer = observers[pid] else { return }


        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )


        observers.removeValue(forKey: pid)
    }


    // ─────────────────────────────────────────────────────────────────
    // MARK: - Event Handlers (called from C callback via main queue)
    // ─────────────────────────────────────────────────────────────────


    func handleWindowCreated(pid: pid_t) {
        let newCount = currentWindowCount(for: pid)
        lastWindowCount[pid] = newCount

        logger.debug("Window created for '\(self.resolvedName(pid))' — count now \(newCount)")


        pendingPhase1Checks[pid]?.cancel()
        pendingPhase1Checks.removeValue(forKey: pid)

        pendingPhase2PIDs.remove(pid)

        onWindowAppeared?(pid)
    }

 
    func handlePossibleWindowClose(pid: pid_t) {
        pendingPhase1Checks[pid]?.cancel()

        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.pendingPhase1Checks.removeValue(forKey: pid)
            self.phaseOneCheck(pid: pid)
        }

        pendingPhase1Checks[pid] = item

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }


    // ─────────────────────────────────────────────────────────────────
    // MARK: - Two-Phase TOCTOU Detection
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

        logger.info("'\(app.localizedName ?? "?")': \(count) window(s) after Phase 1 (was \(previous))")

        guard count == 0 else { return }

        let bundleID      = app.bundleIdentifier ?? ""
        let isKnownHider  = knownHiders.contains(bundleID)

        if isKnownHider {

            logger.debug("Phase 1: '\(app.localizedName ?? "?")' is a known hider — deferring to Phase 2")
            schedulePhaseTwoCheck(pid: pid)
        } else {
            logger.info("🎯 Phase 1 confirmed: zero windows — firing for '\(app.localizedName ?? "?")'")
            onZeroWindows?(app)
        }
    }

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
            logger.debug("Phase 2: '\(app.localizedName ?? "?")' is hidden — hide-on-close confirmed. Not quitting.")
            return
        }

        let count = currentWindowCount(for: pid)
        logger.info("'\(app.localizedName ?? "?")': \(count) window(s) at Phase 2 (650ms)")

        guard count == 0 else {
            logger.debug("Phase 2: '\(app.localizedName ?? "?")' has windows now — skipping quit")
            return
        }

        logger.info("🎯 Phase 2 confirmed: zero windows — firing for '\(app.localizedName ?? "?")'")
        onZeroWindows?(app)
    }


    // ─────────────────────────────────────────────────────────────────
    // MARK: - Window Count
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

        return windows.filter { window in

            !isSheet(window) && !isDialog(window) && !isFloatingWindow(window)
        }.count
    }

    // ── Window type helpers ─────────────────────────────────────────

    private func isSheet(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &value)
        return (value as? String) == "AXSheet"
    }

    private func isDialog(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &value)
        return (value as? String) == "AXDialog"
    }

    private func isFloatingWindow(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &value)
        return (value as? String) == "AXFloatingWindow"
    }

    // ── Utility ─────────────────────────────────────────────────────


    private func resolvedName(_ pid: pid_t) -> String {
        NSWorkspace.shared.runningApplications
            .first(where: { $0.processIdentifier == pid })?
            .localizedName ?? "PID:\(pid)"
    }
}


// ─────────────────────────────────────────────────────────────────────────────
// MARK: - C Callback (free function — required by AXObserverCreate API)
// ─────────────────────────────────────────────────────────────────────────────


private func axWindowEventCallback(
    observer:         AXObserver,
    element:          AXUIElement,
    notificationName: CFString,
    refcon:           UnsafeMutableRawPointer?
) {
    guard let refcon = refcon else { return }


    let monitor      = Unmanaged<WindowMonitor>.fromOpaque(refcon).takeUnretainedValue()
    let notification = notificationName as String


    var pid: pid_t = 0
    let pidErr = AXUIElementGetPid(element, &pid)

    guard pidErr == .success, pid != 0 else {

        return
    }


    DispatchQueue.main.async {
        switch notification {

        case kAXWindowCreatedStr:

            monitor.handleWindowCreated(pid: pid)

        case kAXMainWindowChangedStr, kAXFocusedWindowChangedStr:

            monitor.handlePossibleWindowClose(pid: pid)

        default:
            break
        }
    }
}
