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

    @Test func reportsAccessDeniedWhenTheProfilesFileIsNotReadable() throws {
        let root = setupProfile()
        let ini = root.appending(path: "profiles.ini")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: ini.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: ini.path) }

        var thrown: BrowserCookieError?
        do {
            _ = try GeckoCookieStore(profilesRoot: root).cookies(matching: [])
        } catch {
            thrown = error
        }

        #expect(thrown == .accessDenied)
    }

    @Test func listsNamedProfilesWithInstallDefaultFirst() throws {
        let root = SQLiteTestDatabase.makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let ini = """
        [Profile0]
        Name=Personal
        IsRelative=1
        Path=Profiles/personal
        [Profile1]
        Name=Work
        IsRelative=0
        Path=/external/work
        [Install123]
        Default=/external/work
        """
        try ini.write(to: root.appending(path: "profiles.ini"), atomically: true, encoding: .utf8)
        let profiles = try GeckoCookieStore(profilesRoot: root).profiles()
        #expect(profiles.map(\.name) == ["Work", "Personal"])
        #expect(profiles[0].directory.path == "/external/work")
        #expect(profiles[1].directory == root.appending(path: "Profiles/personal"))
    }

    @Test func readsOnlyTheExplicitlySelectedProfile() throws {
        let root = setupProfile()
        defer { try? FileManager.default.removeItem(at: root) }
        let selected = root.appending(path: "Profiles/work")
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: true)
        SQLiteTestDatabase.create(at: selected.appending(path: "cookies.sqlite"), statements: [
            "CREATE TABLE moz_cookies (host TEXT, name TEXT, value TEXT, path TEXT, expiry INTEGER)",
            "INSERT INTO moz_cookies VALUES ('.claude.ai', 'sessionKey', 'work', '/', 4102444800)"
        ])
        let cookies = try GeckoCookieStore(profilesRoot: root).cookies(
            matching: [.contains("claude.ai")], profile: selected
        )
        #expect(cookies.map(\.value) == ["work"])
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
