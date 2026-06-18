import SwiftUI
import ServiceManagement
import os.log

struct GeneralTab: View {

    @EnvironmentObject private var env: AppEnvironment

    @AppStorage(SettingsKey.defaultBehavior)
    private var defaultBehaviorRaw: String = AppBehavior.quit.rawValue

    @AppStorage(SettingsKey.gracePeriodSeconds)
    private var gracePeriodSeconds: Int = 0

    @AppStorage(SettingsKey.launchAtLogin)
    private var launchAtLogin: Bool = false

    @AppStorage(SettingsKey.showNotifications)
    private var showNotifications: Bool = true

    private var defaultBehavior: Binding<AppBehavior> {
        Binding(
            get: { AppBehavior(rawValue: defaultBehaviorRaw) ?? .quit },
            set: { defaultBehaviorRaw = $0.rawValue }
        )
    }

    private var gracePeriodDouble: Binding<Double> {
        Binding(
            get: { Double(gracePeriodSeconds) },
            set: { gracePeriodSeconds = Int($0) }
        )
    }

    var body: some View {
        Form {
            behaviorSection
            timingSection
            systemSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Behavior

    private var behaviorSection: some View {
        Section {
            Toggle("Enable Nix", isOn: $env.isEnabled)

            Picker("When last window closes", selection: defaultBehavior) {
                ForEach(AppBehavior.allCases, id: \.self) { behavior in
                    Text(behavior.displayName).tag(behavior)
                }
            }
            .pickerStyle(.menu)
            .disabled(!env.isEnabled)

        } header: {
            Text("Behavior")
        } footer: {
            Text("Set per-app overrides in the Apps tab.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Timing

    private var timingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Grace period")
                    Spacer()
                    // Plain text — avoid contentTransition on macOS 14 beta edge cases
                    Text(gracePeriodSeconds == 0 ? "Immediate" : "\(gracePeriodSeconds)s")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.1), value: gracePeriodSeconds)
                }

                Slider(value: gracePeriodDouble, in: 0...30, step: 1)
                    .disabled(!env.isEnabled)

                Text("Nix waits this long before quitting. Reopening a window during the grace period cancels the quit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Timing")
        }
    }

    // MARK: - System

    private var systemSection: some View {
        Section {
            Toggle("Launch Nix at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    let ok = LoginItemService.setEnabled(newValue)
                    if !ok { launchAtLogin = LoginItemService.isEnabled }
                }

            Toggle("Notify when an app is quit", isOn: $showNotifications)

        } header: {
            Text("System")
        } footer: {
            Text("Notifications appear briefly when Nix quits an app in the background.")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - AppBehavior Display Names

extension AppBehavior {
    var displayName: String {
        switch self {
        case .quit:   return "Quit the app"
        case .hide:   return "Hide the app"
        case .ignore: return "Do nothing (macOS default)"
        case .prompt: return "Ask me each time"
        }
    }
}

private func updateLoginItemState(_ enabled: Bool) {
    let success = LoginItemService.setEnabled(enabled)
    if !success { GlobalSettings.shared.launchAtLogin = LoginItemService.isEnabled }
}
