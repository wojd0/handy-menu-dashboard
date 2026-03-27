import Foundation
import Security

enum KeychainService {
    enum Key: String {
        case cursorCookies = "com.wojd0.dashboard.cursorCookies"
        case copilotPAT = "com.wojd0.dashboard.copilotPAT"
        case copilotUsername = "com.wojd0.dashboard.copilotUsername"
        case copilotEntitlement = "com.wojd0.dashboard.copilotEntitlement"
    }

    static func save(key: Key, data: Data) {
        delete(key: key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "wojciech-little-dashboard",
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: Key) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "wojciech-little-dashboard",
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "wojciech-little-dashboard",
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func saveString(key: Key, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        save(key: key, data: data)
    }

    static func loadString(key: Key) -> String? {
        guard let data = load(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
