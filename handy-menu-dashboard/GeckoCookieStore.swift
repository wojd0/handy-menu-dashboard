import Foundation

nonisolated struct GeckoCookieStore {
    static let freshness = "(expiry = 0 OR expiry > CAST(strftime('%s', 'now') AS INTEGER))"

    let profilesRoot: URL

    func cookies(
        matching filters: [CookieHarvest.DomainMatch], profile: URL? = nil, applicationURL: URL? = nil
    ) throws(BrowserCookieError) -> [BrowserCookie] {
        let directory: URL
        if let profile {
            directory = profile
        } else {
            guard let first = try profiles(applicationURL: applicationURL).first else { throw .noProfile }
            directory = first.directory
        }
        let database = directory.appending(path: "cookies.sqlite")

        let snapshot = try SQLiteSnapshot(of: database)
        defer { snapshot.close() }

        let predicate = CookieHarvest.DomainMatch.sqlWhereClause(filters, column: "host", freshness: Self.freshness)
        let rows = try snapshot.rows("SELECT host, name, value, path FROM moz_cookies WHERE \(predicate)")

        return rows.compactMap { row in
            guard row.count == 4, let host = row[0].text, let name = row[1].text else { return nil }
            return BrowserCookie(
                domain: host,
                name: name,
                value: row[2].text ?? "",
                path: row[3].text ?? "/"
            )
        }
    }

    func profiles(applicationURL: URL? = nil) throws(BrowserCookieError) -> [BrowserProfile] {
        let contents: String
        do {
            contents = try String(contentsOf: profilesRoot.appending(path: "profiles.ini"), encoding: .utf8)
        } catch {
            throw BrowserCookieError.classifyRead(error)
        }
        let sections = Self.sections(in: contents)
        let entries = installationProfiles(sections.filter { $0.name.hasPrefix("Profile") }, applicationURL: applicationURL)
        let paths = Set(entries.compactMap { $0.values["Path"] })
        let installDefault = sections.filter { $0.name.hasPrefix("Install") }
            .compactMap { $0.values["Default"] }.first { paths.contains($0) }
        let groups = try profileGroups(for: entries)
        var profiles: [BrowserProfile] = []
        for entry in entries {
            guard let path = entry.values["Path"], !path.isEmpty else { continue }
            let directory = profileDirectory(path, isAbsolute: entry.values["IsRelative"] == "0")
            let group = entry.values["StoreID"].flatMap { groups[$0] } ?? []
            let namedProfile = groups.values.joined().first { $0.directory == directory }
                ?? BrowserProfile(name: entry.values["Name"] ?? directory.lastPathComponent, directory: directory)
            let candidates = group.isEmpty ? [namedProfile] : group
            profiles.append(contentsOf: candidates)
            if path == installDefault || (installDefault == nil && entry.values["Default"] == "1") {
                if let preferred = candidates.first(where: { $0.directory == directory }) {
                    profiles.insert(preferred, at: 0)
                }
            }
        }
        var seen = Set<URL>()
        profiles = profiles.filter { seen.insert($0.directory).inserted }
        guard !profiles.isEmpty else { throw .noProfile }
        return profiles
    }

    private func profileDirectory(_ path: String, isAbsolute: Bool = false) -> URL {
        (isAbsolute || path.hasPrefix("/")
            ? URL(fileURLWithPath: path) : profilesRoot.appending(path: path)).standardizedFileURL
    }

    private func installationProfiles(_ entries: [Section], applicationURL: URL?) -> [Section] {
        guard let applicationURL else { return entries }
        let resources = applicationURL.appending(path: "Contents/Resources").standardizedFileURL
        var matching: [Section] = []
        var unknown: [Section] = []
        for entry in entries {
            guard let path = entry.values["Path"] else { continue }
            let directory = profileDirectory(path, isAbsolute: entry.values["IsRelative"] == "0")
            guard let contents = try? String(contentsOf: directory.appending(path: "compatibility.ini"), encoding: .utf8),
                  let platform = Self.sections(in: contents).first(where: { $0.name == "Compatibility" })?
                    .values["LastPlatformDir"] else {
                unknown.append(entry)
                continue
            }
            if URL(fileURLWithPath: platform).standardizedFileURL.path == resources.path { matching.append(entry) }
        }
        // Prefer profiles used by this installation over unused legacy placeholders.
        return matching.isEmpty ? unknown : matching
    }

    private func profileGroups(for entries: [Section]) throws(BrowserCookieError) -> [String: [BrowserProfile]] {
        var groups: [String: [BrowserProfile]] = [:]
        for storeID in Set(entries.compactMap { $0.values["StoreID"] }) {
            // Store IDs are single filename components, never paths.
            guard !storeID.isEmpty, storeID != ".", storeID != "..", !storeID.contains("/") else { continue }
            do {
                let database = profilesRoot.appending(path: "Profile Groups/\(storeID).sqlite")
                let snapshot = try SQLiteSnapshot(of: database)
                defer { snapshot.close() }
                // A datastore can exist before Firefox has created selectable profiles.
                let tables = try snapshot.rows(
                    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'Profiles' COLLATE NOCASE"
                )
                guard !tables.isEmpty else { continue }
                groups[storeID] = try snapshot.rows("SELECT name, path FROM Profiles ORDER BY name, path").compactMap { row in
                    guard let name = row[0].text, let path = row[1].text, !path.isEmpty else { return nil }
                    let directory = profileDirectory(path)
                    return BrowserProfile(name: name.isEmpty ? directory.lastPathComponent : name, directory: directory)
                }
            } catch {
                if error == .accessDenied { throw error }
                // Older installations and interrupted migrations may only have profiles.ini.
            }
        }
        return groups
    }

    private struct Section {
        var name: String
        var values: [String: String]
    }

    private static func sections(in contents: String) -> [Section] {
        var sections: [Section] = []
        for line in contents.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                sections.append(Section(name: String(trimmed.dropFirst().dropLast()), values: [:]))
            } else if let separator = trimmed.firstIndex(of: "="), !sections.isEmpty {
                let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
                sections[sections.count - 1].values[key] = value
            }
        }
        return sections
    }
}
