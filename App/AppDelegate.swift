import AppKit
import os.log

class AppDelegate: NSObject, NSApplicationDelegate {
    
    private let logger = Logger(
        subsystem: "com.sahan.Nix",
        category: "AppDelegate"
    )
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        logger.info("Nix launched. AX permission: \(AXIsProcessTrusted())")
        
        // ── TEMPORARY TEST — Day 6 only ──────────────────────────
        // Wait 2 seconds after launch, then print AX reports for all
        // currently running regular apps. Watch Console.app to see the output.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            print("\n🔍 Running AX diagnostic on all apps...\n")
            
            let regularApps = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
            
            for app in regularApps {
                printWindowReport(for: app)
            }
            
            print("\n✅ AX diagnostic complete.\n")
        }
        
        func applicationWillTerminate(_ notification: Notification) {
            print("Nix is shutting down")
        }
        
        func applicationDidBecomeActive(_ notification: Notification) {
            logger.info("Nix is now active")
            
            AppEnvironment.shared.accessibilityManager.checkOnActivation()
        }
    }
}
