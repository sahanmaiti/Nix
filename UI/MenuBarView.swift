// MenuBarView.swift

import SwiftUI

struct MenuBarView: View {

    @EnvironmentObject var env: AppEnvironment
    @Environment(\.openWindow) var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // -- PERMISSION BANNER --
            if !env.accessibilityManager.isGranted {
                permissionBanner
                Divider()
            }
            
            // -- HEADER --
            headerSection

            Divider()
            
            // -- STATUS --
            statusSection

            Divider()
            
            // --  APP SECTION --
            appsSection

            Divider()

            // -- PAUSE SECTION --
            pauseSection

            Divider()
            
            // -- FOOTER SECTION --
            footerSection
        }
        .frame(width: 260)
    }
    
    // MARK: - Permission Banner
    
    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            
            // Warming icon + title
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
                
                Text("Permission Required")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            // Explanation :
            Text("Nix needs Accessibility access to detect when app windows close.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            //The button that triggers the system permission prompt
            Button("Grant Permission") {
                env.accessibilityManager.requestPermission()
            }
            .font(.caption)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.08))
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

    // MARK: - Running Apps

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 0) {

            Text("RUNNING APPS (\(env.appTracker.trackedApps.count))")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)

            if env.appTracker.trackedApps.isEmpty {

                Text("No apps running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)

            } else {

                let appsToShow = Array(
                    env.appTracker.trackedApps
                        .sorted { $0.name < $1.name }
                        .prefix(6)
                )

                ForEach(appsToShow) { app in
                    appRow(app: app)
                }

                let remaining = env.appTracker.trackedApps.count - 6

                if remaining > 0 {
                    Text("+ \(remaining) more")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.top, 2)
                        .padding(.bottom, 6)
                }
            }
        }
    }

    private func appRow(app: TrackedApp) -> some View {
        HStack(spacing: 8) {

            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "app.fill")
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.secondary)
            }

            Text(app.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Circle()
                .fill(app.isHidden ? Color.yellow : Color.green)
                .frame(width: 6, height: 6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
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
                openWindow(id: "settings")
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
} 
