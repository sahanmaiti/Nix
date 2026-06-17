import AppKit
import ApplicationServices

let trusted = AXIsProcessTrusted()
print("Process trusted:", trusted)

let bundleID = "com.apple.TextEdit"
let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID })!
let pid = app.processIdentifier

var observer: AXObserver?
let err1 = AXObserverCreate(pid, { _, _, notif, _ in
    print("Fired:", notif)
}, &observer)
print("Create err:", err1.rawValue)

let obs = observer!
let appElement = AXUIElementCreateApplication(pid)
let err2 = AXObserverAddNotification(obs, appElement, "AXWindowClosed" as CFString, nil)
print("Add err:", err2.rawValue)

let err3 = AXObserverAddNotification(obs, appElement, "AXMainWindowChanged" as CFString, nil)
print("Add main err:", err3.rawValue)

CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)

DispatchQueue.main.asyncAfter(deadline: .now() + 5) { exit(0) }
RunLoop.main.run()
