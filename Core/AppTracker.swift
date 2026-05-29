import AppKit
import Combine

// MARK: - AppTracker
// AppTracker is a SERVICE — it runs continuously in the background,
// maintaining a live picture of what apps are running.

@MainActor
final class AppTracker: ObservableObject {

    @Published private(set) var trackedApps: [TrackedApp] = []

    private var cancellables = Set<AnyCancellable>()

    // Apps we will NEVER track or quit.
    
    private let permanentWhitelist: Set<String> = [
        "com.apple.finder",          // Finder must never be quit
        "com.apple.dock",            // The Dock process
        "com.apple.SystemUIServer",  // Menu bar system processes
        "com.apple.NotificationCenter"
    ]

    init() {
        setupWorkspaceObservers()   // Start listening for future events
        loadCurrentlyRunningApps()  // Handle apps already running
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
    }

    // Load apps that were already running before Nix launched.
    // Without this, Nix would be "blind" to everything open at startup.
    private func loadCurrentlyRunningApps() {
        NSWorkspace.shared.runningApplications
            .filter { shouldTrack($0) }
            .forEach { appDidLaunch($0) }
    }

    // MARK: - Event Handlers

    private func appDidLaunch(_ app: NSRunningApplication) {
        // Defensive guard: never add duplicates.
        guard !trackedApps.contains(where: { $0.pid == app.processIdentifier }) else {
            return
        }

        let tracked = TrackedApp(runningApp: app)
        trackedApps.append(tracked)
        print("📱 Now tracking: \(tracked.name) (PID: \(tracked.pid))")
    }

    private func appDidTerminate(_ app: NSRunningApplication) {
        trackedApps.removeAll { $0.pid == app.processIdentifier }
        print("💀 Stopped tracking: \(app.localizedName ?? "unknown")")
    }

    private func appDidHide(_ app: NSRunningApplication) {

        if let index = trackedApps.firstIndex(where: { $0.pid == app.processIdentifier }) {
            trackedApps[index].isHidden = true
            print("👁 Hidden: \(trackedApps[index].name)")
        }
    }

    private func appDidUnhide(_ app: NSRunningApplication) {
        if let index = trackedApps.firstIndex(where: { $0.pid == app.processIdentifier }) {
            trackedApps[index].isHidden = false
            print("👁 Unhidden: \(trackedApps[index].name)")
        }
    }

    // MARK: - Filter Logic

    private func shouldTrack(_ app: NSRunningApplication) -> Bool {
        // Rule 1: Only track regular apps (those that appear in the Dock)
        guard app.activationPolicy == .regular else { return false }

        // Rule 2: Never track whitelisted system apps
        if let bundleID = app.bundleIdentifier,
           permanentWhitelist.contains(bundleID) {
            return false
        }

        return true
    }
}

// MARK: - TrackedApp Model

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
