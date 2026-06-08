/// WindowMonitor is the DETECTION layer of Nix. It does exactly one thing:
/// watch every tracked app for window-close events and report when an app
/// reaches zero visible windows.


import ApplicationServices
import AppKit
import os.log

// ─────────────────────────────────────────────────────────────────────────────
// AX Notification String Constants
// ─────────────────────────────────────────────────────────────────────────────
private let kAXWindowClosedStr  = "AXWindowClosed"
private let kAXWindowCreatedStr = "AXWindowCreated"


final class WindowMonitor {

    // ─────────────────────────────────────────────────────────────
    // MARK: - Callbacks
    // ─────────────────────────────────────────────────────────────

    var onZeroWindows:    ((NSRunningApplication) -> Void)?
    var onWindowAppeared: ((pid_t) -> Void)?

    // ─────────────────────────────────────────────────────────────
    // MARK: - Observer Storage
    // ─────────────────────────────────────────────────────────────

    private var observers:       [pid_t: AXObserver] = [:]
    private var lastWindowCount: [pid_t: Int]        = [:]

    private let logger = Logger(subsystem: "com.sahan.Nix", category: "WindowMonitor")

    // ─────────────────────────────────────────────────────────────
    // MARK: - Known Hiders
    // ─────────────────────────────────────────────────────────────

    private let knownHiders: Set<String> = [
        "com.hnc.Discord",
        "com.spotify.client",
        "com.tinyspeck.slackmacgap",     // Slack
        "com.readdle.smartemail",         // Spark
        "com.mimestream.Mimestream",
        "com.apple.iChat",               // Messages
        "us.zoom.xos",                   // Zoom
        "com.microsoft.teams",
        "com.microsoft.teams2",          // Teams new version
        "com.skype.skype",
        "com.apple.MobileSMS",
    ]

    // ─────────────────────────────────────────────────────────────
    // MARK: - Public Interface
    // ─────────────────────────────────────────────────────────────

    func startMonitoring(app: NSRunningApplication) {
        let pid = app.processIdentifier

        guard observers[pid] == nil else {
            logger.debug("Already monitoring \(app.localizedName ?? "?") — skipping")
            return
        }

        guard AXIsProcessTrusted() else {
            logger.warning("No AX permission — cannot monitor \(app.localizedName ?? "?")")
            return
        }

        createObserver(for: app)
    }

    func stopMonitoring(app: NSRunningApplication) {
        let pid = app.processIdentifier
        removeObserver(for: pid)
        lastWindowCount.removeValue(forKey: pid)
        logger.info("Stopped monitoring \(app.localizedName ?? "?")")
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - Observer Creation
    // ─────────────────────────────────────────────────────────────

    private func createObserver(for app: NSRunningApplication) {
        let pid  = app.processIdentifier
        let name = app.localizedName ?? "unknown"

        var axObserver: AXObserver?
        let createError = AXObserverCreate(pid, axWindowEventCallback, &axObserver)

        guard createError == .success, let observer = axObserver else {
            logger.error("AXObserverCreate failed for \(name): error \(createError.rawValue)")
            return
        }

        let appElement = AXUIElementCreateApplication(pid)
        let selfPtr    = Unmanaged.passUnretained(self).toOpaque()

        let notifications: [CFString] = [
            kAXWindowClosedStr  as CFString,
            kAXWindowCreatedStr as CFString
        ]

        for notification in notifications {
            let addError = AXObserverAddNotification(
                observer,
                appElement,
                notification,
                selfPtr
            )

            if addError != .success && addError != .notificationAlreadyRegistered {
                logger.warning("Failed to register \(notification) for \(name): \(addError.rawValue)")
            }
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

        observers[pid]       = observer
        lastWindowCount[pid] = visibleWindowCount(for: pid)

        logger.info("✅ Monitoring started: \(name) (PID \(pid))")
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - Observer Removal
    // ─────────────────────────────────────────────────────────────

    private func removeObserver(for pid: pid_t) {
        guard let observer = observers[pid] else { return }

        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

        observers.removeValue(forKey: pid)
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - Event Handling
    // ─────────────────────────────────────────────────────────────

    func handleWindowClosed(pid: pid_t) {
        logger.debug("Window closed event: PID \(pid)")
        
        let bundleID = NSWorkspace.shared.runningApplications
            .first(where: { $0.processIdentifier == pid })?.bundleIdentifier ?? ""

        let isKnownHider = knownHiders.contains(bundleID)
        let debounce: TimeInterval = isKnownHider ? 0.5 : 0.15

        if isKnownHider {
            logger.debug("Known hider '\(bundleID)' — using extended debounce (\(Int(debounce * 1000))ms)")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + debounce) { [weak self] in
            self?.evaluateWindowCount(for: pid)
        }
    }

    func handleWindowCreated(pid: pid_t) {
        logger.debug("Window created event: PID \(pid)")
        onWindowAppeared?(pid)
        lastWindowCount[pid] = visibleWindowCount(for: pid)
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - Window Count Evaluation
    // ─────────────────────────────────────────────────────────────

    private func evaluateWindowCount(for pid: pid_t) {
        guard let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.processIdentifier == pid }) else {
            logger.debug("App with PID \(pid) no longer running — skipping")
            return
        }

        guard !app.isHidden else {
            logger.debug("'\(app.localizedName ?? "?")' is hidden — skipping evaluation")
            return
        }

        let windowCount   = visibleWindowCount(for: pid)
        let previousCount = lastWindowCount[pid] ?? 0
        lastWindowCount[pid] = windowCount

        logger.info("'\(app.localizedName ?? "?")': \(windowCount) visible window(s) (was \(previousCount))")

        if windowCount == 0 {
            logger.info("🎯 Zero windows — firing onZeroWindows for '\(app.localizedName ?? "?")'")
            onZeroWindows?(app)
        }
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

    let monitor      = Unmanaged<WindowMonitor>.fromOpaque(refcon).takeUnretainedValue()
    let notification = notificationName as String

    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)

    DispatchQueue.main.async {
        if notification == kAXWindowClosedStr {
            monitor.handleWindowClosed(pid: pid)
        } else if notification == kAXWindowCreatedStr {
            monitor.handleWindowCreated(pid: pid)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Window Counting Helper
// ─────────────────────────────────────────────────────────────────────────────

private extension WindowMonitor {

    func visibleWindowCount(for pid: pid_t) -> Int {
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
            !isMinimized(window) && !isSheet(window) && !isDialog(window)
        }.count
    }

    private func isMinimized(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value)
        return (value as? Bool) == true
    }

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
}
