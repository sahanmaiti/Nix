import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - MenuBarView
// ─────────────────────────────────────────────────────────────────────────────

struct MenuBarView: View {

    @EnvironmentObject var env: AppEnvironment
    @Environment(\.openWindow) var openWindow

    var body: some View {
        VStack(spacing: 0) {

            if !env.accessibilityManager.isGranted {
                accessibilityWarning
                Divider().opacity(0.5)
            }

            header

            if !env.appTracker.trackedApps.isEmpty {
                Divider().opacity(0.4)
                appList
            }

            Divider().opacity(0.4)
            controlRows
            versionFooter
        }
        .frame(width: 280)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Accessibility Warning
    // ─────────────────────────────────────────────────────────────────────────

    private var accessibilityWarning: some View {
        Button { env.accessibilityManager.requestPermission() } label: {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 13, weight: .medium))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Accessibility Required")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Tap to open Privacy & Security")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.orange.opacity(0.08))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Header
    // ─────────────────────────────────────────────────────────────────────────

    private var header: some View {
        HStack(spacing: 10) {
            Image("NixIcon")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 5.5, style: .continuous))
                .opacity(env.isEnabled && !env.isPaused ? 1.0 : 0.45)
                .animation(.easeInOut(duration: 0.2), value: env.isEnabled)
                .animation(.easeInOut(duration: 0.2), value: env.isPaused)

            VStack(alignment: .leading, spacing: 1) {
                Text("Nix")
                    .font(.system(size: 13, weight: .bold))
                Text(headerStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .animation(.easeInOut(duration: 0.15), value: headerStatus)
            }

            Spacer()

            Toggle("", isOn: $env.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .disabled(env.isPaused)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var headerStatus: String {
        if env.isPaused   { return "Monitoring paused" }
        if !env.isEnabled { return "Monitoring disabled" }
        let n = env.appTracker.trackedApps.count
        return n == 0 ? "No apps open" : "Watching \(n) app\(n == 1 ? "" : "s")"
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - App List
    // ─────────────────────────────────────────────────────────────────────────

    private var appList: some View {
        buildAppList(env.appTracker.trackedApps.sorted { $0.name < $1.name })
    }

    private func buildAppList(_ apps: [TrackedApp]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(apps.prefix(5))) { app in
                HStack(spacing: 9) {
                    Group {
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "app.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(width: 16, height: 16)
                        }
                    }

                    Text(app.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer()

                    Circle()
                        .fill(app.isHidden ? Color.orange : Color.green)
                        .frame(width: 6, height: 6)
                        .opacity(env.isPaused ? 0.3 : 0.85)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
            }

            if apps.count > 5 {
                Text("and \(apps.count - 5) more…")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 1)
                    .padding(.bottom, 3)
            }
        }
        .padding(.vertical, 5)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Control Rows
    // ─────────────────────────────────────────────────────────────────────────

    private var controlRows: some View {
        VStack(spacing: 0) {
            if env.isPaused {
                MenuRow(icon: "play.circle", label: "Resume Monitoring") {
                    env.resume()
                }
            } else {
                MenuRow(icon: "pause.circle", label: "Pause for 30 Minutes") {
                    env.pause(minutes: 30)
                }
                MenuRow(icon: "pause.circle", label: "Pause for 2 Hours") {
                    env.pause(minutes: 120)
                }
            }

            Divider().padding(.horizontal, 4).opacity(0.4)

            MenuRow(icon: "gear", label: "Settings…", action: openSettings)
            MenuRow(icon: "power", label: "Quit Nix") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 4)
    }

    private func openSettings() {
        openWindow(id: "settings")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.title == "Settings" })?.makeKeyAndOrderFront(nil)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Version Footer
    // ─────────────────────────────────────────────────────────────────────────

    private var versionFooter: some View {
        Text("Nix · v1.0")
            .font(.system(size: 10))
            .foregroundStyle(Color(.quaternaryLabelColor))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 5)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - MenuRow
// ─────────────────────────────────────────────────────────────────────────────

private struct MenuRow: View {
    let icon: String
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16, alignment: .center)

                Text(label)
                    .font(.system(size: 13))

                Spacer()
            }
            .foregroundStyle(isHovered ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .animation(.easeInOut(duration: 0.08), value: isHovered)
        .onHover { isHovered = $0 }
    }
}
