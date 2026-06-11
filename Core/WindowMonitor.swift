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
    
    private var observers:       [pid_t: AXObserver]        = [:]
    private var windowObservers: [pid_t: Set<WindowHandle>] = [:]
    private var lastWindowCount: [pid_t: Int]               = [:]

    private let logger = Logger(subsystem: "com.sahan.Nix", category: "WindowMonitor")

    // ─────────────────────────────────────────────────────────────
    // MARK: - Known Hiders
    // ─────────────────────────────────────────────────────────────

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
        windowObservers.removeValue(forKey: pid)
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
            logger.error("AXObserverCreate failed for '\(name)': error \(createError.rawValue)")
            return
        }

        let appElement = AXUIElementCreateApplication(pid)
        let selfPtr    = Unmanaged.passUnretained(self).toOpaque()

        let createdResult = AXObserverAddNotification(
            observer,
            appElement,
            kAXWindowCreatedStr as CFString,
            selfPtr
        )

        if createdResult != .success && createdResult != .notificationAlreadyRegistered {
            logger.warning("Failed to register AXWindowCreated for '\(name)': \(createdResult.rawValue)")
        } else {
            logger.debug("Registered AXWindowCreated on app element for '\(name)'")
        }
        
        let closedResult = AXObserverAddNotification(
            observer,
            appElement,
            kAXWindowClosedStr as CFString,
            selfPtr
        )

        logger.debug("AXWindowClosed on app element result: \(closedResult.rawValue)")
        
        let registeredCount = registerWindowClosedOnAllCurrentWindows(
            pid: pid,
            observer: observer,
            selfPtr: selfPtr,
            appName: name
        )

        logger.debug("Registered AXWindowClosed on \(registeredCount) existing window(s) for '\(name)'")

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

        observers[pid]       = observer
        lastWindowCount[pid] = visibleWindowCount(for: pid)

        logger.info("✅ Monitoring started: '\(name)' (PID \(pid)) — \(registeredCount) window(s) observed")
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Window-Level kAXWindowClosed Registration
    // ─────────────────────────────────────────────────────────────────────────

    @discardableResult
    private func registerWindowClosedOnAllCurrentWindows(
        pid: pid_t,
        observer: AXObserver,
        selfPtr: UnsafeMutableRawPointer,
        appName: String
    ) -> Int {
        let appElement = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsRef
        )

        guard result == .success, let windows = windowsRef as? [AXUIElement] else {
            logger.debug("No windows to register for '\(appName)' (AX result: \(result.rawValue))")
            return 0
        }

        var registeredCount = 0

        for window in windows {
            if registerWindowClosed(window: window, pid: pid, observer: observer, selfPtr: selfPtr) {
                registeredCount += 1
            }
        }

        return registeredCount
    }

    @discardableResult
    private func registerWindowClosed(
        window: AXUIElement,
        pid: pid_t,
        observer: AXObserver,
        selfPtr: UnsafeMutableRawPointer
    ) -> Bool {
        let handle = WindowHandle(element: window)

        if windowObservers[pid]?.contains(handle) == true {
            return false
        }

        let addResult = AXObserverAddNotification(
            observer,
            window,
            kAXWindowClosedStr as CFString,
            selfPtr
        )

        switch addResult {
        case .success:
            if windowObservers[pid] == nil { windowObservers[pid] = [] }
            windowObservers[pid]!.insert(handle)
            return true

        case .notificationAlreadyRegistered:
            if windowObservers[pid] == nil { windowObservers[pid] = [] }
            windowObservers[pid]!.insert(handle)
            return false

        default:
            logger.debug("Could not register AXWindowClosed on window element: \(addResult.rawValue)")
            return false
        }
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

    func handleWindowCreated(pid: pid_t, windowElement: AXUIElement) {
        logger.debug("Window created event: PID \(pid)")
        
        guard let observer = observers[pid] else {
            logger.warning("handleWindowCreated: no observer for PID \(pid) — cannot register close")
            return
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let registered = registerWindowClosed(
            window: windowElement,
            pid: pid,
            observer: observer,
            selfPtr: selfPtr
        )

        if registered {
            logger.debug("Registered AXWindowClosed on new window for PID \(pid)")
        }

        lastWindowCount[pid] = visibleWindowCount(for: pid)
        onWindowAppeared?(pid)
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - Window Count Evaluation
    // ─────────────────────────────────────────────────────────────

    private func evaluateWindowCount(for pid: pid_t) {
        guard let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.processIdentifier == pid }) else {
            logger.debug("App with PID \(pid) no longer running — skipping evaluation")
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
            logger.info("Zero windows — firing onZeroWindows for '\(app.localizedName ?? "?")'")
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
        switch notification {
        case kAXWindowClosedStr:
            monitor.handleWindowClosed(pid: pid)

        case kAXWindowCreatedStr:
            monitor.handleWindowCreated(pid: pid, windowElement: element)

        default:
            break
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

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - WindowHandle
// ─────────────────────────────────────────────────────────────────────────────

private struct WindowHandle: Hashable {
    let element: AXUIElement

    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }

    static func == (lhs: WindowHandle, rhs: WindowHandle) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }
}
