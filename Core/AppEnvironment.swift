import SwiftUI
import Combine

@MainActor
final class AppEnvironment: ObservableObject {
    
    @Published var isEnabled: Bool = true
    @Published var isPaused: Bool = false
    
    static let shared = AppEnvironment()
    private init() { }
    
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
