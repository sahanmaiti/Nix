import SwiftUI
import os.log

private let paywallLogger = Logger(subsystem: "com.sahan.Nix", category: "PaywallView")

struct PaywallView: View {

    let onActivated: () -> Void

    @StateObject private var trial   = TrialManager.shared
    @StateObject private var license = LicenseManager.shared

    @State private var manualKey       = ""
    @State private var manualEntryError: String?

    private let checkoutURL: URL = {
        let urlString = "https://nixapp.lemonsqueezy.com/checkout/buy/c5b82404-dcd0-4bb8-b478-b36991c1e3b2"
        #if !DEBUG
        precondition(
            !urlString.contains("YOURSTORE"),
            "🚨 Replace placeholder Lemon Squeezy checkout URL before shipping a Release build"
        )
        #endif
        return URL(string: urlString) ?? URL(string: "https://lemonsqueezy.com")!
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.35)

            ScrollView {
                VStack(spacing: 28) {
                    checkoutSection
                    orDivider
                    manualEntrySection
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }

            Divider().opacity(0.35)
            footer
        }
        .frame(minWidth: 540, maxWidth: .infinity, minHeight: 560)
        .padding(.top, 28)
        .glassWindow(.sidebar)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Header
    // ─────────────────────────────────────────────────────────────────────────

    private var header: some View {
        HStack(spacing: 12) {
            Image("NixIcon")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(trial.isExpired ? "Your Trial Has Ended" : "Unlock Nix")
                    .font(.system(size: 14, weight: .semibold))

                Text("One-time purchase · $9.99 · No subscription")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !trial.isExpired {
                Text("\(trial.daysRemaining) day\(trial.daysRemaining == 1 ? "" : "s") left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.10), in: Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Checkout Section (opens system browser)
    // ─────────────────────────────────────────────────────────────────────────

    private var checkoutSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "cart.fill")
                .font(.system(size: 30))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 6) {
                Text("Purchase a License")
                    .font(.system(size: 16, weight: .semibold))

                Text("Opens in your browser. After checkout, your license key\nis emailed to you and shown on the confirmation page.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                openCheckout()
            } label: {
                Label("Continue to Checkout", systemImage: "arrow.up.right.square")
                    .frame(maxWidth: 260)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var orDivider: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
            Text("OR")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Manual Key Entry (primary in-app activation path)
    // ─────────────────────────────────────────────────────────────────────────

    private var manualEntrySection: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text("Already have a license key?")
                    .font(.system(size: 14, weight: .semibold))
                Text("Paste it below to activate Nix.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                TextField("XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX", text: $manualKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .disableAutocorrection(true)
                    .frame(maxWidth: 400)

                if let error = manualEntryError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Button(license.isValidating ? "Validating…" : "Activate License") {
                activateManualKey()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(
                manualKey.trimmingCharacters(in: .whitespaces).isEmpty ||
                license.isValidating
            )
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .glassCard(cornerRadius: 14)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Footer
    // ─────────────────────────────────────────────────────────────────────────

    private var footer: some View {
        HStack {
            if !trial.isExpired {
                Text("\(trial.daysRemaining) day\(trial.daysRemaining == 1 ? "" : "s") remaining in trial")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Actions
    // ─────────────────────────────────────────────────────────────────────────

    private func openCheckout() {
        paywallLogger.info("Opening checkout in system browser")
        NSWorkspace.shared.open(checkoutURL)
    }

    private func activateManualKey() {
        let trimmed = manualKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            let success = await license.activate(licenseKey: trimmed)
            if success {
                onActivated()
            } else {
                manualEntryError = license.lastError ?? "Activation failed — check the key and try again."
            }
        }
    }
}
