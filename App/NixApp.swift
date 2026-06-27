import SwiftUI

@main
struct NixApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var env = AppEnvironment.shared

    var body: some Scene {
        MenuBarExtra("Nix", systemImage: menuBarIcon) {
            MenuBarView()
                .environmentObject(env)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIcon: String {
        if env.isPaused { return "pause.circle" }
        if !env.isEnabled { return "circle.slash" }
        return "xmark.circle"
    }
}
