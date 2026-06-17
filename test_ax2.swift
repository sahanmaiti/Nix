import AppKit
import ApplicationServices

let bundleID = "com.apple.Safari"
print("Testing \(bundleID), please open and close a window in Safari manually in the next 10 seconds.")

guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else {
    print("App not running")
    exit(1)
}

let pid = app.processIdentifier
var observer: AXObserver?
AXObserverCreate(pid, { _, element, notification, _ in
    print("[\(bundleID)] Fired:", notification as String)
}, &observer)

guard let obs = observer else { exit(1) }
let appElement = AXUIElementCreateApplication(pid)

AXObserverAddNotification(obs, appElement, "AXWindowClosed" as CFString, nil)
AXObserverAddNotification(obs, appElement, "AXUIElementDestroyed" as CFString, nil)
AXObserverAddNotification(obs, appElement, "AXMainWindowChanged" as CFString, nil)
AXObserverAddNotification(obs, appElement, kAXFocusedWindowChangedNotification as CFString, nil)

CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)

DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
    print("Done")
    exit(0)
}

RunLoop.main.run()
