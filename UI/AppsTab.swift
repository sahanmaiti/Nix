import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - AppsTab
// ─────────────────────────────────────────────────────────────────────────────

struct AppsTab: View {

    @EnvironmentObject private var env: AppEnvironment

    @State private var searchText = ""

    private var filteredApps: [TrackedApp] {
        let sorted = env.appTracker.trackedApps.sorted { $0.name < $1.name }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().opacity(0.5)
            appListOrEmpty
            Divider().opacity(0.5)
            footer
        }
    }

    // ── Search Bar ───────────────────────────────────────────────

    private var searchBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
                .font(.system(size: 13, weight: .medium))

            TextField("Search apps…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.body)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(.textBackgroundColor).opacity(0.6))
    }

    // ── App List ─────────────────────────────────────────────────

    @ViewBuilder
    private var appListOrEmpty: some View {
        if filteredApps.isEmpty {
            emptyState
        } else {
            List(filteredApps) { app in
                AppRuleRow(app: app)
                    .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
            }
            .listStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: searchText.isEmpty ? "tray" : "magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)

            Text(searchText.isEmpty
                 ? "No apps being monitored"
                 : "No apps match \"\(searchText)\"")
                .font(.callout)
                .foregroundStyle(.secondary)

            if searchText.isEmpty {
                Text("Open any app and it will appear here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ── Footer ───────────────────────────────────────────────────

    private var footer: some View {
        HStack {
            Text("\(env.appTracker.trackedApps.count) app\(env.appTracker.trackedApps.count == 1 ? "" : "s") monitored")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(.windowBackgroundColor).opacity(0.5))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - AppRuleRow
// ─────────────────────────────────────────────────────────────────────────────

struct AppRuleRow: View {

    @EnvironmentObject private var env: AppEnvironment

    let app: TrackedApp

    private var defaultLabel: String {
        "Default (\(GlobalSettings.shared.defaultBehavior.displayName))"
    }

    var body: some View {
        HStack(spacing: 10) {
            appIcon
            appInfo
            Spacer()
            behaviorPicker
        }
        .padding(.vertical, 3)
    }

    private var appIcon: some View {
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

    private var appInfo: some View {
        VStack(alignment: .leading, spacing: 1) {
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

    private var behaviorPicker: some View {
        Picker("", selection: behaviorBinding) {
            Text(defaultLabel)
                .tag(Optional<AppBehavior>.none)

            Divider()

            ForEach(AppBehavior.allCases, id: \.self) { behavior in
                Text(behavior.displayName)
                    .tag(Optional(behavior))
            }
        }
        .pickerStyle(.menu)
        .frame(width: 170)
        .labelsHidden()
    }

    private var behaviorBinding: Binding<AppBehavior?> {
        Binding(
            get: {
                guard let bundleID = app.bundleIdentifier else { return nil }
                return env.ruleStore.rule(for: bundleID)?.behavior
            },
            set: { newBehavior in
                guard let bundleID = app.bundleIdentifier else { return }
                if let behavior = newBehavior {
                    env.ruleStore.setBehavior(behavior, for: bundleID, appName: app.name)
                } else {
                    env.ruleStore.removeRule(for: bundleID)
                }
            }
        )
    }
}
