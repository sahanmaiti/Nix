// The dependency container for the entire Nix application.

import SwiftUI
import Combine
import OSLog

@MainActor  // All updates to @Published properties happen on main thread
final class AppEnvironment: ObservableObject {

    // ──────────────────────────────────────────────────
    // MARK: - PUBLISHED STATE
    // SwiftUI redraws when these change
    // ──────────────────────────────────────────────────

    @Published var isEnabled: Bool = true {
            didSet {
                quitEngine.isEnabled = isEnabled
                GlobalSettings.shared.isEnabled = isEnabled
                logger.info("isEnabled \(self.isEnabled)")
            }
        }
        @Published var isPaused: Bool = false {
            didSet {
                quitEngine.isPaused = isPaused
                logger.info("isPaused \(self.isPaused)")
            }
        }

    // ──────────────────────────────────────────────────
    // MARK: - SERVICES
    // AppEnvironment OWNS these. They live as long as the app does.
    // ──────────────────────────────────────────────────

    let accessibilityManager: AccessibilityManager
    let windowMonitor: WindowMonitor
    let appTracker: AppTracker
    let quitEngine: QuitEngine
    let ruleStore: RuleStore
    
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
        self.ruleStore = store
        
        self.quitEngine = QuitEngine(ruleStore: store)
        
        self.windowMonitor = WindowMonitor()
        
        self.appTracker = AppTracker(windowMonitor: windowMonitor)
        
        // --- 2: Load persisted settings into engine (startup sync) ---------------------
            syncSettingsToEngine()

        // --- 3. Wire the detection → decision pipeline ----------------------
        /// WindowMonitor fires → QuitEngine decides
            windowMonitor.onZeroWindows = { [weak quitEngine] app in
                quitEngine?.evaluate(app: app)
            }

        /// WindowMonitor sees new window → cancel any pending quit
            windowMonitor.onWindowAppeared = { [weak quitEngine] pid in
                quitEngine?.cancelPendingQuit(for: pid)
            }

        // --- 4. Forward child changes to AppEnvironment ------------------
            appTracker.objectWillChange
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)

            accessibilityManager.objectWillChange
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)

        // --- 5: Observe GlobalSettings for runtime changes ----------------
                GlobalSettings.shared.objectWillChange
                    .sink { [weak self] _ in
                        DispatchQueue.main.async {
                            self?.syncSettingsToEngine()
                        }
                    }
                    .store(in: &cancellables)
        
            logger.info("AppEnvironment initialised — all services wired")
        }

        // ----------------------------------------
        // MARK: - Settings Sync
        // ----------------------------------------

        private func syncSettingsToEngine() {
            let settings = GlobalSettings.shared

            quitEngine.defaultBehavior          = settings.defaultBehavior
            quitEngine.globalGracePeriodSeconds = settings.gracePeriodSeconds

            logger.debug("Engine synced: behavior=\(settings.defaultBehaviorRaw), grace=\(settings.gracePeriodSeconds)s")
        }
    
    // ──────────────────────────────────────────────────
    // MARK: - ACTIONS
    // User-facing operations that modify state.
    // ──────────────────────────────────────────────────

    func toggleEnabled() {
        isEnabled.toggle()
    }

    func pause(minutes: Int) {
        isPaused = true
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(minutes * 60)) { [weak self] in
            self?.isPaused = false
        }
    }

    func resume() {
        isPaused = false
    }
}
