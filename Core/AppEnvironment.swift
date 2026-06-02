// The dependency container for the entire Nix application.

import SwiftUI
import Combine

@MainActor  // All updates to @Published properties happen on main thread
final class AppEnvironment: ObservableObject {

    // ──────────────────────────────────────────────────
    // MARK: - PUBLISHED STATE
    // SwiftUI redraws when these change
    // ──────────────────────────────────────────────────

    @Published var isEnabled: Bool = true
    @Published var isPaused: Bool = false

    // ──────────────────────────────────────────────────
    // MARK: - SERVICES
    // AppEnvironment OWNS these. They live as long as the app does.
    // ──────────────────────────────────────────────────

    let accessibilityManager: AccessibilityManager
    let windowMonitor: WindowMonitor
    let appTracker: AppTracker
    
    // ──────────────────────────────────────────────────
    // MARK: - Private
    // ──────────────────────────────────────────────────

    private var cancellables = Set<AnyCancellable>()
    
    // ──────────────────────────────────────────────────
    // MARK: - SINGLETON
    // ──────────────────────────────────────────────────

    static let shared = AppEnvironment()

    private init() {
        // 1. Create services in dependenct order.
        self.accessibilityManager = AccessibilityManager()
        self.windowMonitor = WindowMonitor()
        self.appTracker = AppTracker(windowMonitor: windowMonitor)
        
        // 2. Wire the WindowMonitor -> QuitEngine pipeline
        windowMonitor.onZeroWindows = { [weak self] app in
            guard let self = self else { return }
            guard self.isEnabled && !self.isPaused else {
                print("⏸ Engine disabled/paused — would have quit \(app.localizedName ?? "?")")
                return
            }
            print("🔴 WOULD QUIT: \(app.localizedName ?? "?") (PID \(app.processIdentifier))")
        }
        windowMonitor.onWindowAppeared = { pid in
                    print("✅ Window re-appeared for PID \(pid) — would cancel pending quit")
                }
        
        // 3. Forward child object changes to AppEnviroment's publisher
        appTracker.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        accessibilityManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
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
