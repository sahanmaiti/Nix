import ServiceManagement
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - OnboardingView (Container)
// ─────────────────────────────────────────────────────────────────────────────

struct OnboardingView: View {

    let onComplete: () -> Void

    @EnvironmentObject private var env: AppEnvironment

    @State private var currentStep: Int = 0

    @AppStorage("nix.onboardingComplete") private var onboardingComplete: Bool = false

    private let pageWidth: CGFloat = 520
    private let totalSteps: Int = 4

    var body: some View {
        VStack(spacing: 0) {
            // The sliding carousel — all steps exist simultaneously, offset horizontally
            stepCarousel
                .frame(height: 360)

            Divider()

            // Navigation dots + context-sensitive buttons
            navigationBar
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
        }
        .frame(width: pageWidth)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Carousel
    // ─────────────────────────────────────────────────────────────────────────

    private var stepCarousel: some View {
        ZStack(alignment: .topLeading) {
            WelcomeStep()
                .frame(width: pageWidth)
                .offset(x: pageOffset(for: 0))

            HowItWorksStep()
                .frame(width: pageWidth)
                .offset(x: pageOffset(for: 1))

            PermissionStep()
                .frame(width: pageWidth)
                .offset(x: pageOffset(for: 2))

            SetupStep()
                .frame(width: pageWidth)
                .offset(x: pageOffset(for: 3))
        }
        .clipped()
        .animation(.easeInOut(duration: 0.28), value: currentStep)
    }

    private func pageOffset(for step: Int) -> CGFloat {
        CGFloat(step - currentStep) * pageWidth
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Navigation Bar
    // ─────────────────────────────────────────────────────────────────────────

    private var navigationBar: some View {
        HStack(spacing: 0) {
            progressIndicator
            Spacer()
            navigationButtons
        }
    }

    // Animated "pill" indicators — the active step expands into a capsule
    private var progressIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index == currentStep
                          ? Color.accentColor
                          : Color.secondary.opacity(0.22))
                    .frame(width: index == currentStep ? 20 : 7, height: 7)
                    .animation(.spring(response: 0.3, dampingFraction: 0.75), value: currentStep)
            }
        }
    }

    // Each step gets context-appropriate buttons.
    // @ViewBuilder lets us return different view types per case.
    @ViewBuilder
    private var navigationButtons: some View {
        switch currentStep {

        case 0: // Welcome — single forward action
            Button("Get Started") { advance() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)

        case 1: // How It Works — can go back
            HStack(spacing: 10) {
                Button("Back") { retreat() }
                    .buttonStyle(.bordered)
                Button("Next") { advance() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
            }

        case 2: // Permission — "Continue" works even without permission
            HStack(spacing: 10) {
                Button("Back") { retreat() }
                    .buttonStyle(.bordered)
                Button(env.accessibilityManager.isGranted ? "Continue" : "Skip for Now") {
                    advance()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }

        case 3: // Final setup — commit action
            HStack(spacing: 10) {
                Button("Back") { retreat() }
                    .buttonStyle(.bordered)
                Button("Start Using Nix") { finish() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
            }

        default:
            EmptyView()
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Actions
    // ─────────────────────────────────────────────────────────────────────────

    private func advance() {
        guard currentStep < totalSteps - 1 else { return }
        currentStep += 1
    }

    private func retreat() {
        guard currentStep > 0 else { return }
        currentStep -= 1
    }

    private func finish() {
        // 1. Write the completion flag to UserDefaults.
        //    Next launch, AppDelegate reads this and skips showOnboarding().
        onboardingComplete = true

        // 2. Fire the closure — AppDelegate closes the NSWindow.
        onComplete()
    }
}


// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Step 0: Welcome
// ─────────────────────────────────────────────────────────────────────────────

struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.red)
                .symbolEffect(.pulse.wholeSymbol, options: .repeating)

            VStack(spacing: 6) {
                Text("Welcome to Nix")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Close the window. Quit the app.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Text("On macOS, closing a window doesn't quit the app. Nix changes that — automatically quitting apps when their last window closes.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)

            Spacer()
        }
        .padding(.horizontal, 48)
    }
}


// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Step 1: How It Works
// ─────────────────────────────────────────────────────────────────────────────

struct HowItWorksStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            Text("How It Works")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 22) {
                OnboardingRow(
                    number: "1",
                    title: "You close the last window",
                    detail: "Click the red close button as usual — nothing changes on your end."
                )
                OnboardingRow(
                    number: "2",
                    title: "Nix detects zero windows remain",
                    detail: "Using the macOS Accessibility API, Nix sees that no visible windows are left."
                )
                OnboardingRow(
                    number: "3",
                    title: "The app quits cleanly",
                    detail: "Nix sends the equivalent of Cmd+Q. The app saves its state and exits gracefully."
                )
            }

            Spacer()
        }
        .padding(.horizontal, 48)
    }
}

