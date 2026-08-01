import AppKit
import Combine
import os.log
// MARK: - AppTracker

@MainActor
final class AppTracker: ObservableObject {

    @Published private(set) var trackedApps: [TrackedApp] = []

    private var cancellables = Set<AnyCancellable>()
    private var permanentWhitelist: Set<String> { RuleStore.permanentWhitelist }

    // MARK: - Cancel Callback
    var onCancelPendingQuit: ((pid_t) -> Void)?

    // MARK: - Dependencies

    private let windowMonitor: WindowMonitor
    private let logger = Logger(subsystem: "com.sahan.Nix", category: "AppTracker")

    // MARK: - Init

    init(windowMonitor: WindowMonitor) {
        self.windowMonitor = windowMonitor
        setupWorkspaceObservers()
        loadCurrentlyRunningApps()
    }

    // MARK: - Setup

    private func setupWorkspaceObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        
        // --- App Launched ---
        nc.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .filter { [weak self] app in self?.shouldTrack(app) ?? false }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] app in self?.appDidLaunch(app) }
            .store(in: &cancellables)
        
        // --- App Terminated ---
        nc.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] app in self?.appDidTerminate(app) }
            .store(in: &cancellables)
        
        // --- App Hidden (Cmd+H) ---
        nc.publisher(for: NSWorkspace.didHideApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] app in self?.appDidHide(app) }
            .store(in: &cancellables)
        
        // --- App Unhidden ---
        nc.publisher(for: NSWorkspace.didUnhideApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] app in self?.appDidUnhide(app) }
            .store(in: &cancellables)
        
        // --- App Activated ---
        
        nc.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] app in self?.appDidActivate(app) }
            .store(in: &cancellables)
        
        // --- App Deactivated (fallback for window-close detection) ---
        nc.publisher(for: NSWorkspace.didDeactivateApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] app in self?.appDidDeactivate(app) }
            .store(in: &cancellables)
    }
    
    private func loadCurrentlyRunningApps() {
        NSWorkspace.shared.runningApplications
            .filter { shouldTrack($0) }
            .forEach { appDidLaunch($0) }
    }

    // MARK: - Event Handlers

    private func appDidLaunch(_ app: NSRunningApplication) {
        guard !trackedApps.contains(where: { $0.pid == app.processIdentifier }) else { return }

        let tracked = TrackedApp(runningApp: app)
        trackedApps.append(tracked)
        windowMonitor.startMonitoring(app: app)
        logger.info("📱 Tracking + monitoring: \(tracked.name) (PID: \(tracked.pid))")
    }

    private func appDidTerminate(_ app: NSRunningApplication) {
        trackedApps.removeAll { $0.pid == app.processIdentifier }
        windowMonitor.stopMonitoring(app: app)
        logger.info("💀 Stopped tracking: \(app.localizedName ?? "unknown")")
    }

    private func appDidHide(_ app: NSRunningApplication) {
        if let index = trackedApps.firstIndex(where: { $0.pid == app.processIdentifier }) {
            trackedApps[index].isHidden = true
        }
        logger.debug("👁 App hidden: \(app.localizedName ?? "?")")
    }

    private func appDidUnhide(_ app: NSRunningApplication) {
        if let index = trackedApps.firstIndex(where: { $0.pid == app.processIdentifier }) {
            trackedApps[index].isHidden = false
        }
        guard trackedApps.contains(where: { $0.pid == app.processIdentifier }) else { return }
        logger.debug("👁 App unhidden: \(app.localizedName ?? "?") — cancelling any pending quit")
        onCancelPendingQuit?(app.processIdentifier)
    }
    
    private func appDidDeactivate(_ app: NSRunningApplication) {
        guard trackedApps.contains(where: { $0.pid == app.processIdentifier }) else { return }
        logger.debug("👁 App deactivated: \(app.localizedName ?? "?") — fallback window check")
        windowMonitor.checkOnDeactivation(for: app.processIdentifier)
    }

    // MARK: - Activation handler
    private func appDidActivate(_ app: NSRunningApplication) {
        guard trackedApps.contains(where: { $0.pid == app.processIdentifier }) else { return }
        logger.debug("▶️ App activated: \(app.localizedName ?? "?") — cancelling any pending quit")
        onCancelPendingQuit?(app.processIdentifier)

        // Reliable, non-AX signal that always fires before a user could close this app's last
        // window — including apps already running on a background Space at Nix launch, whose
        // windows never trigger an AX-level retry.
        windowMonitor.refreshRegistrations(for: app.processIdentifier)
    }
    

    // MARK: - Filter Logic

    private func shouldTrack(_ app: NSRunningApplication) -> Bool {
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return false
        }
        guard app.activationPolicy == .regular else { return false }
        if let bundleID = app.bundleIdentifier,
           permanentWhitelist.contains(bundleID) {
            return false
        }
        return true
    }
}

// MARK: - TrackedApp Model (unchanged)

struct TrackedApp: Identifiable {
    var id: pid_t { pid }
    let pid: pid_t
    let bundleIdentifier: String?
    let name: String
    let icon: NSImage?
    var isHidden: Bool

    init(runningApp: NSRunningApplication) {
        self.pid = runningApp.processIdentifier
        self.bundleIdentifier = runningApp.bundleIdentifier
        self.name = runningApp.localizedName ?? "Unknown App"
        self.icon = runningApp.icon
        self.isHidden = runningApp.isHidden
    }
}
