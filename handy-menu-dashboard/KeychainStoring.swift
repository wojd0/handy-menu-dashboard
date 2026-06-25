import Foundation

enum KeychainKey: String {
    case cursorCookies = "com.wojd0.dashboard.cursorCookies"
    case copilotPAT = "com.wojd0.dashboard.copilotPAT"
    case copilotUsername = "com.wojd0.dashboard.copilotUsername"
    case copilotEntitlement = "com.wojd0.dashboard.copilotEntitlement"
}

protocol KeychainStoring {
    func save(key: KeychainKey, data: Data)
    func load(key: KeychainKey) -> Data?
    func delete(key: KeychainKey)
}

extension KeychainStoring {
    func saveString(key: KeychainKey, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        save(key: key, data: data)
    }

    func loadString(key: KeychainKey) -> String? {
        guard let data = load(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
