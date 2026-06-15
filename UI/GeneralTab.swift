import SwiftUI
import ServiceManagement
import os.log

struct GeneralTab: View {

    // MARK: - Live State (via AppEnvironment)
    
    @EnvironmentObject private var env: AppEnvironment

    // MARK: - Persisted Settings (via @AppStorage)

    @AppStorage(SettingsKey.defaultBehavior)
    private var defaultBehaviorRaw: String = AppBehavior.quit.rawValue

    @AppStorage(SettingsKey.gracePeriodSeconds)
    private var gracePeriodSeconds: Int = 0

    @AppStorage(SettingsKey.launchAtLogin)
    private var launchAtLogin: Bool = false

    @AppStorage(SettingsKey.showNotifications)
    private var showNotifications: Bool = true

    // MARK: - Bridging Bindings

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

    // MARK: - Body

    var body: some View {
        Form {
            behaviorSection
            timingSection
            systemSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Sections

    private var behaviorSection: some View {
        Section {
            // THE MAIN TOGGLE
            Toggle("Enable Nix", isOn: $env.isEnabled)

            // DEFAULT BEHAVIOR PICKER
            Picker("When last window closes", selection: defaultBehavior) {
                ForEach(AppBehavior.allCases, id: \.self) { behavior in
                    Text(behavior.displayName)
                        .tag(behavior)
                }
            }
            .pickerStyle(.menu)
            .disabled(!env.isEnabled)

        } header: {
            Text("Behavior")
        } footer: {
            Text("Per-app overrides can be set in the Apps tab.")
                .foregroundStyle(.secondary)
        }
    }

    private var timingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {

                HStack {
                    Text("Grace period")
                    Spacer()
                    Text(gracePeriodSeconds == 0 ? "Immediate" : "\(gracePeriodSeconds)s")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.1), value: gracePeriodSeconds)
                }

                Slider(value: gracePeriodDouble, in: 0...30, step: 1)
                    .disabled(!env.isEnabled)

                Text("How long to wait before quitting after the last window closes. Open a new window during this period to cancel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        } header: {
            Text("Timing")
        }
    }

    private var systemSection: some View {
        Section {
            // LAUNCH AT LOGIN TOGGLE
            Toggle("Launch Nix at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    updateLoginItemState(newValue)
                }

            // NOTIFICATION TOGGLE
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
    do {
        if enabled {
            try SMAppService.mainApp.register()
            Logger(subsystem: "com.sahan.Nix", category: "GeneralTab")
                .info("Login item registered - Nix will launch at login")
        } else {
            try SMAppService.mainApp.unregister()
            Logger(subsystem: "com.sahan.Nix", category: "GeneralTab")
                .info("Login item unregistered - Nix will not launch at login")
        }
    } catch {
        Logger(subsystem: "com.sahan.Nix", category: "GeneralTab")
            .error("Login item update failed: \(error.localizedDescription)")
    }
}

