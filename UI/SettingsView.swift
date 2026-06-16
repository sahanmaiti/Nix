import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AppsTab()
                .tabItem {
                    Label("Apps", systemImage: "square.grid.2x2")
                }

            PlaceholderTab(
                icon: "hand.raised",
                message: "Whitelist editor — coming soon"
            )
            .tabItem {
                Label("Whitelist", systemImage: "hand.raised")
            }
        }
        .frame(
            minWidth:    480, idealWidth:  520, maxWidth:  .infinity,
            minHeight:   380, idealHeight: 420, maxHeight: .infinity
        )
    }
}

// MARK: - Placeholder Tab

private struct PlaceholderTab: View {
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
