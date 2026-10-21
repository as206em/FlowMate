import Foundation
import Security

/// Stores secrets such as API keys outside the plain-text config file
protocol SecretStore: AnyObject {
    func secret(for account: String) -> String?
    /// Saves the secret; nil or an empty string deletes it
    func setSecret(_ value: String?, for account: String)
}

/// Saves secrets in the user's login Keychain
final class KeychainSecretStore: SecretStore {
    private let service: String

    init(service: String = "com.asem-mkl.FlowMate") {
        self.service = service
    }

    func secret(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func setSecret(_ value: String?, for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else {
            SecItemDelete(query as CFDictionary)
            return
        }

        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
}

/// Keeps secrets in memory only. Used by tests so they never touch the real Keychain.
final class InMemorySecretStore: SecretStore {
    private var secrets: [String: String] = [:]

    func secret(for account: String) -> String? {
        secrets[account]
    }

    func setSecret(_ value: String?, for account: String) {
        if let value, !value.isEmpty {
            secrets[account] = value
        } else {
            secrets.removeValue(forKey: account)
        }
    }
}
