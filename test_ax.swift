import AppKit
import ApplicationServices

let bundleID = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "com.apple.TextEdit"
print("Testing \(bundleID)")

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

CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)

let task = Process()
task.launchPath = "/usr/bin/osascript"
task.arguments = ["-e", "tell application id \"\(bundleID)\" to make new document", "-e", "delay 1", "-e", "tell application id \"\(bundleID)\" to close window 1"]
task.launch()

DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
    exit(0)
}

RunLoop.main.run()
