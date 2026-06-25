import SwiftUI
import WebKit
import os.log

private let paywallLogger = Logger(subsystem: "com.sahan.Nix", category: "PaywallView")

struct PaywallView: View {

    let onActivated: () -> Void

    @StateObject private var trial   = TrialManager.shared
    @StateObject private var license = LicenseManager.shared

    @State private var showManualEntry = false
    @State private var manualKey       = ""
    @State private var manualEntryError: String?

    private let checkoutURL: URL = {
        let urlString = "https://nixapp.lemonsqueezy.com/checkout/buy/9bd06aa9-0c32-4c46-b4d6-64fa6323ec6a?embed=1"
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

            ZStack {
                CheckoutWebView(url: checkoutURL, onLicenseKeyReceived: handleReceivedKey)
                    .opacity(showManualEntry ? 0 : 1)
                    .allowsHitTesting(!showManualEntry)

                if showManualEntry {
                    manualEntryForm
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: showManualEntry)

            Divider().opacity(0.35)
            footer
        }
        .frame(minWidth: 540, maxWidth: .infinity)
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
                    .background(Color.secondary.opacity(0.10),
                                in: Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Manual Entry Form
    // ─────────────────────────────────────────────────────────────────────────

    private var manualEntryForm: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)

                    Text("Enter your license key")
                        .font(.system(size: 16, weight: .semibold))

                    Text("Find it in your purchase confirmation email.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 6) {
                    TextField("XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX", text: $manualKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                        .disableAutocorrection(true)
                        .frame(width: 380)

                    if let error = manualEntryError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Button(license.isValidating ? "Validating…" : "Activate License") {
                    activateManualKey()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(
                    manualKey.trimmingCharacters(in: .whitespaces).isEmpty ||
                    license.isValidating
                )
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor).opacity(0.5))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Footer
    // ─────────────────────────────────────────────────────────────────────────

    private var footer: some View {
        HStack {
            Button(showManualEntry ? "← Back to Checkout" : "Already have a key?") {
                withAnimation { showManualEntry.toggle() }
                manualEntryError = nil
            }
            .buttonStyle(.link)
            .font(.system(size: 12))

            Spacer()

            if !trial.isExpired && !showManualEntry {
                Text("\(trial.daysRemaining) day\(trial.daysRemaining == 1 ? "" : "s") remaining in trial")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Actions
    // ─────────────────────────────────────────────────────────────────────────

    private func handleReceivedKey(_ key: String) {
        Task {
            let success = await license.activate(licenseKey: key)
            if success {
                paywallLogger.info("Activation succeeded via checkout redirect")
                onActivated()
            } else {
                paywallLogger.warning("Activation failed via redirect — \(license.lastError ?? "unknown")")
                manualEntryError = license.lastError
                withAnimation { showManualEntry = true }
            }
        }
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

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - CheckoutWebView
// ─────────────────────────────────────────────────────────────────────────────

private struct CheckoutWebView: NSViewRepresentable {

    let url: URL
    let onLicenseKeyReceived: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLicenseKeyReceived: onLicenseKeyReceived)
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) { }

    final class Coordinator: NSObject, WKNavigationDelegate {

        private let onLicenseKeyReceived: (String) -> Void

        init(onLicenseKeyReceived: @escaping (String) -> Void) {
            self.onLicenseKeyReceived = onLicenseKeyReceived
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if url.scheme == "nix", url.host == "activate" {
                let key = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "key" })?.value

                if let key {
                    paywallLogger.info("Intercepted license key from checkout redirect")
                    onLicenseKeyReceived(key)
                } else {
                    paywallLogger.warning("nix://activate redirect with no 'key' param")
                }
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }
}
