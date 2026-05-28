import AppKit
import os.log

class AppDelegate: NSObject, NSApplicationDelegate {
    
    private let logger = Logger(
    subsystem: "com.sahan.Nix",
     category: "AppDelegate"
    )
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        logger.info("Nix launched successfully")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        print("Nix is shutting down")
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        logger.info("Nix is now active")
    }
}
