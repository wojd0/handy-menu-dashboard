import Foundation
import Security

struct KeychainStore: KeychainStoring {
    private let serviceName = "handy-menu-dashboard"

    func save(key: KeychainKey, data: Data) {
        let query = baseQuery(for: key)

        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    func load(key: KeychainKey) -> Data? {
        if let data = read(key: key, dataProtectionKeychain: true) {
            return data
        }

        guard let legacyData = read(key: key, dataProtectionKeychain: false) else { return nil }

        save(key: key, data: legacyData)
        SecItemDelete(baseQuery(for: key, dataProtectionKeychain: false) as CFDictionary)
        return legacyData
    }

    func delete(key: KeychainKey) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }

    private func read(key: KeychainKey, dataProtectionKeychain: Bool) -> Data? {
        var query = baseQuery(for: key, dataProtectionKeychain: dataProtectionKeychain)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func baseQuery(for key: KeychainKey, dataProtectionKeychain: Bool = true) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue
        ]
        if dataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }
}
