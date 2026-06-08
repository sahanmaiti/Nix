// Responds to macOS application lifecycle events.

import AppKit
import ApplicationServices
import os.log

class AppDelegate: NSObject, NSApplicationDelegate {
    
    private let logger = Logger(
        subsystem: "com.sahan.Nix",
        category: "AppDelegate"
    )
    
    // MARK: -  LifeCycle Methods
    /// These are CLASS-LEVEL methods. They are direct member of AppDelegate, not nested any other function.
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        //Hides from Dock and App Switcher - makes Nix a background utility
        NSApp.setActivationPolicy(.accessory)
        
        logger.info("Nix launched. AX permission: \(AXIsProcessTrusted())")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            Task { @MainActor in
                runAllVerifications()
            }
        }
        //-----------------------------------------------------------
    }
    func applicationWillTerminate(_ notification: Notification) {
        logger.info("Nix is shutting down = cleaning up")
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        logger.debug("Nix became active - checking AX permission")
        AppEnvironment.shared.accessibilityManager.checkPermission()
    }
}
