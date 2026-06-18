import AppKit
import ApplicationServices
import os.log
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {

    private let logger = Logger(subsystem: "com.sahan.Nix", category: "AppDelegate")

    private var onboardingWindow: NSWindow?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NotificationService.requestAuthorization()
        logger.info("Nix launched. AX permission: \(AXIsProcessTrusted())")

        // ── Onboarding ──────────────────────────────────────────────────────
        if !UserDefaults.standard.bool(forKey: "nix.onboardingComplete") {
            showOnboarding()
        }

        // ── Verification Suite (debug only) ─────────────────────────────────
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            Task { @MainActor in
                runAllVerifications()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("Nix is shutting down — cleaning up")
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        logger.debug("Nix became active — checking AX permission")
        AppEnvironment.shared.accessibilityManager.checkPermission()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Onboarding Window
    // ─────────────────────────────────────────────────────────────────────────

    private func showOnboarding() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 520, height: 440)),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Welcome to Nix"
        window.center()

        window.isReleasedWhenClosed = false

        window.titlebarAppearsTransparent = true

        let rootView = OnboardingView { [weak self] in
            window.close()           // dismiss the window
            self?.onboardingWindow = nil  // release our strong reference → ARC deallocates
            self?.logger.info("Onboarding completed — window closed")
        }
        .environmentObject(AppEnvironment.shared)
        window.contentView = NSHostingView(rootView: rootView)

        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)

        onboardingWindow = window

        logger.info("Onboarding window shown (first launch)")
    }
}
