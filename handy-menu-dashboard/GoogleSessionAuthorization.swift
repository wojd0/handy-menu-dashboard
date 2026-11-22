import CryptoKit
import Foundation

enum GoogleSessionAuthorization {
    static let schemes: [(scheme: String, cookie: String)] = [
        ("SAPISIDHASH", "SAPISID"),
        ("SAPISID1PHASH", "__Secure-1PAPISID"),
        ("SAPISID3PHASH", "__Secure-3PAPISID")
    ]

    static func header(cookieHeader: String, origin: String, timestamp: Int) -> String? {
        let parts = schemes.compactMap { scheme, cookie -> String? in
            guard let value = CookieHeader.value(named: cookie, in: cookieHeader), !value.isEmpty else { return nil }
            return "\(scheme) \(timestamp)_\(hash(timestamp: timestamp, value: value, origin: origin))"
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ")
    }

    static func hash(timestamp: Int, value: String, origin: String) -> String {
        Insecure.SHA1.hash(data: Data("\(timestamp) \(value) \(origin)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func sentCookies(_ cookies: [HTTPCookie], to host: String) -> [HTTPCookie] {
        cookies.filter { cookie in
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return host == domain || host.hasSuffix("." + domain)
        }
    }
}
