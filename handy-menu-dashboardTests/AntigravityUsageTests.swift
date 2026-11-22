import Foundation
import Testing
@testable import handy_menu_dashboard

@Suite("Antigravity usage")
struct AntigravityUsageTests {
    private static let quotaSummary = """
        [[[null,[[[["gemini-weekly","Weekly Limit Remaining","weekly",0.75798696,null,["1795862809"],\
        "You have used some of your weekly limit, it will fully refresh in 5 days, 22 hours."],\
        ["gemini-5h","Five Hour Limit Remaining","5h",0.9975905,null,["1795356189"],\
        "You have used some of your 5-hour limit, it will fully refresh in 2 hours, 11 minutes."]],\
        "Gemini Models","Models within this group: Gemini 4 Neon, Gemini 4 Hydrogen, Gemini 3.8 Flash"],\
        [[["3p-weekly","Weekly Limit Remaining","weekly",1,null,["1795953090"]],\
        ["3p-5h","Five Hour Limit Remaining","5h",1,null,["1795366290"]]],\
        "Claude and GPT models","Models within this group: Claude Opus 5.5, Claude Sonnet 5.5, GPT-OSS 120B"],\
        [[["gemini-argon-wtu-weekly","Gemini 4 Argon Weekly Limit","weekly",1,null,["1795953090"]]],\
        "Gemini 4 Argon","For paid Pro plans, Argon quota is separate."]],\
        "Within each group, models share a weekly limit and a 5-hour limit."]]]
        """

    private let cookies = "SID=sid; SAPISID=sapisid; __Secure-1PAPISID=first; __Secure-3PAPISID=third"

    @Test func decodesTheQuotaSummaryGroupsAndWindows() throws {
        let response = try decode(Self.quotaSummary)

        #expect(response.groups.map(\.name) == ["Gemini Models", "Claude and GPT models", "Gemini 4 Argon"])
        let weekly = try #require(response.groups.first?.windows.first)
        #expect(weekly.id == "gemini-weekly")
        #expect(weekly.period == "weekly")
        #expect(weekly.remainingFraction == 0.75798696)
        #expect(weekly.resetsAt == Date(timeIntervalSince1970: 1_795_862_809))
        #expect(response.groups[2].windows.map(\.id) == ["gemini-argon-wtu-weekly"])
    }

    @Test func anOmittedRemainingFractionMeansTheWindowIsUsedUp() throws {
        let response = try decode(#"[[[null,[[[["3p-5h","Five Hour Limit Remaining","5h",null,null,["1"]]],"Group"]]]]]"#)

        #expect(response.groups.first?.windows.first?.percentUsed == 100)
    }

    @Test func anEmptySummaryDecodesToNoGroups() throws {
        #expect(try decode("[]").groups.isEmpty)
    }

    @Test func authorizationSignsEachGoogleSessionCookieWithTheOrigin() throws {
        let header = try #require(GoogleSessionAuthorization.header(
            cookieHeader: cookies,
            origin: "https://antigravity.google.com",
            timestamp: 1_700_000_000
        ))

