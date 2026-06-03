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
                logger.info("isEnabled changed to \(self.isEnabled)")
            }
        }
        @Published var isPaused: Bool = false {
            didSet {
                quitEngine.isPaused = isPaused
                logger.info("isPaused changed to \(self.isPaused)")
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
        self.quitEngine = QuitEngine()
        self.windowMonitor = WindowMonitor()
        self.appTracker = AppTracker(windowMonitor: windowMonitor)
        
        // 2. Wire the detection → decision pipeline

        windowMonitor.onZeroWindows = { [weak quitEngine] app in
            quitEngine?.evaluate(app: app)
        }
        windowMonitor.onWindowAppeared = { [weak quitEngine] pid in
            quitEngine?.cancelPendingQuit(for: pid)
        }

        // 3. Sync initial engine state
                
        quitEngine.isEnabled = isEnabled
        quitEngine.isPaused = isPaused

        // 4. Forward child object changes to AppEnvironment
                
        appTracker.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        accessibilityManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        logger.info("AppEnvironment initialized — all services wired")
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
