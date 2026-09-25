import Foundation
import Testing
@testable import handy_menu_dashboard

@Suite("Gecko cookie store")
struct GeckoCookieStoreTests {
    @Test func readsCookiesFromTheDefaultProfileFilteredByDomain() throws {
        let root = setupProfile()

        let store = GeckoCookieStore(profilesRoot: root)
        let cookies = try store.cookies(matching: [.contains("claude.ai")])

        #expect(cookies.count == 1)
        #expect(cookies.first?.name == "sessionKey")
        #expect(cookies.first?.value == "abc")
        #expect(cookies.first?.domain == ".claude.ai")
    }

    @Test func skipsExpiredCookies() throws {
        let root = setupProfile()

        let cookies = try GeckoCookieStore(profilesRoot: root).cookies(matching: [.contains("cursor.com")])

        #expect(cookies.map(\.value) == ["fresh"])
    }

    @Test func throwsWhenNoProfileExists() {
        let root = SQLiteTestDatabase.makeDirectory()

        var thrown: BrowserCookieError?
        do {
            _ = try GeckoCookieStore(profilesRoot: root).cookies(matching: [])
        } catch {
            thrown = error
        }

        #expect(thrown == .noProfile)
    }

    private func setupProfile() -> URL {
        let root = SQLiteTestDatabase.makeDirectory()
        let profileDir = root.appending(path: "Profiles/abc.default")
        try? FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)

        let ini = "[Install123]\nDefault=Profiles/abc.default\n\n[Profile0]\nPath=Profiles/abc.default\nDefault=1\n"
        try? ini.write(to: root.appending(path: "profiles.ini"), atomically: true, encoding: .utf8)

        SQLiteTestDatabase.create(at: profileDir.appending(path: "cookies.sqlite"), statements: [
            "CREATE TABLE moz_cookies (host TEXT, name TEXT, value TEXT, path TEXT, expiry INTEGER)",
            "INSERT INTO moz_cookies VALUES ('.claude.ai', 'sessionKey', 'abc', '/', 4102444800)",
            "INSERT INTO moz_cookies VALUES ('.example.com', 'other', 'xyz', '/', 4102444800)",
            "INSERT INTO moz_cookies VALUES ('.cursor.com', 'WorkosCursorSessionToken', 'stale', '/', 946684800)",
            "INSERT INTO moz_cookies VALUES ('cursor.com', 'WorkosCursorSessionToken', 'fresh', '/', 4102444800)"
        ])
        return root
    }
}
