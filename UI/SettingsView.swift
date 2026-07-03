import SwiftUI

// MARK: - SettingsPage

enum SettingsPage: String, Hashable, CaseIterable {
    case general   = "General"
    case apps      = "Apps"
    case whitelist = "Whitelist"

    var systemImage: String {
        switch self {
        case .general:   return "gear"
        case .apps:      return "square.grid.2x2"
        case .whitelist: return "hand.raised"
        }
    }

    var iconColor: Color {
        switch self {
        case .general:   return .indigo
        case .apps:      return .blue
        case .whitelist: return .orange
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var selection: SettingsPage? = .general
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(SettingsPage.allCases, id: \.self, selection: $selection) { page in
                SidebarRow(page: page)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 175, max: 210)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                // "Settings" heading that mirrors the screenshot
                Text("Settings")
                    .font(.system(size: 19, weight: .semibold))
                    .padding(.top, 14)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)

                contentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 600, idealWidth: 700, minHeight: 620, idealHeight: 680)
    }

    @ViewBuilder
    private var contentView: some View {
        switch selection ?? .general {
        case .general:   GeneralTab()
        case .apps:      AppsTab()
        case .whitelist: WhitelistTab()
        }
    }
}

// MARK: - SidebarRow

private struct SidebarRow: View {
    let page: SettingsPage

    var body: some View {
        Label {
            Text(page.rawValue)
        } icon: {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(page.iconColor)
                    .frame(width: 24, height: 24)
                Image(systemName: page.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.vertical, 1)
    }
}
