import Foundation
import Testing
@testable import handy_menu_dashboard

@Suite("Shared Keychain credentials")
struct KeychainStoreTests {
    @Test func providersShareOneEntryAndReadItOnlyOncePerLaunch() {
        let items = MemoryKeychainItems()
        let store = KeychainStore(items: items)
        store.saveString(key: .cursorCookies, value: "cursor")
        store.saveString(key: .claudeCookies, value: "claude")
        store.saveString(key: .copilotCookies, value: "github")
        store.saveString(key: .chatGPTCookies, value: "chatgpt")

        #expect(Set(items.values.keys) == [KeychainStore.account])
        let relaunched = KeychainStore(items: items)
        items.reads = []
        #expect(relaunched.loadString(key: .cursorCookies) == "cursor")
        #expect(relaunched.loadString(key: .claudeCookies) == "claude")
        #expect(relaunched.loadString(key: .copilotCookies) == "github")
        #expect(relaunched.loadString(key: .chatGPTCookies) == "chatgpt")
        #expect(items.reads == [KeychainStore.account])
    }

    @Test func oldEntriesAreIgnoredAndUsersMustAuthenticateAgain() {
        let items = MemoryKeychainItems()
        items.values[KeychainKey.cursorCookies.rawValue] = Data("old cursor".utf8)
        items.values[KeychainKey.claudeCookies.rawValue] = Data("old claude".utf8)
        let original = items.values
        let store = KeychainStore(items: items)

        #expect(store.loadString(key: .cursorCookies) == nil)
        #expect(store.loadString(key: .claudeCookies) == nil)
        #expect(items.reads == [KeychainStore.account])
        #expect(items.values == original)

        store.saveString(key: .cursorCookies, value: "new cursor")
        #expect(KeychainStore(items: items).loadString(key: .cursorCookies) == "new cursor")
        #expect(items.values[KeychainKey.cursorCookies.rawValue] == original[KeychainKey.cursorCookies.rawValue])
    }

    @Test func signingOutPreservesOtherProvidersAndDoesNotRestoreOldCookies() {
        let items = MemoryKeychainItems()
        items.values[KeychainKey.cursorCookies.rawValue] = Data("old".utf8)
        let store = KeychainStore(items: items)
        store.saveString(key: .cursorCookies, value: "cursor")
        store.saveString(key: .claudeCookies, value: "claude")
        store.delete(key: .cursorCookies)

        let relaunched = KeychainStore(items: items)
        #expect(relaunched.loadString(key: .cursorCookies) == nil)
        #expect(relaunched.loadString(key: .claudeCookies) == "claude")
        relaunched.delete(key: .claudeCookies)
        let signedOut = KeychainStore(items: items)
        #expect(signedOut.loadString(key: .cursorCookies) == nil)
        #expect(signedOut.loadString(key: .claudeCookies) == nil)
    }

    @Test func deniedReadDoesNotOverwriteSharedCredentials() {
        let items = MemoryKeychainItems()
        KeychainStore(items: items).saveString(key: .claudeCookies, value: "claude")
        let original = items.values
        items.deniedReads = [KeychainStore.account]
        let store = KeychainStore(items: items)
        store.saveString(key: .cursorCookies, value: "cursor")
        store.delete(key: .claudeCookies)
        #expect(store.loadString(key: .claudeCookies) == nil)
        #expect(items.values == original)
    }

    @Test func corruptSharedEntryIsNotReplacedWithEmptyCredentials() {
        let items = MemoryKeychainItems()
        items.values[KeychainStore.account] = Data("invalid JSON".utf8)
        let original = items.values
        let store = KeychainStore(items: items)
        #expect(store.loadString(key: .cursorCookies) == nil)
        store.saveString(key: .claudeCookies, value: "claude")
        store.delete(key: .cursorCookies)
        #expect(items.values == original)
    }

    @Test func failedWritesDoNotChangeCachedCredentials() {
        let items = MemoryKeychainItems()
        let store = KeychainStore(items: items)
        store.saveString(key: .cursorCookies, value: "original")
        items.failWrites = true
        store.saveString(key: .cursorCookies, value: "replacement")
        #expect(store.loadString(key: .cursorCookies) == "original")
        store.delete(key: .cursorCookies)
        #expect(store.loadString(key: .cursorCookies) == "original")
        #expect(KeychainStore(items: items).loadString(key: .cursorCookies) == "original")
    }

}

private final class MemoryKeychainItems: KeychainItemStoring {
    enum Failure: Error { case denied }

    var values: [String: Data] = [:]
    var reads: [String] = []
    var deniedReads: Set<String> = []
    var failWrites = false

    func load(account: String) throws -> Data? {
        reads.append(account)
        if deniedReads.contains(account) { throw Failure.denied }
        return values[account]
    }

    func save(account: String, data: Data) throws {
        if failWrites { throw Failure.denied }
        values[account] = data
    }
}
