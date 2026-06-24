import SwiftUI
import WebKit
import os.log

private let paywallLogger = Logger(subsystem: "com.sahan.Nix", category: "PaywallView")

struct PaywallView: View {

    let onActivated: () -> Void

    @StateObject private var trial   = TrialManager.shared
    @StateObject private var license = LicenseManager.shared

    @State private var showManualEntry = false
    @State private var manualKey = ""
    @State private var manualEntryError: String?

    // ⚠️ REPLACE before shipping: your real Lemon Squeezy checkout URL.
    // Get it from: LS Dashboard → Your Product → Share → Checkout URL
    // Append ?embed=1 for cleaner overlay (strips LS page chrome).
    // Set redirect after purchase to: nix://activate?key=[license_key]
    private let checkoutURL: URL = {
        let urlString = "https://nixapp.lemonsqueezy.com/checkout/buy/9bd06aa9-0c32-4c46-b4d6-64fa6323ec6a"
        // Only hard-crash in Release builds — in Debug, the WKWebView just shows
        // a failed load, which is fine for testing the trial expiry flow.
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
            Divider().opacity(0.4)

            if showManualEntry {
                manualEntryForm
            } else {
                CheckoutWebView(url: checkoutURL, onLicenseKeyReceived: handleReceivedKey)
            }

            Divider().opacity(0.4)
            footer
        }
        .frame(width: 480, height: 560)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Image("NixIcon")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            Text(trial.isExpired ? "Your Trial Has Ended" : "Unlock Nix")
                .font(.system(size: 18, weight: .bold, design: .rounded))

            Text("One-time purchase · $9.99 · No subscription")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    // MARK: - Manual Entry Fallback

    private var manualEntryForm: some View {
        VStack(spacing: 14) {
            Spacer()

            Text("Enter the license key from your purchase email")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            TextField("XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX", text: $manualKey)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
                .disableAutocorrection(true)

            if let error = manualEntryError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button(license.isValidating ? "Validating…" : "Activate") {
                activateManualKey()
            }
            .buttonStyle(.borderedProminent)
            .disabled(manualKey.trimmingCharacters(in: .whitespaces).isEmpty || license.isValidating)

            Spacer()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button(showManualEntry ? "Back to Checkout" : "Already have a key?") {
                showManualEntry.toggle()
                manualEntryError = nil
            }
            .buttonStyle(.link)
            .font(.caption)

            Spacer()

            if !trial.isExpired {
                Text("\(trial.daysRemaining) day\(trial.daysRemaining == 1 ? "" : "s") left in trial")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Activation

    private func handleReceivedKey(_ key: String) {
        Task {
            let success = await license.activate(licenseKey: key)
            if success {
                paywallLogger.info("Activation succeeded via checkout redirect")
                onActivated()
            } else {
                paywallLogger.warning("Activation failed via redirect — \(license.lastError ?? "unknown")")
                manualEntryError = license.lastError
                showManualEntry = true
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

    /// Intercepts the nix:// redirect BEFORE WKWebView tries (and fails) to
    /// load it as a real navigation — avoids any OS-level round trip.
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
