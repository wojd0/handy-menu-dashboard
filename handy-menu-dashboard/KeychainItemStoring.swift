import Foundation
import Security

/// The item-level seam keeps storage tests out of the user's Keychain.
protocol KeychainItemStoring {
    func load(account: String) throws -> Data?
    func save(account: String, data: Data) throws
}

final class SystemKeychainItems: KeychainItemStoring {
    private var locations: [String: Bool] = [:]

    private struct KeychainError: Error {
        let status: OSStatus
    }

    func load(account: String) throws -> Data? {
        do {
            if let data = try read(account: account, dataProtectionKeychain: true) {
                locations[account] = true
                return data
            }
        } catch let error as KeychainError where isUnavailable(error.status) {
            // Unsigned local builds have no data-protection Keychain access group.
        }
        let data = try read(account: account, dataProtectionKeychain: false)
        if data != nil { locations[account] = false }
        return data
    }

    func save(account: String, data: Data) throws {
        // Update the same item when switching between unsigned and signed builds.
        // Creating a second copy in the other Keychain would leave stale credentials.
        if let location = locations[account] {
            let status = upsert(account: account, data: data, dataProtectionKeychain: location)
            guard status == errSecSuccess else { throw KeychainError(status: status) }
            return
        }
        let status = upsert(account: account, data: data, dataProtectionKeychain: true)
        if status == errSecSuccess {
            locations[account] = true
            return
        }
        guard isUnavailable(status) else { throw KeychainError(status: status) }
        let fallbackStatus = upsert(account: account, data: data, dataProtectionKeychain: false)
        guard fallbackStatus == errSecSuccess else { throw KeychainError(status: fallbackStatus) }
        locations[account] = false
    }

    private func isUnavailable(_ status: OSStatus) -> Bool {
        status == errSecMissingEntitlement || status == errSecNotAvailable
    }

    private func upsert(account: String, data: Data, dataProtectionKeychain: Bool) -> OSStatus {
        let query = baseQuery(account: account, dataProtectionKeychain: dataProtectionKeychain)
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

    private func read(account: String, dataProtectionKeychain: Bool) throws -> Data? {
        var query = baseQuery(account: account, dataProtectionKeychain: dataProtectionKeychain)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(status: status == errSecSuccess ? errSecDecode : status)
        }
        return data
    }

    private func baseQuery(account: String, dataProtectionKeychain: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "handy-menu-dashboard",
            kSecAttrAccount as String: account
        ]
        if dataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }
}
