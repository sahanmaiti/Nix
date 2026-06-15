// PURPOSE: Pure functions for reading the Accessibility tree.
/// These functions answer ONE question: "How many real, visible windows does this process have right now ?"

import ApplicationServices
import AppKit
import os.log

private let axLogger = Logger(subsystem: "com.sahan.Nix", category: "AXWindowReader")

//-------------------------------
//MARK: - Core Window Counting
//-------------------------------
/// Returns the number of "real" visible windows for the given process ID.

func visibleWindowCount(for pid: pid_t) -> Int {
    return visibleWindows(for: pid).count
}

func visibleWindows(for pid: pid_t) -> [AXUIElement] {
    
    //--- Step 1: Get the application element ------------
    let appElement: AXUIElement = AXUIElementCreateApplication(pid)
    
    //--- Step 2: Read the windows attributes ------------
        var windowsRef: CFTypeRef?
    let result: AXError = AXUIElementCopyAttributeValue(
        appElement,
        kAXWindowsAttribute as CFString,
        &windowsRef
    )
    
    //--- Step 3: Check the error ----------
    guard result == .success else {
        return []
    }
    
    //--- Step 4: Cast CFTypeRef -> [AXUIElement] ----------
        guard let windows = windowsRef as? [AXUIElement] else {
        return []
    }
    
    //--- Step 5: Filter th only "real" windows ---------
        return windows.filter { isRealWindow($0) }}


// -----------------------------------------------------------------
// MARK: -  Window Classification
// -----------------------------------------------------------------
/// Returns true if the wondow element represents a "real" visible window that counts towards an app's window presence.

func isRealWindow(_ window: AXUIElement) -> Bool {
    if isMinimized(window) {
            return false
        }
    if isSheetOrDialog(window) {
        return false
    }
    return true
}

/// Returns true if the window is currently minimized to the Dock,
func isMinimized(_ window: AXUIElement) -> Bool {
    var minimizedRef: CFTypeRef?
    
    let result = AXUIElementCopyAttributeValue(
        window,
        kAXMinimizedAttribute as CFString,
        &minimizedRef
    )
    guard result == .success, let isMinimized = minimizedRef as? Bool else {
           return false
       }
       return isMinimized
}

/// Returns true if the window is a sheet, dialog, or other non-primary windows type.
func isSheetOrDialog(_ window: AXUIElement) -> Bool {
    
    var subroleRef: CFTypeRef?
    
    let result = AXUIElementCopyAttributeValue(
        window,
        kAXSubroleAttribute as CFString,
        &subroleRef
    )
    guard result == .success, let subrole = subroleRef as? String else {
            return false
        }
    let nonPrimarySubroles: Set<String> = [
        "AXSheet",          // Save/print dialogs attached to windows
        "AXDialog",         // Modal alert dialogs
        "AXFloatingWindow", // Tool palettes in create apps.
        "AXSystemDialog"    // OS-level dialogs
    ]
    return nonPrimarySubroles.contains(subrole)
}

// --------------------------------------------------
// MARK: - Application-Level State Checks
// --------------------------------------------------
///Returns true if the applicatino is currently hidden.

func isApplicationHidden(pid: pid_t) -> Bool {
    
    let appElemnent = AXUIElementCreateApplication(pid)
    var hiddenRef: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(
        appElemnent,
        kAXHiddenAttribute as CFString,
        &hiddenRef
    )
    
    guard result == .success, let hidden = hiddenRef as? Bool else {
           return false
       }
    return hidden
}

// -----------------------------------------------------
// MARK: - Debug Helper
// -----------------------------------------------------
/// Prints a complete diagnostic report for one running app to the console.

func printWindowReport(for app: NSRunningApplication) {
    let pid  = app.processIdentifier
    let name = app.localizedName ?? "Unknown"

    let appElement = AXUIElementCreateApplication(pid)
    var windowsRef: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(
        appElement,
        kAXWindowsAttribute as CFString,
        &windowsRef
    )

    axLogger.info("╔══ AX REPORT: \(name) (PID \(pid)) ══")
    axLogger.info("║  AX call result: \(result.rawValue) (\(result == .success ? "success" : "FAILED"))")

    guard result == .success else {
        if result.rawValue == -25212 {
            axLogger.warning("║  → Attribute unsupported (app may not expose AX windows)")
        } else if result.rawValue == -25200 {
            axLogger.warning("║  → cannotComplete — likely no Accessibility permission")
        } else {
            axLogger.warning("║  → AX error \(result.rawValue)")
        }
        axLogger.info("╚══")
        return
    }

    guard let windows = windowsRef as? [AXUIElement] else {
        axLogger.warning("║  Cast to [AXUIElement] failed — no windows or unexpected type")
        axLogger.info("╚══")
        return
    }

    axLogger.info("║  Total AX window elements: \(windows.count)")

    for (index, window) in windows.enumerated() {

        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
        let title = (titleRef as? String) ?? "(no title)"

        var subroleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef)
        let subrole = (subroleRef as? String) ?? "(no subrole)"

        let minimized = isMinimized(window)
        let real      = isRealWindow(window)

        axLogger.debug("║  [\(index)] \"\(title)\" subrole=\(subrole) minimized=\(minimized) real=\(real)")
    }

    axLogger.info("║  ► VISIBLE COUNT: \(visibleWindowCount(for: pid))")
    axLogger.info("║  ► APP HIDDEN:    \(isApplicationHidden(pid: pid))")
    axLogger.info("╚══")
}
