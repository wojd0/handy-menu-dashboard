import Foundation
import Testing
@testable import handy_menu_dashboard

@Suite("Firefox profile groups")
struct GeckoProfileTests {
    @Test func resolvesDisplayNamesAndSeparatesInstallations() throws {
        let root = SQLiteTestDatabase.makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRegistry(at: root)
        try writeGroup("release", at: root, rows: [
            "('moje', 'Profiles/personal')", "('robota', 'Profiles/work')"
        ])
        try writeGroup("developer", at: root, rows: ["('Development', 'Profiles/dev')"])
        try writeCompatibility("personal", application: "Firefox", at: root)
        try writeCompatibility("work", application: "Firefox", at: root)
        try writeCompatibility("dev", application: "Firefox Developer Edition", at: root)

        let store = GeckoCookieStore(profilesRoot: root)
        let release = try store.profiles(applicationURL: URL(fileURLWithPath: "/Applications/Firefox.app"))
        #expect(release.map(\.name) == ["robota", "moje"])
        #expect(release.map { $0.directory.path } == [
            root.appending(path: "Profiles/work").path, root.appending(path: "Profiles/personal").path
        ])
        let developer = try store.profiles(applicationURL: URL(fileURLWithPath: "/Applications/Firefox Developer Edition.app"))
        #expect(developer.map(\.name) == ["Development"])
    }

    @Test func expandsGroupMembersNotListedInRegistryAndResolvesAbsolutePaths() throws {
        let root = SQLiteTestDatabase.makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try "[Profile0]\nName=Old name\nPath=Profiles/personal\nStoreID=release\nDefault=1\n"
            .write(to: root.appending(path: "profiles.ini"), atomically: true, encoding: .utf8)
        try writeGroup("release", at: root, rows: [
            "('moje', 'Profiles/./personal')", "('robota', '/external/work')"
        ])
        let profiles = try GeckoCookieStore(profilesRoot: root).profiles()
        #expect(profiles.map(\.name) == ["moje", "robota"])
        #expect(profiles.last?.directory.path == "/external/work")
    }

    @Test(arguments: ["missing", "empty", "uninitialized", "corrupt"])
    func fallsBackToLegacyNamesWhenGroupIsUnavailable(state: String) throws {
        let root = SQLiteTestDatabase.makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try "[Profile0]\nName=Legacy\nPath=Profiles/legacy\nStoreID=release\n"
            .write(to: root.appending(path: "profiles.ini"), atomically: true, encoding: .utf8)
        if state != "missing" {
            try writeGroup("release", at: root, rows: [])
            let database = root.appending(path: "Profile Groups/release.sqlite")
            if state == "uninitialized" {
                SQLiteTestDatabase.create(at: database, statements: ["CREATE TABLE SharedPrefs (name TEXT)"])
            } else if state == "corrupt" {
                try Data("broken database".utf8).write(to: database)
            }
        }
        let profiles = try GeckoCookieStore(profilesRoot: root).profiles()
        #expect(profiles.map(\.name) == ["Legacy"])
    }

    @Test func ignoresUnreferencedGroups() throws {
        let root = SQLiteTestDatabase.makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try "[Profile0]\nName=Legacy\nPath=Profiles/legacy\n"
            .write(to: root.appending(path: "profiles.ini"), atomically: true, encoding: .utf8)
        try writeGroup("orphan", at: root, rows: ["('Deleted', 'Profiles/deleted')"])
        #expect(try GeckoCookieStore(profilesRoot: root).profiles().map(\.name) == ["Legacy"])
    }

    private func writeGroup(_ storeID: String, at root: URL, rows: [String]) throws {
        let groups = root.appending(path: "Profile Groups")
        try FileManager.default.createDirectory(at: groups, withIntermediateDirectories: true)
        SQLiteTestDatabase.create(at: groups.appending(path: "\(storeID).sqlite"), statements:
            ["CREATE TABLE Profiles (id INTEGER PRIMARY KEY, name TEXT, path TEXT)"]
            + rows.map { "INSERT INTO Profiles (name, path) VALUES \($0)" }
        )
    }

    private func writeCompatibility(_ profile: String, application: String, at root: URL) throws {
        let directory = root.appending(path: "Profiles/\(profile)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "[Compatibility]\nLastPlatformDir=/Applications/\(application).app/Contents/Resources\n"
            .write(to: directory.appending(path: "compatibility.ini"), atomically: true, encoding: .utf8)
    }

    private func writeRegistry(at root: URL) throws {
        let contents = """
        [Profile0]
        Name=dev-edition-default
        Path=Profiles/dev
        StoreID=developer
        [Profile3]
        Name=Profile 1
        Path=Profiles/personal
        StoreID=release
        [InstallRelease]
        Default=Profiles/work
        [Profile2]
        Name=Original profile
        Path=Profiles/work
        StoreID=release
        [InstallDeveloper]
        Default=Profiles/dev
        [Profile1]
        Name=default
        Path=Profiles/default
        Default=1
        """
        try contents.write(to: root.appending(path: "profiles.ini"), atomically: true, encoding: .utf8)
    }
}
