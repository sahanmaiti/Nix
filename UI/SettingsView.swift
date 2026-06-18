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

            WhitelistTab()
                .tabItem {
                    Label("Whitelist", systemImage: "hand.raised")
                }
        }
        .frame(
                    minWidth:    480, idealWidth:  520, maxWidth:  .infinity,
                    minHeight:   380, idealHeight: 420, maxHeight: .infinity
                )
                .glassWindow()
    }
}
