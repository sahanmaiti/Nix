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
        
        // ── TEMPORARY TEST — Day 6 only ──────────────────────────
        // Wait 2 seconds after launch, then print AX reports for all
        // currently running regular apps. Watch Console.app to see the output.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.runAXDiagnostic()
        }
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
    
    // MARK: - Private Helpers
    
    private func runAXDiagnostic() {
            print("\n Running AX diagnostic on all running apps...\n")

            let regularApps = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }

            for app in regularApps {
                printWindowReport(for: app)
            }

            print("\n AX diagnostic complete — \(regularApps.count) apps checked.\n")
        }
    }