// Reusable numbered row for the How It Works step.
// Private to this file — nothing outside OnboardingView needs it.
private struct OnboardingRow: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Numbered badge
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 30, height: 30)
                Text(number)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}


// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Step 2: Accessibility Permission
// ─────────────────────────────────────────────────────────────────────────────

struct PermissionStep: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: permissionIcon)
                .font(.system(size: 72))
                .foregroundStyle(permissionIconColor)
                .symbolEffect(.bounce, value: env.accessibilityManager.isGranted)
                .animation(.spring(response: 0.4, dampingFraction: 0.6),
                           value: env.accessibilityManager.isGranted)

            VStack(spacing: 8) {
                Text("Accessibility Permission")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Nix uses the macOS Accessibility API to observe window close events in other apps. This requires your explicit permission — Nix cannot read window content or your data.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 390)
            }

            // Conditionally show grant button OR confirmation label
            if env.accessibilityManager.isGranted {
                Label("Permission Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .fontWeight(.semibold)
                    .transition(.scale.combined(with: .opacity))
            } else {
                VStack(spacing: 8) {
                    Button("Open Accessibility Settings") {
                        env.accessibilityManager.requestPermission()
                    }
                    .buttonStyle(.borderedProminent)

                    Text("System Settings → Privacy & Security → Accessibility → Enable Nix")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .transition(.opacity)
            }

            Spacer()
        }
        .padding(.horizontal, 48)
        .animation(.easeInOut(duration: 0.25), value: env.accessibilityManager.isGranted)
    }

    private var permissionIcon: String {
        env.accessibilityManager.isGranted ? "checkmark.shield.fill" : "lock.shield.fill"
    }

    private var permissionIconColor: Color {
        env.accessibilityManager.isGranted ? .green : .orange
    }
}


// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Step 3: Initial Setup
// ─────────────────────────────────────────────────────────────────────────────

struct SetupStep: View {

    @AppStorage(SettingsKey.defaultBehavior)
    private var defaultBehaviorRaw: String = AppBehavior.quit.rawValue

    @AppStorage(SettingsKey.launchAtLogin)
    private var launchAtLogin: Bool = false

    private var defaultBehavior: Binding<AppBehavior> {
        Binding(
            get: { AppBehavior(rawValue: defaultBehaviorRaw) ?? .quit },
            set: { defaultBehaviorRaw = $0.rawValue }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Header
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.green)

                Text("Almost Ready")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Set your preferences. You can change these anytime in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Preference controls in a rounded card
            VStack(alignment: .leading, spacing: 14) {

                // Default behavior picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("When the last window closes:")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Picker("Default behavior", selection: defaultBehavior) {
                        Text("Quit the app").tag(AppBehavior.quit)
                        Text("Hide the app").tag(AppBehavior.hide)
                        Text("Ask me each time").tag(AppBehavior.prompt)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Divider()

                // Launch at login toggle
                Toggle("Launch Nix automatically at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
            .padding(16)
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 40)

            Spacer()
        }
    }
}