        let parts = header.split(separator: " ").map(String.init)
        #expect(parts.count == 6)
        #expect(parts[0] == "SAPISIDHASH")
        #expect(parts[2] == "SAPISID1PHASH")
        #expect(parts[4] == "SAPISID3PHASH")
        #expect(parts[1] == "1700000000_" + GoogleSessionAuthorization.hash(
            timestamp: 1_700_000_000, value: "sapisid", origin: "https://antigravity.google.com"
        ))
    }

    @Test func authorizationHashIsTheSHA1OfTimestampValueAndOrigin() {
        let hash = GoogleSessionAuthorization.hash(timestamp: 1_700_000_000, value: "sapisid", origin: "https://o.test")

        #expect(hash == "aa221dd6a46b9e265ffa50ca0a0992894095f339")
    }

    @Test func authorizationNeedsASAPISIDCookie() {
        #expect(GoogleSessionAuthorization.header(cookieHeader: "SID=sid", origin: "https://o", timestamp: 1) == nil)
    }

    @Test func onlyCookiesSentToTheQuotaHostAreKept() {
        let kept = GoogleSessionAuthorization.sentCookies(
            [
                cookie("SAPISID", domain: ".google.com"),
                cookie("OSID", domain: "mail.google.com"),
                cookie("HOST", domain: "aicode.clients6.google.com")
            ],
            to: "aicode.clients6.google.com"
        )

        #expect(kept.map(\.name) == ["SAPISID", "HOST"])
    }

    @Test func refreshPostsASignedRequestAndAppliesTheGroups() async throws {
        let recorder = RequestRecorder()
        let service = makeService(cookies: cookies) { request in
            recorder.requests.append(request)
            return try httpResponse(for: request, data: Data(Self.quotaSummary.utf8))
        }

        await service.refresh()

        let request = try #require(recorder.requests.first)
        #expect(request.url?.absoluteString == AntigravityService.quotaURL)
        #expect(request.httpMethod == "POST")
        #expect(request.httpBody == Data("[]".utf8))
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json+protobuf")
        #expect(request.value(forHTTPHeaderField: "Origin") == "https://antigravity.google.com")
        #expect(request.value(forHTTPHeaderField: "X-Goog-Api-Key") == AntigravityService.apiKey)
        #expect(request.value(forHTTPHeaderField: "Cookie") == cookies)
        #expect(request.value(forHTTPHeaderField: "Authorization") == GoogleSessionAuthorization.header(
            cookieHeader: cookies, origin: "https://antigravity.google.com", timestamp: 1_795_348_289
        ))
        #expect(service.groups.count == 3)
        #expect(service.error == nil)
    }

    @Test func theMenuBarReportsTheMostUsedWindow() async {
        let service = makeService(cookies: cookies) { try httpResponse(for: $0, data: Data(Self.quotaSummary.utf8)) }
        service.isEnabled = true

        await service.refresh()

        #expect(service.menuBarWindow?.id == "gemini-weekly")
        #expect(service.menuBarFragment(displayMode: .percentUsed) == "24%")
        #expect(service.menuBarFragment(displayMode: .percentRemaining) == "76%")
        #expect(service.menuBarFragment(displayMode: .monetary) == "24%")
    }

    @Test func everyReportedGroupIsAUsagePool() async {
        let service = makeService(cookies: cookies) { try httpResponse(for: $0, data: Data(Self.quotaSummary.utf8)) }

        await service.refresh()

        #expect(service.availableUsagePools.map(\.label) == [
            "Most Used", "Gemini Models", "Claude and GPT models", "Gemini 4 Argon"
        ])
        #expect(service.availableUsagePools[3] == .group(name: "Gemini 4 Argon", windowIDs: ["gemini-argon-wtu-weekly"]))
    }

    @Test func theChosenGroupDrivesTheMenuBar() async {
        let preferences = InMemoryPreferenceStore()
        let service = makeService(cookies: cookies, preferences: preferences) {
            try httpResponse(for: $0, data: Data(Self.quotaSummary.utf8))
        }
        service.isEnabled = true
        await service.refresh()

        service.usagePool = service.availableUsagePools[2]

        #expect(service.resolvedUsagePool.label == "Claude and GPT models")
        #expect(service.menuBarWindow?.id == "3p-5h")
        #expect(service.menuBarFragment(displayMode: .percentUsed) == "0%")
        #expect(ProviderPreferences.antigravityUsagePool(in: preferences) == service.availableUsagePools[2])
    }

    @Test func aRenamedGroupKeepsTheChoiceThroughItsWindowIDs() async {
        let renamed = Self.quotaSummary.replacingOccurrences(of: "\"Gemini Models\"", with: "\"Gemini 4 Models\"")
        let service = makeService(cookies: cookies) { try httpResponse(for: $0, data: Data(renamed.utf8)) }
        service.usagePool = .group(name: "Gemini Models", windowIDs: ["gemini-weekly", "gemini-5h"])

        await service.refresh()

        #expect(service.resolvedUsagePool == .group(name: "Gemini 4 Models", windowIDs: ["gemini-5h", "gemini-weekly"]))
    }

    @Test func aGroupWithNewWindowIDsKeepsTheChoiceThroughItsName() async {
        let service = makeService(cookies: cookies) { try httpResponse(for: $0, data: Data(Self.quotaSummary.utf8)) }
        service.usagePool = .group(name: "Gemini 4 Argon", windowIDs: ["gemini-argon-weekly"])

        await service.refresh()

        #expect(service.resolvedUsagePool.label == "Gemini 4 Argon")
        #expect(service.menuBarWindow?.id == "gemini-argon-wtu-weekly")
    }

    @Test func aRemovedGroupFallsBackToMostUsedAndKeepsTheSavedChoice() async {
        let removed = AntigravityUsagePool.group(name: "Gemini 5 Krypton", windowIDs: ["krypton-weekly"])
        let service = makeService(cookies: cookies) { try httpResponse(for: $0, data: Data(Self.quotaSummary.utf8)) }
        service.isEnabled = true
        service.usagePool = removed

        await service.refresh()

        #expect(service.resolvedUsagePool == .mostUsed)
        #expect(service.menuBarFragment(displayMode: .percentUsed) == "24%")
        #expect(service.usagePool == removed)
    }

    @Test func timeRangesComeFromThePeriodsOfTheChosenPool() async {
        let service = makeService(cookies: cookies) { try httpResponse(for: $0, data: Data(Self.quotaSummary.utf8)) }
        await service.refresh()

        #expect(service.availablePoolRanges.map(\.label) == ["Most Used", "Session (5h)", "Weekly"])

        service.usagePool = service.availableUsagePools[3]

        #expect(service.availablePoolRanges == [.mostUsed, .period("weekly")])
    }

    @Test func theChosenTimeRangeNarrowsTheMenuBarWindow() async {
        let preferences = InMemoryPreferenceStore()
        let service = makeService(cookies: cookies, preferences: preferences) {
            try httpResponse(for: $0, data: Data(Self.quotaSummary.utf8))
        }
        service.isEnabled = true
        await service.refresh()

        service.poolRange = .period("5h")

        #expect(service.menuBarWindow?.id == "gemini-5h")
        #expect(service.menuBarFragment(displayMode: .percentUsed) == "0%")
        #expect(ProviderPreferences.antigravityPoolRange(in: preferences) == .period("5h"))

        service.usagePool = service.availableUsagePools[2]

        #expect(service.menuBarWindow?.id == "3p-5h")
    }

    @Test func aTimeRangeTheGroupDoesNotReportFallsBackToMostUsed() async {
        let service = makeService(cookies: cookies) { try httpResponse(for: $0, data: Data(Self.quotaSummary.utf8)) }
        await service.refresh()
        service.usagePool = service.availableUsagePools[3]
        service.poolRange = .period("5h")

        #expect(service.resolvedPoolRange == .mostUsed)
        #expect(service.menuBarWindow?.id == "gemini-argon-wtu-weekly")
        #expect(service.poolRange == .period("5h"))
    }

    @Test func anUnknownPeriodIsLabelledFromItsName() {
        #expect(AntigravityPoolRange.period("daily").label == "Daily")
    }

    @Test func theServiceStartsFromTheStoredUsagePool() {
        let preferences = InMemoryPreferenceStore()
        let stored = AntigravityUsagePool.group(name: "Gemini 4 Argon", windowIDs: ["gemini-argon-wtu-weekly"])
        ProviderPreferences.setAntigravityUsagePool(stored, in: preferences)

        let service = makeService(cookies: nil, preferences: preferences) { _ in throw NetworkFailure() }

        #expect(service.usagePool == stored)
        #expect(service.poolRange == .mostUsed)
    }

    @Test func windowsAreTitledByTheirPeriod() async {
        let service = makeService(cookies: cookies) { try httpResponse(for: $0, data: Data(Self.quotaSummary.utf8)) }

        await service.refresh()

        #expect(service.groups.first?.windows.map(\.title) == ["Session (5h)", "Weekly"])
    }

    @Test func everyWindowIsAUsageBarUnderItsGroup() async {
        let service = makeService(cookies: cookies) { try httpResponse(for: $0, data: Data(Self.quotaSummary.utf8)) }

        await service.refresh()

        #expect(service.usageBars.prefix(2) == [
            UsageBar(id: "gemini-5h", title: "Session (5h)", section: "Gemini Models"),
            UsageBar(id: "gemini-weekly", title: "Weekly", section: "Gemini Models")
        ])
        #expect(service.usageBars.count == 5)

        service.hiddenUsageBars = Set(service.usageBars.map(\.id))
        #expect(service.showsAnyUsageBar == false)
    }

    @Test func browserCookiesAreValidatedBeforeTheyArePersisted() async {
        let keychain = InMemoryKeychainStore()
        let service = AntigravityService(
            keychain: keychain,
            dataLoader: { try httpResponse(for: $0, status: 401, data: Data()) },
            autoRefresh: false,
            preferences: InMemoryPreferenceStore()
        )

        let outcome = await service.adoptBrowserCookies([cookie("SAPISID", domain: ".google.com")])

        #expect(outcome == .staleSession)
        #expect(keychain.loadString(key: .antigravityCookies) == nil)
        #expect(service.isAuthenticated == false)
    }

    @Test func aValidBrowserSessionIsPersistedAndEnablesTheProvider() async {
        let keychain = InMemoryKeychainStore()
        let service = AntigravityService(
            keychain: keychain,
            dataLoader: { try httpResponse(for: $0, data: Data(Self.quotaSummary.utf8)) },
            autoRefresh: false,
            preferences: InMemoryPreferenceStore()
        )

        let outcome = await service.adoptBrowserCookies([
            cookie("SAPISID", domain: ".google.com"),
            cookie("OSID", domain: "mail.google.com")
        ])

        #expect(outcome == .authenticated)
        #expect(keychain.loadString(key: .antigravityCookies) == "SAPISID=v")
        #expect(service.isEnabled)
        #expect(service.groups.count == 3)
    }

    @Test func browserCookiesWithoutAGoogleSessionAreRejected() async {
        let service = makeService(cookies: nil) { _ in throw NetworkFailure() }

        let outcome = await service.adoptBrowserCookies([cookie("NID", domain: ".google.com")])

        #expect(outcome == .failure("No Google session found"))
    }

    @Test func anExpiredSessionDiscardsTheCredential() async {
        let keychain = InMemoryKeychainStore()
        keychain.saveString(key: .antigravityCookies, value: cookies)
        let service = AntigravityService(
            keychain: keychain,
            dataLoader: { try httpResponse(for: $0, status: 401, data: Data()) },
            autoRefresh: false,
            preferences: InMemoryPreferenceStore()
        )

        await service.refresh()

        #expect(service.isAuthenticated == false)
        #expect(keychain.loadString(key: .antigravityCookies) == nil)
    }

    @Test func aMalformedPayloadIsAnInvalidResponse() async {
        let service = makeService(cookies: cookies) { try httpResponse(for: $0, data: Data("{}".utf8)) }

        await service.refresh()

        #expect(service.error == "Invalid response from Antigravity")
    }

    private func decode(_ text: String) throws -> AntigravityQuotaResponse {
        try JSONDecoder().decode(AntigravityQuotaResponse.self, from: Data(text.utf8))
    }

    private func makeService(
        cookies: String?,
        preferences: InMemoryPreferenceStore = InMemoryPreferenceStore(),
        dataLoader: @escaping UsageDataLoader
    ) -> AntigravityService {
        let keychain = InMemoryKeychainStore()
        if let cookies {
            keychain.saveString(key: .antigravityCookies, value: cookies)
        }
        return AntigravityService(
            keychain: keychain,
            dataLoader: dataLoader,
            autoRefresh: false,
            preferences: preferences,
            now: { Date(timeIntervalSince1970: 1_795_348_289) }
        )
    }

    private func cookie(_ name: String, value: String = "v", domain: String) -> HTTPCookie {
        HTTPCookie(properties: [.domain: domain, .path: "/", .name: name, .value: value])!
    }
}

private final class RequestRecorder: @unchecked Sendable {
    var requests: [URLRequest] = []
}
