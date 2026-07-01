import SwiftUI

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
}

struct SettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var selection: SettingsPage? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, id: \.self, selection: $selection) { page in
                Label(page.rawValue, systemImage: page.systemImage)
                    .padding(.vertical, 2)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 175, max: 210)
        } detail: {
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
