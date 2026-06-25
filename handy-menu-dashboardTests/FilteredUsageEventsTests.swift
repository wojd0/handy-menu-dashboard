import Foundation
import Testing
@testable import handy_menu_dashboard

@Suite("Filtered usage events")
struct FilteredUsageEventsTests {
    @Test func decodesUsageEventsFromJSON() throws {
        let json = """
        {
          "totalUsageEventsCount": 2,
          "usageEventsDisplay": [
            { "chargedCents": 12.5 },
            { "chargedCents": 7.25 }
          ]
        }
        """
        let data = Data(json.utf8)

        let response = try JSONDecoder().decode(FilteredUsageEventsResponse.self, from: data)

        #expect(response.totalUsageEventsCount == 2)
        #expect(response.usageEventsDisplay.count == 2)
    }

    @Test func sumChargedCentsRoundsFractionalCents() {
        let events = [
            FilteredUsageEventsResponse.UsageEvent(chargedCents: 10.4),
            FilteredUsageEventsResponse.UsageEvent(chargedCents: 20.6),
        ]

        #expect(UsageMath.sumChargedCents(from: events) == 31)
    }

    @Test func sumChargedCentsTreatsMissingValuesAsZero() {
        let events = [
            FilteredUsageEventsResponse.UsageEvent(chargedCents: 5),
            FilteredUsageEventsResponse.UsageEvent(chargedCents: nil),
            FilteredUsageEventsResponse.UsageEvent(chargedCents: 2.75),
        ]

        #expect(UsageMath.sumChargedCents(from: events) == 8)
    }

    @Test func sumChargedCentsMatchesDecodedPayload() throws {
        let json = """
        {
          "totalUsageEventsCount": 3,
          "usageEventsDisplay": [
            { "chargedCents": 0.4 },
            { "chargedCents": 0.4 },
            { "chargedCents": 0.4 }
          ]
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(FilteredUsageEventsResponse.self, from: data)

        #expect(UsageMath.sumChargedCents(from: response.usageEventsDisplay) == 1)
    }
}
