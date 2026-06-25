import Foundation
import Security

struct KeychainStore: KeychainStoring {
    private let serviceName = "handy-menu-dashboard"

    func save(key: KeychainKey, data: Data) {
        var query = baseQuery(for: key)
        query[kSecUseDataProtectionKeychain as String] = true

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(addQuery as CFDictionary, nil)
        }

        deleteLegacyItem(for: key)
    }

    func load(key: KeychainKey) -> Data? {
        if let data = loadFromDataProtectionKeychain(key: key) {
            return data
        }

        if let legacyData = loadLegacyItem(key: key) {
            save(key: key, data: legacyData)
            return legacyData
        }

        return nil
    }

    func delete(key: KeychainKey) {
        deleteLegacyItem(for: key)

        var query = baseQuery(for: key)
        query[kSecUseDataProtectionKeychain as String] = true
        SecItemDelete(query as CFDictionary)
    }

    private func baseQuery(for key: KeychainKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue
        ]
    }

    private func loadFromDataProtectionKeychain(key: KeychainKey) -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseDataProtectionKeychain as String] = true
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func loadLegacyItem(key: KeychainKey) -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func deleteLegacyItem(for key: KeychainKey) {
        let query = baseQuery(for: key)
        SecItemDelete(query as CFDictionary)
    }
}
