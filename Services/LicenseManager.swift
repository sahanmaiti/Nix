import Foundation
import Combine
import os.log

// MARK: - API Response Models

private struct ActivateResponse: Decodable {
    let activated: Bool
    let error: String?
    let instance: InstanceInfo?

    struct InstanceInfo: Decodable {
        let id: String
    }
}

private struct ValidateResponse: Decodable {
    let valid: Bool
    let error: String?
}

// MARK: - Keychain Account Keys

private enum LicenseAccount {
    static let key        = "nix.license.key"
    static let instanceID = "nix.license.instanceID"
}

// MARK: - LicenseManager

@MainActor
final class LicenseManager: ObservableObject {

    @Published private(set) var isLicensed: Bool = false
    @Published private(set) var isValidating: Bool = false
    @Published private(set) var lastError: String?

    private let logger = Logger(subsystem: "com.sahan.Nix", category: "LicenseManager")

    private let activateURL = URL(string: "https://api.lemonsqueezy.com/v1/licenses/activate")!
    private let validateURL = URL(string: "https://api.lemonsqueezy.com/v1/licenses/validate")!

    static let shared = LicenseManager()

    private init() {
        isLicensed = KeychainHelper.load(account: LicenseAccount.key) != nil
        logger.info("LicenseManager initialized — cached license present: \(self.isLicensed)")
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Activation (first purchase, or reinstall with existing key)
    // ─────────────────────────────────────────────────────────

    @discardableResult
    func activate(licenseKey: String) async -> Bool {
        isValidating = true
        lastError = nil
        defer { isValidating = false }

        var request = URLRequest(url: activateURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncode([
            "license_key":   licenseKey,
            "instance_name": instanceIdentifier()
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                lastError = "No response from license server"
                return false
            }

            let decoded = try JSONDecoder().decode(ActivateResponse.self, from: data)

            guard http.statusCode == 200, decoded.activated else {
                lastError = decoded.error ?? "Activation failed (HTTP \(http.statusCode))"
                logger.warning("Activation rejected: \(self.lastError ?? "unknown")")
                return false
            }

            KeychainHelper.save(licenseKey, account: LicenseAccount.key)
            if let instanceID = decoded.instance?.id {
                KeychainHelper.save(instanceID, account: LicenseAccount.instanceID)
            }

            isLicensed = true
            logger.info("✅ License activated")
            return true

        } catch {
            lastError = "Network error: \(error.localizedDescription)"
            logger.error("Activate request failed: \(error.localizedDescription)")
            return false
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Startup Validation
    // ─────────────────────────────────────────────────────────

    func validateStoredLicense() async {
        guard let key = KeychainHelper.load(account: LicenseAccount.key) else {
            isLicensed = false
            return
        }

        isValidating = true
        defer { isValidating = false }

        var params = ["license_key": key]
        if let instanceID = KeychainHelper.load(account: LicenseAccount.instanceID) {
            params["instance_id"] = instanceID
        }

        var request = URLRequest(url: validateURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncode(params)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                logger.warning("Validate: non-200 response — keeping cached license state")
                return
            }

            let decoded = try JSONDecoder().decode(ValidateResponse.self, from: data)
            isLicensed = decoded.valid

            if !decoded.valid {
                logger.warning("License revoked (\(decoded.error ?? "unknown")) — clearing local state")
                KeychainHelper.delete(account: LicenseAccount.key)
                KeychainHelper.delete(account: LicenseAccount.instanceID)
            }
        } catch {
            logger.debug("Validate failed, likely offline: \(error.localizedDescription) — keeping cached state")
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Helpers
    // ─────────────────────────────────────────────────────────

    private func instanceIdentifier() -> String {
        let storageKey = "nix.license.instanceName"
        if let existing = UserDefaults.standard.string(forKey: storageKey) {
            return existing
        }
        let new = "Mac-\(UUID().uuidString.prefix(8))"
        UserDefaults.standard.set(new, forKey: storageKey)
        return new
    }

    private func formEncode(_ params: [String: String]) -> Data {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+"))
        let pairs = params.map { key, value -> String in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }
        return pairs.joined(separator: "&").data(using: .utf8) ?? Data()
    }

    #if DEBUG
    func debugReset() {
        KeychainHelper.delete(account: LicenseAccount.key)
        KeychainHelper.delete(account: LicenseAccount.instanceID)
        isLicensed = false
        logger.warning("DEBUG: license reset")
    }
    #endif
}
