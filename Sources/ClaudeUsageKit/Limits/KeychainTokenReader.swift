import Foundation
import Security

/// Reads the Claude Code OAuth access token from the macOS Keychain.
///
/// Claude Code stores its credentials as a generic-password item named
/// `Claude Code-credentials`, whose value is a JSON blob of the form
/// `{ "claudeAiOauth": { "accessToken": "...", ... } }`. We read the current
/// token on every request, so as long as Claude Code keeps it refreshed, the
/// widget always has a valid token — no separate login required.
///
/// The first read from a differently-signed app triggers a one-time Keychain
/// authorization prompt; choosing "Always Allow" makes subsequent reads silent.
public enum KeychainTokenReader {
    /// The Keychain item Claude Code writes its credentials to.
    public static let service = "Claude Code-credentials"

    /// The current Claude Code OAuth access token, or `nil` if unavailable.
    public static func claudeCodeAccessToken() -> String? {
        guard let data = rawCredentialData() else { return nil }
        return accessToken(fromJSON: data)
    }

    static func rawCredentialData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    /// Extract the access token from the stored JSON, tolerating both the
    /// nested (`claudeAiOauth.accessToken`) and flat (`accessToken`) shapes.
    static func accessToken(fromJSON data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let root = object as? [String: Any]
        else {
            return nil
        }
        if let oauth = root["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String, !token.isEmpty {
            return token
        }
        if let token = root["accessToken"] as? String, !token.isEmpty {
            return token
        }
        return nil
    }
}
