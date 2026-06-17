import AppKit
import ApplicationServices

let bundleID = "com.apple.TextEdit"
print("Testing TextEdit")

guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else {
    print("App not running")
    exit(1)
}

let pid = app.processIdentifier
var observer: AXObserver?
AXObserverCreate(pid, { _, element, notification, _ in
    print("[TextEdit] Fired:", notification as String)
}, &observer)

guard let obs = observer else { exit(1) }
let appElement = AXUIElementCreateApplication(pid)

AXObserverAddNotification(obs, appElement, "AXWindowClosed" as CFString, nil)
AXObserverAddNotification(obs, appElement, "AXUIElementDestroyed" as CFString, nil)
AXObserverAddNotification(obs, appElement, "AXMainWindowChanged" as CFString, nil)

CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)

DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
    print("Done")
    exit(0)
}
RunLoop.main.run()
