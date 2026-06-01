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

    let appTracker: AppTracker
    let accessibilityManager: AccessibilityManager
    
    // ──────────────────────────────────────────────────
    // MARK: - Private
    // ──────────────────────────────────────────────────

    private var cancellables = Set<AnyCancellable>()
    
    // ──────────────────────────────────────────────────
    // MARK: - SINGLETON
    // ──────────────────────────────────────────────────

    static let shared = AppEnvironment()

    private init() {
        self.accessibilityManager = AccessibilityManager()
        self.appTracker = AppTracker()
        
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
