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

        // Step 1: Create the AXObserver
        var axObserver: AXObserver?
        let createError = AXObserverCreate(pid, axWindowEventCallback, &axObserver)

        guard createError == .success, let observer = axObserver else {
            logger.error("AXObserverCreate failed for \(name): error \(createError.rawValue)")
            return
        }

        // Step 2: Get the app-level AX element
        let appElement = AXUIElementCreateApplication(pid)

        // Step 3: Pack `self` as an opaque pointer for the C callback
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // Step 4: Register for window notifications
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

        // Step 5: Connect to the main run loop
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

        // Step 6: Store the observer (keeps it alive via ARC)
        observers[pid]       = observer
        lastWindowCount[pid] = visibleWindowCount(for: pid)

        logger.info("✅ Monitoring started: \(name) (PID \(pid))")
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - Observer Removal
    // ─────────────────────────────────────────────────────────────

    private func removeObserver(for pid: pid_t) {
        guard let observer = observers[pid] else { return }

        // Remove from run loop BEFORE releasing — order matters.
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

        // 150ms debounce: lets the AX tree settle after the closing animation
        // before we count windows. Without this we sometimes get stale counts.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
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

        // Never evaluate a hidden app — Cmd+H hides windows without closing them.
        guard !app.isHidden else {
            logger.debug("'\(app.localizedName ?? "?")' is hidden — skipping evaluation")
            return
        }

        let windowCount    = visibleWindowCount(for: pid)
        let previousCount  = lastWindowCount[pid] ?? 0
        lastWindowCount[pid] = windowCount

        logger.info("'\(app.localizedName ?? "?")': \(windowCount) visible window(s) (was \(previousCount))")

        if windowCount == 0 {
            logger.info("🎯 Zero windows — firing onZeroWindows for '\(app.localizedName ?? "?")'")
            onZeroWindows?(app)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - C Callback (must be a top-level free function, not a method)
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
        // ✅ FIX: Comparing against our locally defined string constants.
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

    /// Returns the number of truly visible (non-minimized, non-sheet) windows
    /// for the given process. This is the count that matters for quit decisions.
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
