import Foundation
import Testing
@testable import handy_menu_dashboard

@Suite("Chromium cookie store")
struct ChromiumCookieStoreTests {
    @Test func readsPlaintextCookiesFromTheLastUsedProfile() throws {
        let root = setupUserData(lastUsed: "Profile 1")

        let store = ChromiumCookieStore(
            userDataRoot: root,
            safeStorageService: "Chrome Safe Storage",
            safeStorageAccount: "Chrome",
            safeStoragePassword: { "peanuts" }
        )
        let cookies = try store.cookies(matching: [.exactOrSuffix("github.com")])

        #expect(cookies.count == 1)
        #expect(cookies.first?.name == "user_session")
        #expect(cookies.first?.value == "live")
    }

    @Test func skipsExpiredCookiesButKeepsSessionCookies() throws {
        let root = setupUserData(lastUsed: "Default")

        let cookies = try ChromiumCookieStore(
            userDataRoot: root,
            safeStorageService: "Chrome Safe Storage",
            safeStorageAccount: "Chrome",
            safeStoragePassword: { "peanuts" }
        ).cookies(matching: [.contains("cursor.com")])

        #expect(cookies.map(\.value).sorted() == ["fresh", "session"])
    }

    @Test func throwsWhenTheProfileIsMissing() {
        let root = SQLiteTestDatabase.makeDirectory()

        var thrown: BrowserCookieError?
        do {
            _ = try ChromiumCookieStore(
                userDataRoot: root,
                safeStorageService: "Chrome Safe Storage",
                safeStorageAccount: "Chrome",
                safeStoragePassword: { "peanuts" }
            ).cookies(matching: [])
        } catch {
            thrown = error
        }

        #expect(thrown == .noProfile)
    }

    private func setupUserData(lastUsed: String) -> URL {
        let root = SQLiteTestDatabase.makeDirectory()

        let localState = ["profile": ["last_used": lastUsed]]
        let stateData = try? JSONSerialization.data(withJSONObject: localState)
        try? stateData?.write(to: root.appending(path: "Local State"))

        let profileDir = root.appending(path: lastUsed)
        try? FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)

        SQLiteTestDatabase.create(at: profileDir.appending(path: "Cookies"), statements: [
            "CREATE TABLE meta (key TEXT, value TEXT)",
            "INSERT INTO meta VALUES ('version', '24')",
            "CREATE TABLE cookies (host_key TEXT, name TEXT, value TEXT, path TEXT, encrypted_value BLOB, expires_utc INTEGER)",
            "INSERT INTO cookies VALUES ('github.com', 'user_session', 'live', '/', x'', 0)",
            "INSERT INTO cookies VALUES ('.example.com', 'other', 'nope', '/', x'', 0)",
            "INSERT INTO cookies VALUES ('.cursor.com', 'a', 'stale', '/', x'', 12591158400000000)",
            "INSERT INTO cookies VALUES ('.cursor.com', 'b', 'fresh', '/', x'', 15747091200000000)",
            "INSERT INTO cookies VALUES ('cursor.com', 'c', 'session', '/', x'', 0)"
        ])
        return root
    }
}
