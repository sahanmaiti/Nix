// MenuBarView.swift

import SwiftUI

struct MenuBarView: View {

    @EnvironmentObject var env: AppEnvironment
    @Environment(\.openSettings) var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            headerSection

            Divider()

            statusSection

            Divider()

            pauseSection

            Divider()

            footerSection
        }
        .frame(width: 260)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text("Nix")
                    .font(.headline)

                Text(env.isPaused ? "Paused" : (env.isEnabled ? "Active" : "Disabled"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $env.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(env.isPaused)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Status

    private var statusSection: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Pause

    private var pauseSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if env.isPaused {
                menuRow(icon: "play.circle", label: "Resume Monitoring") {
                    env.resume()
                }
            } else {
                menuRow(icon: "pause.circle", label: "Pause for 30 minutes") {
                    env.pause(minutes: 30)
                }
                menuRow(icon: "pause.circle", label: "Pause for 2 hours") {
                    env.pause(minutes: 120)
                }
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuRow(icon: "gear", label: "Settings...") {
                openSettings()
            }
            menuRow(icon: "power", label: "Quit Nix") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    // MARK: - Row Helper

    private func menuRow(
        icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(label)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var statusColor: Color {
        if env.isPaused { return .yellow }
        if env.isEnabled { return .green }
        return .gray
    }

    private var statusText: String {
        if env.isPaused { return "Monitoring paused" }
        if env.isEnabled { return "Monitoring active" }
        return "Monitoring disabled"
    }

} // ← This closing brace ends the MenuBarView struct
