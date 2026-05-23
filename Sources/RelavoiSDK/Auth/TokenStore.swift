import Foundation
import Security

/// Thin wrapper over Keychain Services for persisting the SDK's JWT.
///
/// - Service: `com.relavoi.sdk.auth`
/// - Account: the tenant ID (allows multiple tenants to coexist in one host app)
/// - Accessibility: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
final class TokenStore {

    private let service = "com.relavoi.sdk.auth"
    private let account: String

    init(tenantId: String) {
        self.account = tenantId
    }

    // MARK: - Public

    func save(token: String, expiresAt: Date) {
        let payload = StoredToken(token: token, expiresAt: expiresAt)
        guard let data = try? JSONEncoder().encode(payload) else { return }

        // Delete any previous entry first; SecItemUpdate is finicky on first-write.
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(baseQuery as CFDictionary)

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    func load() -> (String, Date)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        guard let decoded = try? JSONDecoder().decode(StoredToken.self, from: data) else {
            return nil
        }
        return (decoded.token, decoded.expiresAt)
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Internal codable

    private struct StoredToken: Codable {
        let token: String
        let expiresAt: Date
    }
}
