import AppKit
import ApplicationServices
import os.log
import SwiftUI
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate {
    
    private(set) static var shared: AppDelegate!
    
    private let logger = Logger(subsystem: "com.sahan.Nix", category: "AppDelegate")
    
    private var onboardingWindow: NSWindow?
    private var paywallWindow: NSWindow?
    private var settingsWindow: NSWindow? 
    private var updaterController: SPUStandardUpdaterController?
    
    override init() {
        super.init()
        AppDelegate.shared = self
    }
    
    // MARK: - Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        logger.info("Nix launched. AX permission: \(AXIsProcessTrusted())")
        
#if !DEBUG
updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: nil,
    userDriverDelegate: nil
)
#endif
        
        if !UserDefaults.standard.bool(forKey: "nix.onboardingComplete") {
            showOnboarding()
        } else {
            checkPaywallGate()
        }
        
        Task { @MainActor in
            await LicenseManager.shared.validateStoredLicense()
            checkPaywallGate()
        }
        
#if DEBUG
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            Task { @MainActor in
                runAllVerifications()
            }
        }
#endif
    }
    
    func checkForUpdates() {
        updaterController?.updater.checkForUpdates()
    }
    
    var canCheckForUpdates: Bool {
        updaterController?.updater.canCheckForUpdates ?? false
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        logger.info("Nix is shutting down — cleaning up")
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        logger.debug("Nix became active — checking AX permission")
        AppEnvironment.shared.accessibilityManager.checkPermission()
        TrialManager.shared.refresh()
        checkPaywallGate()
        NotificationService.requestAuthorization()
    }
    
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
    
    // MARK: - Settings Window
    
    func showSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        settingsWindow = nil
        
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 700, height: 680)),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 600, height: 620)
        window.toolbarStyle = .unified

        // Attach an empty toolbar so the sidebar toggle button from SwiftUI's
        // .toolbar modifier has a place to live in the titlebar area.
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar

        window.center()
        
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.settingsWindow = nil
            self?.revertToAccessoryIfNeeded()
        }
        
        let rootView = SettingsView()
            .environmentObject(AppEnvironment.shared)
        
        window.contentView = NSHostingView(rootView: rootView)
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
        logger.info("Settings window shown")
    }
    
    // MARK: - Onboarding Window
    
    private func showOnboarding() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 520, height: 460)),
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
        
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.onboardingWindow = nil
            self?.revertToAccessoryIfNeeded()
        }
        
        let rootView = OnboardingView { [weak self, weak window] in
            window?.close()
            self?.onboardingWindow = nil
            self?.logger.info("Onboarding completed — window closed")
            self?.checkPaywallGate()
            self?.revertToAccessoryIfNeeded()
        }
        .environmentObject(AppEnvironment.shared)
        
        window.contentView = NSHostingView(rootView: rootView)
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
        logger.info("Onboarding window shown (first launch)")
    }
    
    // MARK: - Paywall Window
    
    @MainActor
    private func checkPaywallGate() {
        guard UserDefaults.standard.bool(forKey: "nix.onboardingComplete") else { return }
        guard onboardingWindow == nil else { return }
        guard paywallWindow == nil else { return }
        guard AppEnvironment.shared.requiresPaywall else { return }
        showPaywall()
    }
    
    func showPaywall() {
        if let existing = paywallWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        paywallWindow = nil
        
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 640, height: 620)),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.minSize = NSSize(width: 540, height: 500)
        window.center()
        
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.paywallWindow = nil
            self?.revertToAccessoryIfNeeded()
        }
        
        let rootView = PaywallView { [weak self, weak window] in
            window?.close()
            self?.paywallWindow = nil
            self?.logger.info("Paywall dismissed — license activated")
            self?.revertToAccessoryIfNeeded()
        }
        .environmentObject(AppEnvironment.shared)
        
        window.contentView = NSHostingView(rootView: rootView)
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        paywallWindow = window
        logger.info("Paywall window shown")
    }
    
    // MARK: - Activation Policy Management
    
    func revertToAccessoryIfNeeded() {
        let hasOnboarding = onboardingWindow?.isVisible == true
        let hasPaywall    = paywallWindow?.isVisible == true
        let hasSettings   = settingsWindow?.isVisible == true   // ← direct reference, no string match
        
        if !hasOnboarding && !hasPaywall && !hasSettings {
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
