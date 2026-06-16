// The dependency container for the entire Nix application.

import SwiftUI
import Combine
import OSLog

@MainActor
final class AppEnvironment: ObservableObject {
    
    // ──────────────────────────────────────────────────
    // MARK: - PUBLISHED STATE
    // SwiftUI redraws when these change
    // ──────────────────────────────────────────────────
    
    @Published var isEnabled: Bool = true {
        didSet {
            quitEngine.isEnabled = isEnabled
            GlobalSettings.shared.isEnabled = isEnabled
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
    // AppEnvironment OWNS these. They live as long as the app does.
    // ──────────────────────────────────────────────────
    
    let accessibilityManager: AccessibilityManager
    let windowMonitor:        WindowMonitor
    let appTracker:           AppTracker
    let quitEngine:           QuitEngine
    let ruleStore:            RuleStore

    let settings: GlobalSettings = GlobalSettings.shared
    
    // ──────────────────────────────────────────────────
    // MARK: - Private
    // ──────────────────────────────────────────────────
    
    private var cancellables = Set<AnyCancellable>()
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
        
        // 2. Load persisted settings into engine at startup.
        loadPersistedSettings()

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
        
        // 4. Forward child changes so SwiftUI views that observe AppEnvironment
        //    redraw when appTracker or accessibilityManager publish changes.
        appTracker.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        accessibilityManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        
        // 5. Watch GlobalSettings for runtime changes → sync into engine.
        GlobalSettings.shared.objectWillChange
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncSettingsToEngine() }
            .store(in: &cancellables)
        
        logger.info("AppEnvironment initialised — all services wired")
    }
    
    // ──────────────────────────────────────────────────
    // MARK: - Settings Sync
    // ──────────────────────────────────────────────────
    
    private func loadPersistedSettings() {
        let s = GlobalSettings.shared
        
        quitEngine.isEnabled                = s.isEnabled
        quitEngine.defaultBehavior          = s.defaultBehavior
        quitEngine.globalGracePeriodSeconds = s.gracePeriodSeconds
        
        // Align the @Published property with the persisted value.
        _isEnabled = Published(initialValue: s.isEnabled)
        
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
    
    // ──────────────────────────────────────────────────
    // MARK: - ACTIONS
    // ──────────────────────────────────────────────────
    
    func toggleEnabled() { isEnabled.toggle() }
    
    func pause(minutes: Int) {
        isPaused = true
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(minutes * 60)) { [weak self] in
            self?.isPaused = false
        }
    }
    
    func resume() { isPaused = false }
}
