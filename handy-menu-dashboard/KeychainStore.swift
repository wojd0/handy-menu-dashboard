import Foundation
import OSLog

final class KeychainStore: KeychainStoring {
    static let account = "com.wojd0.dashboard.credentials"

    private struct Credentials: Codable {
        var values: [String: Data] = [:]
    }

    private let items: any KeychainItemStoring
    private var cachedCredentials: Credentials?
    private let logger = Logger(subsystem: "wojd0.handy-menu-dashboard", category: "Keychain")

    init(items: any KeychainItemStoring = SystemKeychainItems()) {
        self.items = items
    }

    func save(key: KeychainKey, data: Data) {
        do {
            var credentials = try loadCredentials()
            if credentials.values[key.rawValue] == data { return }
            credentials.values[key.rawValue] = data
            try persist(credentials)
        } catch {
            logger.error("Unable to save credentials.")
        }
    }

    func load(key: KeychainKey) -> Data? {
        do {
            return try loadCredentials().values[key.rawValue]
        } catch {
            logger.error("Unable to read credentials; saved entries were left unchanged.")
            return nil
        }
    }

    func delete(key: KeychainKey) {
        do {
            var credentials = try loadCredentials()
            if credentials.values[key.rawValue] == nil { return }
            credentials.values.removeValue(forKey: key.rawValue)
            try persist(credentials)
        } catch {
            logger.error("Unable to remove a credential.")
        }
    }

    private func loadCredentials() throws -> Credentials {
        if let cachedCredentials { return cachedCredentials }
        let credentials: Credentials
        if let data = try items.load(account: Self.account) {
            credentials = try JSONDecoder().decode(Credentials.self, from: data)
        } else {
            credentials = Credentials()
        }
        cachedCredentials = credentials
        return credentials
    }

    private func persist(_ credentials: Credentials) throws {
        try items.save(account: Self.account, data: JSONEncoder().encode(credentials))
        cachedCredentials = credentials
    }
}
