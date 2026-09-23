import Foundation
import Security

struct KeychainStore: KeychainStoring {
    private let serviceName = "handy-menu-dashboard"

    func save(key: KeychainKey, data: Data) {
        let protectedStatus = upsert(key: key, data: data, dataProtectionKeychain: true)
        if protectedStatus == errSecSuccess {
            delete(key: key, dataProtectionKeychain: false)
            return
        }

        // Local builds are intentionally unsigned, so they have no access group for
        // the data-protection Keychain. Keep credentials durable in the user's regular
        // macOS Keychain instead of silently dropping them.
        upsert(key: key, data: data, dataProtectionKeychain: false)
    }

    func load(key: KeychainKey) -> Data? {
        if let data = read(key: key, dataProtectionKeychain: true) {
            return data
        }

        guard let legacyData = read(key: key, dataProtectionKeychain: false) else { return nil }

        if upsert(key: key, data: legacyData, dataProtectionKeychain: true) == errSecSuccess {
            delete(key: key, dataProtectionKeychain: false)
        }
        return legacyData
    }

    func delete(key: KeychainKey) {
        delete(key: key, dataProtectionKeychain: true)
        delete(key: key, dataProtectionKeychain: false)
    }

    @discardableResult
    private func upsert(key: KeychainKey, data: Data, dataProtectionKeychain: Bool) -> OSStatus {
        let query = baseQuery(for: key, dataProtectionKeychain: dataProtectionKeychain)
        let attributes = [kSecValueData as String: data] as CFDictionary
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes)
        guard updateStatus == errSecItemNotFound else { return updateStatus }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        if dataProtectionKeychain {
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
        return SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func delete(key: KeychainKey, dataProtectionKeychain: Bool) {
        SecItemDelete(baseQuery(for: key, dataProtectionKeychain: dataProtectionKeychain) as CFDictionary)
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
