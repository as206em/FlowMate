import Foundation
import Security

/// Stores secrets such as API keys outside the plain-text config file
protocol SecretStore: AnyObject {
    func secret(for account: String) -> String?
    /// Saves the secret; nil or an empty string deletes it.
    /// - Returns: false if the store couldn't save it
    @discardableResult
    func setSecret(_ value: String?, for account: String) -> Bool
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

    @discardableResult
    func setSecret(_ value: String?, for account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }

        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        return status == errSecSuccess
    }
}

/// Keeps secrets in memory only. Used by tests so they never touch the real Keychain.
final class InMemorySecretStore: SecretStore {
    private var secrets: [String: String] = [:]

    func secret(for account: String) -> String? {
        secrets[account]
    }

    /// Set to true to simulate a store that can't save (tests)
    var failsWrites = false

    @discardableResult
    func setSecret(_ value: String?, for account: String) -> Bool {
        guard !failsWrites else { return false }
        if let value, !value.isEmpty {
            secrets[account] = value
        } else {
            secrets.removeValue(forKey: account)
        }
        return true
    }
}
