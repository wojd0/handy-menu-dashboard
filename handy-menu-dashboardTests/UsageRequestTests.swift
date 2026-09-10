import Foundation
import Testing
@testable import handy_menu_dashboard

@Suite("Usage request")
struct UsageRequestTests {
    @Test func everyRequestCarriesTheSafariUserAgentAndCookie() throws {
        let request = try UsageRequest(url: "https://cursor.com/api/usage-summary", cookieHeader: "s=1").urlRequest()

        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == BrowserIdentity.userAgent)
        #expect(request.value(forHTTPHeaderField: "Cookie") == "s=1")
    }

    @Test func customHeadersAreApplied() throws {
        let request = try UsageRequest(
            url: "https://chatgpt.com/backend-api/usage",
            cookieHeader: "s=1",
            headers: ["Authorization": "Bearer token", "ChatGPT-Account-ID": "acct"]
        ).urlRequest()

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-ID") == "acct")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == BrowserIdentity.userAgent)
    }

    @Test func anUnbuildableURLIsRejectedRatherThanForceUnwrapped() {
        let request = UsageRequest(url: "", cookieHeader: "s=1")

        #expect(throws: UsageFailure.Kind.invalidResponse) {
            try request.urlRequest()
        }
    }
}

@Suite("HTTP outcome")
struct HTTPOutcomeTests {
    @Test func standardPolicyTreatsOnlyUnauthorizedAndForbiddenAsExpired() {
        #expect(classify(200) == .ok)
        #expect(classify(401) == .authExpired)
        #expect(classify(403) == .authExpired)
        #expect(classify(404) == .httpError(404))
        #expect(classify(429) == .httpError(429))
    }

    @Test func githubPolicyAlsoTreatsNotFoundAsExpired() {
        #expect(classify(404, policy: .github) == .authExpired)
        #expect(classify(200, policy: .github) == .ok)
        #expect(classify(500, policy: .github) == .httpError(500))
    }

    @Test func githubPolicyTreatsARedirectToLoginAsExpired() {
        let outcome = classify(200, url: "https://github.com/login", policy: .github)

        #expect(outcome == .authExpired)
    }

    @Test func standardPolicyIgnoresTheLoginPath() {
        let outcome = classify(200, url: "https://cursor.com/login")

        #expect(outcome == .ok)
    }

    @Test func aNonHTTPResponseIsInvalid() {
        let response = URLResponse(
            url: URL(string: "https://cursor.com")!,
            mimeType: nil,
            expectedContentLength: 0,
            textEncodingName: nil
        )

        #expect(HTTPOutcome.classify(response: response, policy: .standard) == .invalidResponse)
        #expect(HTTPOutcome.classify(response: nil, policy: .standard) == .invalidResponse)
    }

    private func classify(
        _ status: Int,
        url: String = "https://cursor.com/api/usage-summary",
        policy: AuthExpiredPolicy = .standard
    ) -> HTTPOutcome {
        let response = HTTPURLResponse(
            url: URL(string: url)!,
            statusCode: status,
            httpVersion: "HTTP/2",
            headerFields: nil
        )!
        return HTTPOutcome.classify(response: response, policy: policy)
    }
}

@Suite("Cookie header")
struct CookieHeaderTests {
    @Test func headerJoinsNameValuePairs() {
        let cookies = [makeCookie(name: "sessionKey", value: "sk"), makeCookie(name: "lastActiveOrg", value: "org")]

        #expect(CookieHeader.header(from: cookies) == "sessionKey=sk; lastActiveOrg=org")
    }

    @Test func valueIsFoundRegardlessOfSpacingAfterTheSeparator() {
        #expect(CookieHeader.value(named: "lastActiveOrg", in: "sessionKey=sk; lastActiveOrg=org") == "org")
        #expect(CookieHeader.value(named: "lastActiveOrg", in: "sessionKey=sk;lastActiveOrg=org") == "org")
        #expect(CookieHeader.value(named: "lastActiveOrg", in: "lastActiveOrg=org") == "org")
    }

    @Test func valuesContainingSeparatorsAreKeptWhole() {
        #expect(CookieHeader.value(named: "token", in: "token=a=b=c; other=1") == "a=b=c")
    }

    @Test func missingNameReturnsNil() {
        #expect(CookieHeader.value(named: "absent", in: "sessionKey=sk") == nil)
    }

    private func makeCookie(name: String, value: String) -> HTTPCookie {
        HTTPCookie(properties: [
            .domain: ".claude.ai",
            .path: "/",
            .name: name,
            .value: value
        ])!
    }
}
