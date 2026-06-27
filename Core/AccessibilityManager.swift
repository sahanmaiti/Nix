import ApplicationServices
import AppKit
import Combine
import os.log

@MainActor
final class AccessibilityManager: ObservableObject {
    
    @Published private(set) var isGranted: Bool = false
    
    private var pollTimer: Timer?
    
    private let logger = Logger(subsystem: "com.sahan.Nix", category: "AccessibilityManager")
    
    // MARK: - LifeCycle
    
    init() {
        // Check immediately on creation - don't wait 1 second for the first call
        checkPermission()
        // Start the 1-second polling loop
        startPolling()
        logger.info("AccessibilityManager initialized. Permission granted: \(self.isGranted)")
    }
    
    deinit {
        pollTimer?.invalidate()
        logger.info("AccessibilityManager deallocated. Timer invalidated.")
    }
    
    // MARK: - Permission Check
    
    var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }
    func checkPermission() {
        let newValue = AXIsProcessTrusted()
        
        //OPTIMIZATION: Only update ( and trigger SwiftUI redraw) if the value changed.
        if self.isGranted != newValue {
            self.isGranted = newValue
            self.logger.info("Permission state changed -> \(newValue)")
        }
    }
    
    // MARK: - Permission Request
    
    // Opens System Settings to the Accessibility page AND shows a system prompt asking the user to grant permission.
    
    func requestPermission() {
        let options: CFDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true as CFBoolean
            ] as CFDictionary
        
        let _ = AXIsProcessTrustedWithOptions(options)
        
        logger.info("Permission request triggered - System Settings opened.")
    }
    
    // MARK: - Called From AppDelegate
    
    // AppDelegate will call thes when the app becomes active.
    
    func checkOnActivation() {
        checkPermission()
        logger.debug("Permission check in app activation")
    }
    
    // MARK: - Private Polling Loop
    
    private func startPolling() {
        
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkPermission()
            }
        }
        logger.debug( "Permission polling started ( 1s interval)")
    }
}
