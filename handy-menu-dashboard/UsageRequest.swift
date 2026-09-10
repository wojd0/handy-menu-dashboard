import Foundation

enum BrowserIdentity {
    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/18.5 Safari/605.1.15"
}

struct AuthExpiredPolicy: Equatable {
    var statuses: Set<Int>
    var loginPath: String?

    static let standard = AuthExpiredPolicy(statuses: [401, 403], loginPath: nil)
    static let github = AuthExpiredPolicy(statuses: [401, 403, 404], loginPath: "/login")
}

enum HTTPOutcome: Equatable {
    case ok
    case authExpired
    case httpError(Int)
    case invalidResponse

    static func classify(response: URLResponse?, policy: AuthExpiredPolicy) -> HTTPOutcome {
        guard let http = response as? HTTPURLResponse else {
            return .invalidResponse
        }
        if policy.statuses.contains(http.statusCode) {
            return .authExpired
        }
        if let loginPath = policy.loginPath, http.url?.path == loginPath {
            return .authExpired
        }
        guard http.statusCode == 200 else {
            return .httpError(http.statusCode)
        }
        return .ok
    }
}

struct UsageRequest: Equatable {
    var url: String
    var cookieHeader: String
    var headers: [String: String] = [:]

    func urlRequest() throws(UsageFailure.Kind) -> URLRequest {
        guard let requestURL = URL(string: url) else {
            throw .invalidResponse
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue(BrowserIdentity.userAgent, forHTTPHeaderField: "User-Agent")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }
}

struct UsageTransport {
    private let dataLoader: UsageDataLoader
    private let policy: AuthExpiredPolicy

    init(dataLoader: @escaping UsageDataLoader, policy: AuthExpiredPolicy = .standard) {
        self.dataLoader = dataLoader
        self.policy = policy
    }

    func data(for request: UsageRequest) async throws(UsageFailure.Kind) -> Data {
        let urlRequest = try request.urlRequest()

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await dataLoader(urlRequest)
        } catch {
            throw .network
        }

        switch HTTPOutcome.classify(response: response, policy: policy) {
        case .ok:
            return data
        case .authExpired:
            throw .authExpired
        case .httpError(let code):
            throw .httpError(code)
        case .invalidResponse:
            throw .invalidResponse
        }
    }
}

enum CookieHeader {
    static func header(from cookies: [HTTPCookie]) -> String {
        cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    static func value(named name: String, in header: String) -> String? {
        for pair in header.components(separatedBy: ";") {
            let parts = pair.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
            if parts.count == 2, parts[0] == name {
                return String(parts[1])
            }
        }
        return nil
    }
}
