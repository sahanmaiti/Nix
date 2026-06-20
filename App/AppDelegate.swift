import AppKit
import ApplicationServices
import os.log
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {

    private let logger = Logger(subsystem: "com.sahan.Nix", category: "AppDelegate")

    private var onboardingWindow: NSWindow?
    private var paywallWindow: NSWindow?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NotificationService.requestAuthorization()
        logger.info("Nix launched. AX permission: \(AXIsProcessTrusted())")

        // ── Onboarding ──────────────────────────────────────────────────────
        if !UserDefaults.standard.bool(forKey: "nix.onboardingComplete") {
            showOnboarding()
        } else {
            checkPaywallGate()
        }

        // ── License re-validation (catches refunds/chargebacks since last launch)
        Task { @MainActor in
            await LicenseManager.shared.validateStoredLicense()
            checkPaywallGate()
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
        TrialManager.shared.refresh()
        checkPaywallGate()
    }

    /// Fallback path for the license activation redirect — covers cases where
    /// the URL is opened outside the embedded checkout (e.g. an email link,
    /// or WKWebView interception failing for some reason). The primary path
    /// is CheckoutWebView.Coordinator intercepting this before it ever reaches here.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "nix", url.host == "activate" else { continue }
            guard let key = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "key" })?.value else { continue }

            logger.info("Received license activation via external URL open")
            Task { @MainActor in
                let success = await LicenseManager.shared.activate(licenseKey: key)
                if success {
                    self.paywallWindow?.close()
                    self.paywallWindow = nil
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Onboarding Window
    // ─────────────────────────────────────────────────────────────────────────

    private func showOnboarding() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 520, height: 460)),
            styleMask: [
                .titled,
                .closable,
                .fullSizeContentView,   // Content extends under the titlebar area
            ],
            backing: .buffered,
            defer: false
        )

        // Hide the "Welcome to Nix" title text — we show our own header in SwiftUI
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true

        // Allow the user to drag the window by clicking anywhere in the content
        window.isMovableByWindowBackground = true

        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear

        // Center before showing
        window.center()

        let rootView = OnboardingView { [weak self, weak window] in
            window?.close()
            self?.onboardingWindow = nil
            self?.logger.info("Onboarding completed — window closed")
            self?.checkPaywallGate()
        }
        .environmentObject(AppEnvironment.shared)

        window.contentView = NSHostingView(rootView: rootView)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        onboardingWindow = window

        logger.info("Onboarding window shown (first launch)")
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Paywall Window
    // ─────────────────────────────────────────────────────────────────────────

    @MainActor
    private func checkPaywallGate() {
        guard UserDefaults.standard.bool(forKey: "nix.onboardingComplete") else { return }
        guard onboardingWindow == nil else { return }       // don't stack on top of onboarding
        guard paywallWindow == nil else { return }           // already showing
        guard AppEnvironment.shared.requiresPaywall else { return }
        showPaywall()
    }

    private func showPaywall() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 480, height: 560)),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.center()

        let rootView = PaywallView { [weak self, weak window] in
            window?.close()
            self?.paywallWindow = nil
            self?.logger.info("Paywall dismissed — license activated")
        }
        .environmentObject(AppEnvironment.shared)

        window.contentView = NSHostingView(rootView: rootView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        paywallWindow = window
        logger.info("Paywall window shown — trial expired, no valid license")
    }
}
