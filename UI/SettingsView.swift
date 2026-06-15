import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            
            // General Tab - global behavior settings
            GeneralTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            // Apps Tab - per-app rule overrides
            PlaceholderTab(title: "Apps", icon: "swuare..grid.2x2", message: "Per-app rules - coming in Day 16")
                .tabItem {
                    Label("Apps", systemImage: "square.grid.2x2")
                }
            // WHITELIST TAB — apps Nix never touches (Day 20)
            PlaceholderTab(title: "Whitelist", icon: "hand.raised", message: "Whitelist editor — coming in Day 20")
                .tabItem {
                    Label("Whitelist", systemImage: "hand.raised")
                }
            }
        .frame(width: 520, height: 400)
    }
}
// MARK: - Placeholder Tab

private struct PlaceholderTab: View {
    let title: String
    let icon: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
