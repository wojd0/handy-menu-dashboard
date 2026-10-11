import Foundation

nonisolated enum ManualCookieImport {
    static func command(for browser: Browser, filters: [CookieHarvest.DomainMatch], home: URL) -> String {
        switch browser.engine(home: home) {
        case let .gecko(profilesRoot):
            let root = shellPath(profilesRoot, home: home)
            let predicate = CookieHarvest.DomainMatch.sqlWhereClause(
                filters,
                column: "host",
                freshness: GeckoCookieStore.freshness
            )
            return [
                "DB=$(find \(root) -maxdepth 3 -name cookies.sqlite -exec ls -t {} + | head -1)",
                "{ [ -n \"$DB\" ] || { echo 'No cookies.sqlite found. If you see Operation not permitted, " +
                    "give Terminal Full Disk Access.'; false; }; }",
                "cp \"$DB\" \"$TMPDIR/hmd-gecko.sqlite\"",
                "{ cp \"$DB-wal\" \"$TMPDIR/hmd-gecko.sqlite-wal\" 2>/dev/null || true; }",
                "sqlite3 -separator $'\\t' \"$TMPDIR/hmd-gecko.sqlite\" " +
                    "\"SELECT 'C', host, name, value, path FROM moz_cookies WHERE \(predicate)\" | pbcopy",
                "rm -f \"$TMPDIR\"/hmd-gecko.sqlite*"
            ].joined(separator: " && ")

        case let .chromium(userDataRoot, service, account):
            let root = shellPath(userDataRoot, home: home)
            let predicate = CookieHarvest.DomainMatch.sqlWhereClause(
                filters,
                column: "host_key",
                freshness: ChromiumCookieStore.freshness
            )
            return [
                "DIR=\(root)",
                "P=$(/usr/bin/python3 -c \"import json;print(json.load(open('$DIR/Local State'))" +
                    "['profile']['last_used'])\" 2>/dev/null || echo Default)",
                "cp \"$DIR/$P/Cookies\" \"$TMPDIR/hmd-chromium.sqlite\"",
                "{ printf 'K\\t%s\\n' \"$(security find-generic-password -w -s '\(service)' -a '\(account)')\"",
                "printf 'V\\t%s\\n' \"$(sqlite3 \"$TMPDIR/hmd-chromium.sqlite\" " +
                    "\"SELECT value FROM meta WHERE key='version'\")\"",
                "sqlite3 -separator $'\\t' \"$TMPDIR/hmd-chromium.sqlite\" " +
                    "\"SELECT 'C', host_key, name, value, path, hex(encrypted_value) FROM cookies " +
                    "WHERE \(predicate)\"; } | pbcopy",
                "rm -f \"$TMPDIR/hmd-chromium.sqlite\""
            ].joined(separator: " && ")

        case let .webkit(cookieFile):
            return "base64 -i \(shellPath(cookieFile, home: home)) | pbcopy"
        }
    }

    static func parse(_ text: String, browser: Browser, home: URL) throws(BrowserCookieError) -> [BrowserCookie] {
        switch browser.engine(home: home) {
        case .gecko:
            return parseTabbed(text)
        case .chromium:
            return try parseChromium(text)
        case .webkit:
            let compact = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = Data(base64Encoded: compact, options: .ignoreUnknownCharacters) else {
                throw .unreadable
            }
            return try SafariBinaryCookies.parse(data)
        }
    }

    private static func parseTabbed(_ text: String) -> [BrowserCookie] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let columns = line.components(separatedBy: "\t")
            guard columns.count >= 5, columns[0] == "C" else { return nil }
            return BrowserCookie(domain: columns[1], name: columns[2], value: columns[3], path: columns[4])
        }
    }

    private struct EncryptedRow {
        let host: String
        let name: String
        let value: String
        let path: String
        let encrypted: Data
    }

    private static func parseChromium(_ text: String) throws(BrowserCookieError) -> [BrowserCookie] {
        var password: String?
        var version = 0
        var rows: [EncryptedRow] = []

        for line in text.split(whereSeparator: \.isNewline) {
            let columns = line.components(separatedBy: "\t")
            switch columns.first {
            case "K" where columns.count >= 2:
                password = columns[1]
            case "V" where columns.count >= 2:
                version = Int(columns[1]) ?? 0
            case "C" where columns.count >= 6:
                let encrypted = columns[5].isEmpty ? Data() : dataFromHex(columns[5]) ?? Data()
                rows.append(EncryptedRow(host: columns[1], name: columns[2], value: columns[3], path: columns[4], encrypted: encrypted))
            default:
                continue
            }
        }

        guard let password else { throw .keyUnavailable }
        let cipher = ChromiumCookieCipher(key: ChromiumCookieCipher.deriveKey(fromPassword: password))

        return rows.compactMap { row in
            let value: String
            if !row.value.isEmpty {
                value = row.value
            } else if let decrypted = cipher.decrypt(row.encrypted, host: row.host, metaVersion: version) {
                value = decrypted
            } else {
                return nil
            }
            return BrowserCookie(domain: row.host, name: row.name, value: value, path: row.path)
        }
    }

    private static func shellPath(_ url: URL, home: URL) -> String {
        let path = url.path
        let homePath = home.path
        let escaped: String
        if path.hasPrefix(homePath) {
            escaped = "$HOME" + path.dropFirst(homePath.count)
        } else {
            escaped = path
        }
        return "\"" + escaped.replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func dataFromHex(_ hex: String) -> Data? {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}
