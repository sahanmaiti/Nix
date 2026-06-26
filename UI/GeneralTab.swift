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
            if !env.licenseManager.isLicensed {
                licenseSection
            }
            behaviorSection
            timingSection
            systemSection
        }
        .formStyle(.grouped)
    }

    // MARK: - License / Trial

    private var licenseSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {

                // Title row
                HStack(alignment: .center) {
                    Image(systemName: trialIcon)
                        .foregroundStyle(trialColor)
                        .font(.system(size: 13, weight: .medium))
                    Text(trialTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(trialColor)
                    Spacer()
                    Text(trialBadge)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(trialColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(trialColor.opacity(0.10), in: Capsule())
                }

                // Progress bar
                ProgressView(value: trialProgress)
                    .tint(trialColor)

                // Subtitle + CTA
                HStack(alignment: .center) {
                    Text(trialSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Upgrade · $9.99") {
                        AppDelegate.shared.showPaywall()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("License")
        }
    }

    // MARK: - Trial helpers

    private var trial: TrialManager { env.trialManager }

    private var trialProgress: Double {
        let total = Double(TrialManager.trialDurationDays)
        let used  = total - Double(trial.daysRemaining)
        return min(max(used / total, 0), 1)
    }

    private var trialColor: Color {
        if trial.isExpired          { return .red }
        if trial.daysRemaining <= 2 { return .orange }
        return .green
    }

    private var trialIcon: String {
        trial.isExpired ? "exclamationmark.circle.fill" : "clock.fill"
    }

    private var trialTitle: String {
        trial.isExpired ? "Free Trial Ended" : "Free Trial"
    }

    private var trialBadge: String {
        trial.isExpired
            ? "Expired"
            : "\(trial.daysRemaining) day\(trial.daysRemaining == 1 ? "" : "s") left"
    }

    private var trialSubtitle: String {
        trial.isExpired
            ? "Upgrade to keep using Nix."
            : "Full access during trial. Upgrade anytime to continue after it ends."
    }

    // MARK: - Behavior

    private var behaviorSection: some View {
        Section {
            Toggle("Enable Nix", isOn: $env.isEnabled)

            Picker("When last window closes", selection: defaultBehavior) {
                ForEach(AppBehavior.allCases, id: \.self) { b in
                    Text(b.displayName).tag(b)
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
