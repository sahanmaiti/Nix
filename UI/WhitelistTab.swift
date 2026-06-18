import SwiftUI
import UniformTypeIdentifiers

// ─────────────────────────────────────────────────────────────
// MARK: - WhitelistTab
// ─────────────────────────────────────────────────────────────

struct WhitelistTab: View {

    @EnvironmentObject private var env: AppEnvironment
    @State private var showingAddSheet = false

    private var sortedSystemWhitelist: [String] {
        RuleStore.permanentWhitelist.sorted()
    }

    private var userWhitelistedApps: [AppRule] {
        env.ruleStore.rules.values
            .filter { $0.isWhitelisted }
            .sorted { $0.appName.localizedCompare($1.appName) == .orderedAscending }
    }

    // ── Body ─────────────────────────────────────────────────────

    var body: some View {
        VStack(spacing: 0) {
            list
            Divider()
            footer
        }
    }

    // ── List ─────────────────────────────────────────────────────

    private var list: some View {
        List {
            Section {
                ForEach(sortedSystemWhitelist, id: \.self) { bundleID in
                    SystemWhitelistRow(bundleID: bundleID)
                }
            } header: {
                sectionHeader("System Protected")
            } footer: {
                Text("These apps are never touched by Nix, regardless of your settings.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Section {
                if userWhitelistedApps.isEmpty {
                    emptyUserState
                } else {
                    ForEach(userWhitelistedApps) { rule in
                        UserWhitelistRow(rule: rule) {
                            env.ruleStore.setWhitelisted(
                                false,
                                for: rule.bundleIdentifier,
                                appName: rule.appName
                            )
                        }
                    }
                }
            } header: {
                sectionHeader("My Whitelist")
            } footer: {
                Text("Apps you add here will never be quit by Nix.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .listStyle(.inset)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
    }

    // ── Empty State ───────────────────────────────────────────────

    private var emptyUserState: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "hand.raised")
                    .font(.system(size: 26))
                    .foregroundStyle(.tertiary)
                Text("No apps in your whitelist")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Add an app below to protect it from being quit.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 18)
            Spacer()
        }
    }

    // ── Footer ───────────────────────────────────────────────────

    private var footer: some View {
        HStack {
            Text(userWhitelistedApps.count == 0
                 ? "No protected apps"
                 : "\(userWhitelistedApps.count) protected app\(userWhitelistedApps.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Add App…") {
                showingAddSheet = true
            }
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(.windowBackgroundColor))
        .sheet(isPresented: $showingAddSheet) {
            AddToWhitelistView()
                .environmentObject(env)
        }
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: - SystemWhitelistRow
// ─────────────────────────────────────────────────────────────

private struct SystemWhitelistRow: View {

    let bundleID: String

    private var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    private var appName: String {
        appURL.map { $0.deletingPathExtension().lastPathComponent } ?? bundleID
    }

    private var appIcon: NSImage? {
        appURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    var body: some View {
        HStack(spacing: 10) {
            iconView
            info
            Spacer()
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 1)
    }

    private var iconView: some View {
        Group {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: "app.fill")
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(appName)
                .font(.body)
            Text(bundleID)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: - UserWhitelistRow
// ─────────────────────────────────────────────────────────────

private struct UserWhitelistRow: View {

    let rule: AppRule
    let onRemove: () -> Void

    private var appIcon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleIdentifier) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    var body: some View {
        HStack(spacing: 10) {
            iconView
            info
            Spacer()
            removeButton
        }
        .padding(.vertical, 1)
    }

    private var iconView: some View {
        Group {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: "app.fill")
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(rule.appName)
                .font(.body)
            Text(rule.bundleIdentifier)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.red.opacity(0.75))
        }
        .buttonStyle(.plain)
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: - AddToWhitelistView
// ─────────────────────────────────────────────────────────────

struct AddToWhitelistView: View {

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var searchText   = ""
    @State private var selectedApp: TrackedApp? = nil

    /// Running, non-whitelisted apps — what the picker shows.
    private var availableApps: [TrackedApp] {
        env.appTracker.trackedApps
            .filter { app in
                guard let bundleID = app.bundleIdentifier else { return false }
                return !env.ruleStore.isWhitelisted(bundleID)
            }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            .filter {
                searchText.isEmpty ||
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
    }

    // ── Body ─────────────────────────────────────────────────────

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            Divider()
            appListOrEmpty
            Divider()
            actionBar
        }
        .frame(width: 380, height: 360)
    }

    // ── Header ───────────────────────────────────────────────────

    private var header: some View {
        HStack {
            Text("Add App to Whitelist")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    // ── Search Bar ───────────────────────────────────────────────

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.callout)

            TextField("Search running apps…", text: $searchText)
                .textFieldStyle(.plain)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor))
    }

    // ── App List ─────────────────────────────────────────────────

    @ViewBuilder
    private var appListOrEmpty: some View {
        if availableApps.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: searchText.isEmpty ? "checkmark.circle" : "magnifyingglass")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text(searchText.isEmpty
                     ? "All running apps are already protected"
                     : "No apps match \(searchText)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if searchText.isEmpty {
                    Text("Use Browse to protect an app that isn't currently open.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(availableApps) { app in
                        AppPickerRow(app: app, isSelected: selectedApp?.id == app.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Tap again to deselect
                                selectedApp = (selectedApp?.id == app.id) ? nil : app
                            }

                        if app.id != availableApps.last?.id {
                            Divider().padding(.leading, 46)
                        }
                    }
                }
            }
        }
    }

    // ── Action Bar ───────────────────────────────────────────────

    private var actionBar: some View {
        HStack {
            Button("Browse…") {
                browseForApp()
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.escape)

            Button("Add") {
                addSelected()
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedApp == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // ── Actions ───────────────────────────────────────────────────

    private func addSelected() {
        guard let app = selectedApp, let bundleID = app.bundleIdentifier else { return }
        env.ruleStore.setWhitelisted(true, for: bundleID, appName: app.name)
        dismiss()
    }

    private func browseForApp() {
        let panel = NSOpenPanel()
        panel.title                 = "Choose an Application"
        panel.prompt                = "Add to Whitelist"
        panel.canChooseFiles        = true
        panel.canChooseDirectories  = false
        panel.allowsMultipleSelection = false
        panel.directoryURL          = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes   = [.applicationBundle]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let bundle   = Bundle(url: url)
        let bundleID = bundle?.bundleIdentifier
            ?? url.deletingPathExtension().lastPathComponent
        let appName  = bundle?.infoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle?.infoDictionary?["CFBundleName"] as? String
            ?? url.deletingPathExtension().lastPathComponent

        env.ruleStore.setWhitelisted(true, for: bundleID, appName: appName)
        dismiss()
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: - AppPickerRow
// ─────────────────────────────────────────────────────────────

private struct AppPickerRow: View {

    let app: TrackedApp
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            iconView
            info
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
    }

    private var iconView: some View {
        Group {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: "app.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(app.name)
                .font(.body)
                .lineLimit(1)
            if let bundleID = app.bundleIdentifier {
                Text(bundleID)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }
}
