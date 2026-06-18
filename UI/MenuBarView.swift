import SwiftUI

// ─────────────────────────────────────────────────────────────
// MARK: - MenuBarView
// ─────────────────────────────────────────────────────────────

struct MenuBarView: View {

    @EnvironmentObject var env: AppEnvironment
    @Environment(\.openWindow) var openWindow

    var body: some View {
        VStack(spacing: 0) {

            // Permission warning — only when AX not granted
            if !env.accessibilityManager.isGranted {
                accessibilityWarning
                Divider()
            }

            header

            if !env.appTracker.trackedApps.isEmpty {
                Divider()
                appList
            }

            Divider()
            controlRows
        }
        .frame(width: 280)
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Accessibility Warning
    // ─────────────────────────────────────────────────────────

    private var accessibilityWarning: some View {
        Button { env.accessibilityManager.requestPermission() } label: {
            HStack(spacing: 9) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 14))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Accessibility Permission Required")
                        .font(.system(size: 12, weight: .medium))
                    Text("Click to open Privacy & Security")
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
        .background(Color.orange.opacity(0.07))
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Header
    // ─────────────────────────────────────────────────────────

    private var header: some View {
        HStack(spacing: 10) {
            // Icon color reflects active state — no text badge needed
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(headerIconColor)
                .animation(.easeInOut(duration: 0.2), value: env.isEnabled)
                .animation(.easeInOut(duration: 0.2), value: env.isPaused)

            VStack(alignment: .leading, spacing: 1) {
                Text("Nix")
                    .font(.system(size: 13, weight: .semibold))
                Text(headerStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $env.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .disabled(env.isPaused)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var headerIconColor: Color {
        guard env.isEnabled, !env.isPaused else { return Color(.tertiaryLabelColor) }
        return .red
    }

    private var headerStatus: String {
        if env.isPaused   { return "Monitoring paused" }
        if !env.isEnabled { return "Monitoring disabled" }
        let n = env.appTracker.trackedApps.count
        return n == 0 ? "No apps open" : "Watching \(n) app\(n == 1 ? "" : "s")"
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - App List
    // ─────────────────────────────────────────────────────────

    private var appList: some View {
        buildAppList(env.appTracker.trackedApps.sorted { $0.name < $1.name })
    }

    // Extracted to avoid @ViewBuilder constraints on let-bindings
    private func buildAppList(_ apps: [TrackedApp]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(apps.prefix(5))) { app in
                HStack(spacing: 8) {
                    Group {
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "app.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 14, height: 14)
                        }
                    }

                    Text(app.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer()

                    // 5px dot: green=active, orange=hidden, dimmed when paused
                    Circle()
                        .fill(app.isHidden ? Color.orange : Color.green)
                        .frame(width: 5, height: 5)
                        .opacity(env.isPaused ? 0.35 : 1.0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 3)
            }

            if apps.count > 5 {
                Text("and \(apps.count - 5) more")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 1)
                    .padding(.bottom, 2)
            }
        }
        .padding(.vertical, 5)
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Control Rows
    // ─────────────────────────────────────────────────────────

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

            Divider().padding(.horizontal, 4)

            MenuRow(icon: "gear", label: "Settings…", action: openSettings)
            MenuRow(icon: "power", label: "Quit Nix") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 3)
    }

    private func openSettings() {
        openWindow(id: "settings")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.title == "Settings" })?.makeKeyAndOrderFront(nil)
        }
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: - MenuRow
// Hover behavior replicates native NSMenu row highlighting.
// isHovered drives both background and foreground color.
// ─────────────────────────────────────────────────────────────

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
            // White text on accent matches native NSMenu highlight behavior
            .foregroundStyle(isHovered ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovered ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        // Fast fade mirrors native menu responsiveness
        .animation(.easeInOut(duration: 0.08), value: isHovered)
        .onHover { isHovered = $0 }
    }
}
