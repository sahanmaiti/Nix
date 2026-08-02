import SwiftUI
import Combine
import OSLog

@MainActor
final class AppEnvironment: ObservableObject {
    
    // ──────────────────────────────────────────────────
    // MARK: - PUBLISHED STATE
    /// SwiftUI redraws when these change
    // ──────────────────────────────────────────────────
    
    @Published var isEnabled: Bool = true {
        didSet {
            GlobalSettings.shared.isEnabled = isEnabled
            updateEngineEnabledState()
            logger.info("isEnabled → \(self.isEnabled)")
        }
    }
    @Published var isPaused: Bool = false {
        didSet {
            quitEngine.isPaused = isPaused
            logger.info("isPaused → \(self.isPaused)")
        }
    }
    
    // ──────────────────────────────────────────────────
    // MARK: - SERVICES
    /// AppEnvironment OWNS these. They live as long as the app does.
    // ──────────────────────────────────────────────────
    
    let accessibilityManager: AccessibilityManager
    let windowMonitor:        WindowMonitor
    let appTracker:           AppTracker
    let quitEngine:           QuitEngine
    let ruleStore:            RuleStore

    let settings:       GlobalSettings = GlobalSettings.shared
    let licenseManager: LicenseManager = LicenseManager.shared
    let trialManager:   TrialManager   = TrialManager.shared

    var requiresPaywall: Bool {
        trialManager.isExpired && !licenseManager.isLicensed
    }
    
    // ──────────────────────────────────────────────────
    // MARK: - Private
    // ──────────────────────────────────────────────────
    
    private var cancellables = Set<AnyCancellable>()
    private var pauseTimer: DispatchWorkItem?
    private let logger = Logger(subsystem: "com.sahan.Nix", category: "AppEnvironment")
    
    // ──────────────────────────────────────────────────
    // MARK: - SINGLETON
    // ──────────────────────────────────────────────────
    
    static let shared = AppEnvironment()
    
    private init() {
        // 1. Create services in dependency order.
        self.accessibilityManager = AccessibilityManager()
        
        let store = RuleStore()
        self.ruleStore  = store
        self.quitEngine = QuitEngine(ruleStore: store)
        self.windowMonitor = WindowMonitor()
        self.appTracker    = AppTracker(windowMonitor: windowMonitor)
        
        // 2. Load persisted settings into the engine at startup.
        loadPersistedSettings()
        
        // 2a. Reconcile the launch-at-login toggle with actual system state.
        LoginItemService.syncWithSystemState()

        // 3. Wire the detection → decision pipeline.
        windowMonitor.onZeroWindows = { [weak quitEngine] app in
            quitEngine?.evaluate(app: app)
        }
        windowMonitor.onWindowAppeared = { [weak quitEngine] pid in
            quitEngine?.cancelPendingQuit(for: pid)
        }
        appTracker.onCancelPendingQuit = { [weak quitEngine] pid in
            quitEngine?.cancelPendingQuit(for: pid)
        }
        appTracker.onAppDidTerminate = { [weak quitEngine] pid in
            quitEngine?.confirmedTermination(pid: pid)
        }
        
        // 4. Forward child changes so SwiftUI views that observe AppEnvironment
        appTracker.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        accessibilityManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        ruleStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        accessibilityManager.$isGranted
            .removeDuplicates()
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let running = NSWorkspace.shared.runningApplications
                for tracked in appTracker.trackedApps {
                    guard let app = running.first(where: { $0.processIdentifier == tracked.pid }) else { continue }
                    windowMonitor.startMonitoring(app: app)
                    windowMonitor.refreshRegistrations(for: tracked.pid)
                }
                logger.info("AX permission granted — retried startMonitoring for \(appTracker.trackedApps.count) app(s)")
            }
            .store(in: &cancellables)
        
        licenseManager.objectWillChange
            .sink { [weak self] _ in
                self?.updateEngineEnabledState()
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        trialManager.objectWillChange
            .sink { [weak self] _ in
                self?.updateEngineEnabledState()
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        // 5. Watch GlobalSettings for runtime changes → sync into engine.
        GlobalSettings.shared.objectWillChange
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncSettingsToEngine() }
            .store(in: &cancellables)

        // 6. Apply initial gate state (covers the case where the trial has
        //    already expired by the time AppEnvironment is first constructed).
        updateEngineEnabledState()
        
        logger.info("AppEnvironment initialised — all services wired")
    }
    
    // ──────────────────────────────────────────────────
    // MARK: - Settings Sync
    // ──────────────────────────────────────────────────
    
    private func loadPersistedSettings() {
        let s = GlobalSettings.shared
        
        quitEngine.defaultBehavior          = s.defaultBehavior
        quitEngine.globalGracePeriodSeconds = s.gracePeriodSeconds
        
        isEnabled = s.isEnabled
        
        logger.info("""
            Startup settings loaded: \
            isEnabled=\(s.isEnabled), \
            behavior=\(s.defaultBehaviorRaw), \
            grace=\(s.gracePeriodSeconds)s
            """)
    }
    
    private func syncSettingsToEngine() {
        let s = GlobalSettings.shared
        quitEngine.defaultBehavior          = s.defaultBehavior
        quitEngine.globalGracePeriodSeconds = s.gracePeriodSeconds
        
        logger.debug("""
            Engine synced (runtime): \
            behavior=\(s.defaultBehaviorRaw), \
            grace=\(s.gracePeriodSeconds)s
            """)
    }

    private func updateEngineEnabledState() {
        #if DEBUG
        quitEngine.isEnabled = isEnabled
        #else
        quitEngine.isEnabled = isEnabled && !requiresPaywall
        #endif
        if requiresPaywall {
            logger.info("Engine gated — trial expired, no valid license")
        }
    }
    
    // ──────────────────────────────────────────────────
    // MARK: - ACTIONS
    // ──────────────────────────────────────────────────
    
    func toggleEnabled() { isEnabled.toggle() }
    
    func pause(minutes: Int) {
        pauseTimer?.cancel()
        isPaused = true
        let item = DispatchWorkItem { [weak self] in self?.isPaused = false }
        pauseTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(minutes * 60), execute: item)
    }
    
    func resume() {
        pauseTimer?.cancel()
        pauseTimer = nil
        isPaused = false
    }
}
