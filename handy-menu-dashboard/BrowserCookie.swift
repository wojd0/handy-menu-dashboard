import Foundation

nonisolated struct BrowserCookie: Sendable, Equatable {
    var domain: String
    var name: String
    var value: String
    var path: String

    init(domain: String, name: String, value: String, path: String = "/") {
        self.domain = domain
        self.name = name
        self.value = value
        self.path = path
    }

    var httpCookie: HTTPCookie? {
        HTTPCookie(properties: [
            .domain: domain,
            .name: name,
            .value: value,
            .path: path.isEmpty ? "/" : path
        ])
    }
}

nonisolated enum BrowserCookieError: Error, Equatable {
    case notInstalled
    case noProfile
    case accessDenied
    case keyUnavailable
    case keyDenied
    case unreadable
}

extension Array where Element == BrowserCookie {
    var httpCookies: [HTTPCookie] {
        compactMap(\.httpCookie)
    }
}
