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
    private let totalSteps: Int    = 4

    var body: some View {
        VStack(spacing: 0) {
            stepCarousel
                .frame(height: 370)

            // Nav bar with a very subtle glass separator
            Divider()
                .opacity(0.4)

            navigationBar
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(.ultraThinMaterial.opacity(0.5))
        }
        .frame(width: pageWidth)
        .glassWindow(.sidebar)
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
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: currentStep)
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

    // Animated pill indicators — active step expands to a capsule
    private var progressIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index == currentStep
                          ? Color.accentColor
                          : Color.secondary.opacity(0.20))
                    .frame(width: index == currentStep ? 22 : 7, height: 7)
                    .animation(.spring(response: 0.32, dampingFraction: 0.72), value: currentStep)
            }
        }
    }

    @ViewBuilder
    private var navigationButtons: some View {
        switch currentStep {

        case 0:
            Button("Get Started") { advance() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return)

        case 1:
            HStack(spacing: 10) {
                Button("Back") { retreat() }.buttonStyle(.bordered).controlSize(.large)
                Button("Next") { advance() }.buttonStyle(.borderedProminent).controlSize(.large)
                    .keyboardShortcut(.return)
            }

        case 2:
            HStack(spacing: 10) {
                Button("Back") { retreat() }.buttonStyle(.bordered).controlSize(.large)
                Button(env.accessibilityManager.isGranted ? "Continue" : "Skip for Now") {
                    advance()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return)
            }

        case 3:
            HStack(spacing: 10) {
                Button("Back") { retreat() }.buttonStyle(.bordered).controlSize(.large)
                Button("Start Using Nix") { finish() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.return)
            }

        default:
            EmptyView()
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Actions
    // ─────────────────────────────────────────────────────────────────────────

    private func advance()  { guard currentStep < totalSteps - 1 else { return }; currentStep += 1 }
    private func retreat()  { guard currentStep > 0 else { return }; currentStep -= 1 }
    private func finish()   { onboardingComplete = true; onComplete() }
}


// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Step 0: Welcome
// ─────────────────────────────────────────────────────────────────────────────

struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon with soft radial glow — more depth than a flat symbol
            ZStack {
                // Outer glow
                Circle()
                    .fill(.red.opacity(0.12))
                    .blur(radius: 28)
                    .frame(width: 130, height: 130)

                // Inner glow ring
                Circle()
                    .fill(.red.opacity(0.08))
                    .frame(width: 96, height: 96)

                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 64, weight: .regular))
                    .foregroundStyle(.red)
                    .symbolRenderingMode(.hierarchical)
                    .symbolEffect(.pulse, options: .repeating)
            }
            .padding(.bottom, 24)

            VStack(spacing: 7) {
                Text("Welcome to Nix")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("Close the window. Quit the app.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 16)

            Text("On macOS, closing a window doesn't quit the app. Nix changes that — automatically quitting apps when their last window closes.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 370)

            Spacer()
        }
        .padding(.horizontal, 52)
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
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .padding(.bottom, 28)

            VStack(alignment: .leading, spacing: 24) {
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
        .padding(.horizontal, 52)
    }
}

private struct OnboardingRow: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 32, height: 32)
                Text(number)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .fontWeight(.semibold)
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
        VStack(spacing: 0) {
            Spacer()

            // Icon with glow matching current permission state
            ZStack {
                Circle()
                    .fill(permissionIconColor.opacity(0.12))
                    .blur(radius: 24)
                    .frame(width: 120, height: 120)

                Image(systemName: permissionIcon)
                    .font(.system(size: 64))
                    .foregroundStyle(permissionIconColor)
                    .symbolRenderingMode(.hierarchical)
                    .symbolEffect(.bounce, value: env.accessibilityManager.isGranted)
                    .animation(.spring(response: 0.4, dampingFraction: 0.6),
                               value: env.accessibilityManager.isGranted)
            }
            .padding(.bottom, 20)

            VStack(spacing: 8) {
                Text("Accessibility Permission")
                    .font(.system(size: 22, weight: .bold, design: .rounded))

                Text("Nix uses the macOS Accessibility API to observe window close events in other apps. This requires your explicit permission — Nix cannot read window content or your data.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 390)
            }
            .padding(.bottom, 24)

            if env.accessibilityManager.isGranted {
                Label("Permission Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .fontWeight(.semibold)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            } else {
                VStack(spacing: 8) {
                    Button("Open Accessibility Settings") {
                        env.accessibilityManager.requestPermission()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Text("System Settings → Privacy & Security → Accessibility → Enable Nix")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .transition(.opacity)
            }

            Spacer()
        }
        .padding(.horizontal, 52)
        .animation(.easeInOut(duration: 0.22), value: env.accessibilityManager.isGranted)
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
                ZStack {
                    Circle()
                        .fill(.green.opacity(0.12))
                        .blur(radius: 18)
                        .frame(width: 90, height: 90)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.green)
                        .symbolRenderingMode(.hierarchical)
                }
                .padding(.bottom, 4)

                Text("Almost Ready")
                    .font(.system(size: 22, weight: .bold, design: .rounded))

                Text("Set your preferences. You can change these anytime in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Settings card — Liquid Glass on Tahoe, ultraThinMaterial on Sonoma
            VStack(alignment: .leading, spacing: 16) {

                VStack(alignment: .leading, spacing: 8) {
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
                    .opacity(0.5)

                Toggle("Launch Nix automatically at login", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .onChange(of: launchAtLogin) { _, newValue in
                        let success = LoginItemService.setEnabled(newValue)
                        if !success { launchAtLogin = LoginItemService.isEnabled }
                    }
            }
            .padding(18)
            .glassCard(cornerRadius: 14)   // ← Liquid Glass on Tahoe, material on Sonoma
            .padding(.horizontal, 44)

            Spacer()
        }
    }
}
