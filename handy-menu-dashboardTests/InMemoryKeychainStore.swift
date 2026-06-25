import Foundation
@testable import handy_menu_dashboard

final class InMemoryKeychainStore: KeychainStoring, @unchecked Sendable {
    private var storage: [KeychainKey: Data] = [:]

    func save(key: KeychainKey, data: Data) {
        storage[key] = data
    }

    func load(key: KeychainKey) -> Data? {
        storage[key]
    }

    func delete(key: KeychainKey) {
        storage.removeValue(forKey: key)
    }
}
