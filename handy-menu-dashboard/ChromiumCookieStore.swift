import Foundation
import LocalAuthentication
import Security

nonisolated struct ChromiumCookieStore {
    static let freshness = "(expires_utc = 0 OR expires_utc > (CAST(strftime('%s', 'now') AS INTEGER) + 11644473600) * 1000000)"

    let userDataRoot: URL
    let safeStorageService: String
    let safeStorageAccount: String
    let safeStoragePassword: () throws(BrowserCookieError) -> String

    init(
        userDataRoot: URL,
        safeStorageService: String,
        safeStorageAccount: String,
        allowUserInteraction: Bool = true,
        safeStoragePassword: (() throws(BrowserCookieError) -> String)? = nil
    ) {
        self.userDataRoot = userDataRoot
        self.safeStorageService = safeStorageService
        self.safeStorageAccount = safeStorageAccount
        if let safeStoragePassword {
            self.safeStoragePassword = safeStoragePassword
        } else {
            let service = safeStorageService
            let account = safeStorageAccount
            self.safeStoragePassword = { () throws(BrowserCookieError) -> String in
                try Self.keychainPassword(service: service, account: account, allowUserInteraction: allowUserInteraction)
            }
        }
    }

    func cookies(
        matching filters: [CookieHarvest.DomainMatch], profile: URL? = nil
    ) throws(BrowserCookieError) -> [BrowserCookie] {
        let directory: URL
        if let profile {
            directory = profile
        } else {
            directory = try profileDirectory()
        }
        let cookiesFile = directory.appending(path: "Cookies")

        let snapshot = try SQLiteSnapshot(of: cookiesFile)
        defer { snapshot.close() }

        let metaVersion = try snapshot.rows("SELECT value FROM meta WHERE key = 'version'")
            .first?.first?.text.flatMap { Int($0) } ?? 0

        let predicate = CookieHarvest.DomainMatch.sqlWhereClause(filters, column: "host_key", freshness: Self.freshness)
        let rows = try snapshot.rows(
            "SELECT host_key, name, value, path, encrypted_value FROM cookies WHERE \(predicate)"
        )

        let password = try safeStoragePassword()
        let cipher = ChromiumCookieCipher(key: ChromiumCookieCipher.deriveKey(fromPassword: password))

        return rows.compactMap { row in
            guard row.count == 5, let host = row[0].text, let name = row[1].text else { return nil }
            let plaintextValue = row[2].text ?? ""
            let value: String
            if !plaintextValue.isEmpty {
                value = plaintextValue
            } else if let encrypted = row[4].blob,
                      let decrypted = cipher.decrypt(encrypted, host: host, metaVersion: metaVersion) {
                value = decrypted
            } else {
                return nil
            }
            return BrowserCookie(domain: host, name: name, value: value, path: row[3].text ?? "/")
        }
    }

    private func profileDirectory() throws(BrowserCookieError) -> URL {
        let localState = userDataRoot.appending(path: "Local State")
        var profile = "Default"
        if let data = try? Data(contentsOf: localState),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let profileInfo = root["profile"] as? [String: Any],
           let lastUsed = profileInfo["last_used"] as? String,
           !lastUsed.isEmpty {
            profile = lastUsed
        }

        let directory = userDataRoot.appending(path: profile)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw .noProfile
        }
        return directory
    }

    static func profiles(at root: URL) throws(BrowserCookieError) -> [BrowserProfile] {
        let directories: [URL]
        do {
            directories = try FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            ).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        } catch {
            let error = error as NSError
            if error.code == NSFileReadNoPermissionError { throw .accessDenied }
            if error.code == NSFileReadNoSuchFileError { throw .noProfile }
            throw .unreadable
        }

        let data = try? Data(contentsOf: root.appending(path: "Local State"))
        let state = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let profileInfo = state?["profile"] as? [String: Any]
        let names = profileInfo?["info_cache"] as? [String: [String: Any]] ?? [:]
        let lastUsed = profileInfo?["last_used"] as? String ?? "Default"
        let profiles = directories.compactMap { directory -> BrowserProfile? in
            let folder = directory.lastPathComponent
            guard folder == "Default" || folder.hasPrefix("Profile ") || names[folder] != nil else { return nil }
            let name = names[folder]?["name"] as? String
            return BrowserProfile(name: name.flatMap { $0.isEmpty ? nil : $0 } ?? folder, directory: directory)
        }.sorted { lhs, rhs in
            let lhsWasLastUsed = lhs.directory.lastPathComponent == lastUsed
            let rhsWasLastUsed = rhs.directory.lastPathComponent == lastUsed
            if lhsWasLastUsed != rhsWasLastUsed { return lhsWasLastUsed }
            let comparison = lhs.name.localizedStandardCompare(rhs.name)
            return comparison == .orderedSame
                ? lhs.directory.path < rhs.directory.path : comparison == .orderedAscending
        }
        guard !profiles.isEmpty else { throw .noProfile }
        return profiles
    }

    private static func keychainPassword(
        service: String, account: String, allowUserInteraction: Bool
    ) throws(BrowserCookieError) -> String {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if !allowUserInteraction {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let password = String(data: data, encoding: .utf8) else {
                throw .keyUnavailable
            }
            return password
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            throw .keyDenied
        default:
            throw .keyUnavailable
        }
    }
}
