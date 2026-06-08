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
    // Rule 1: Minimized windows don't count.
    if isMinimized(window) {
            return false
        }
    // Rule 2: Sheets and dialogs don't count as primary windows.
    if isSheetOrDialog(window) {
        return false
    }
    // Passes all checks - this is a real window.
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
    // If the call failed, assume NOT minimized.
    guard result == .success else {
        return false
            }
    guard let isMinimized = minimizedRef as? Bool else {
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
    guard result == .success else {
        return false
    }
    guard let subrole = subroleRef as? String else {
        return false
    }
    let nonWindowSubroles: Set<String> = [
        "AXSheet",          // Save/print dialogs attached to windows
        "AXDialog",         // Modal alert dialogs
        "AXFloatingWindow", // Tool palettes in create apps.
        "AXSystemDialog"    // OS-level dialogs
    ]
    return nonWindowSubroles.contains(subrole)
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
        // Can't determine - assume NOT hidden
        return false
    }
    return hidden
}

// -----------------------------------------------------
// MARK: - Debug Helper
// -----------------------------------------------------
/// Prints a complete diagnostic report for one running app to the console.

func printWindowReport(for app: NSRunningApplication) {
    
    let pid = app.processIdentifier
    let name = app.localizedName ?? "Unknown"
    
    let appElement = AXUIElementCreateApplication(pid)
    
    var windowsRef: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(
        appElement,
        kAXWindowsAttribute as CFString,
        &windowsRef
    )
    print("╔══ AX REPORT: \(name) (PID \(pid)) ══ ")
    print("║  AX call result: \(result.rawValue) (\(result == .success ? "success" : "FAILED"))")
    
    guard result == .success else {
            if result.rawValue == -25212 {
                print("║  → Attribute not supported (app may not expose AX)")
            } else if result.rawValue == -25200 {
                print("║  → cannotComplete — likely no Accessibility permission")
            }
            print("╚══")
            return
        }

        guard let windows = windowsRef as? [AXUIElement] else {
            print("║  Cast to [AXUIElement] failed — no windows or wrong type")
            print("╚══")
            return
        }

        print("║  Total AX window elements: \(windows.count)")

    // Report each window individually
        for (index, window) in windows.enumerated() {

            // Read title
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            let title = (titleRef as? String) ?? "(no title)"

            // Read subrole
            var subroleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef)
            let subrole = (subroleRef as? String) ?? "(no subrole)"

            // Check minimized and real status
            let minimized = isMinimized(window)
            let real = isRealWindow(window)
            
            axLogger.debug("║  [\(index)] \"\(title)\" subrole=\(subrole) minimized=\(minimized) real=\(real)")
        }
               
        axLogger.info("║  ► VISIBLE COUNT: \(visibleWindowCount(for: pid))")
        axLogger.info("║  ► APP HIDDEN:    \(isApplicationHidden(pid: pid))")
        axLogger.info("╚══")
}
