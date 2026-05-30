

import SwiftUI
import Combine

@MainActor  // All updates to @Published properties happen on main thread
final class AppEnvironment: ObservableObject {

    // ──────────────────────────────────────────────────
    // PUBLISHED STATE — UI redraws when these change
    // ──────────────────────────────────────────────────

    @Published var isEnabled: Bool = true
    @Published var isPaused: Bool = false

    // ──────────────────────────────────────────────────
    // SERVICES — owned and initialized here
    // ──────────────────────────────────────────────────

    let appTracker: AppTracker
    let accessibilityManager: AccessibilityManager

    private var cancellables = Set<AnyCancellable>()
    
    // ──────────────────────────────────────────────────
    // SINGLETON
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
    // ACTIONS
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
