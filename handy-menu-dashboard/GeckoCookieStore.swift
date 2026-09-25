import Foundation

nonisolated struct GeckoCookieStore {
    static let freshness = "(expiry = 0 OR expiry > CAST(strftime('%s', 'now') AS INTEGER))"

    let profilesRoot: URL

    func cookies(matching filters: [CookieHarvest.DomainMatch]) throws(BrowserCookieError) -> [BrowserCookie] {
        let profile = try defaultProfile()
        let database = profile.appending(path: "cookies.sqlite")

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

    private func defaultProfile() throws(BrowserCookieError) -> URL {
        let iniURL = profilesRoot.appending(path: "profiles.ini")
        guard let contents = try? String(contentsOf: iniURL, encoding: .utf8) else {
            throw .noProfile
        }

        let sections = Self.sections(in: contents)

        if let installDefault = sections
            .first(where: { $0.name.hasPrefix("Install") })?
            .values["Default"] {
            return profilesRoot.appending(path: installDefault)
        }

        let profiles = sections.filter { $0.name.hasPrefix("Profile") }
        if let flagged = profiles.first(where: { $0.values["Default"] == "1" }),
           let path = flagged.values["Path"] {
            return profilesRoot.appending(path: path)
        }
        if let first = profiles.first, let path = first.values["Path"] {
            return profilesRoot.appending(path: path)
        }

        throw .noProfile
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
                let key = String(trimmed[..<separator])
                let value = String(trimmed[trimmed.index(after: separator)...])
                sections[sections.count - 1].values[key] = value
            }
        }
        return sections
    }
}
