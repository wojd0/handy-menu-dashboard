import Foundation
import Testing
@testable import handy_menu_dashboard

@Suite("Cursor usage summary")
struct CursorUsageSummaryTests {
    @Test func decodesUsageSummaryFromJSON() throws {
        let json = """
        {
          "billingCycleStart": "2026-07-01T00:00:00.000Z",
          "billingCycleEnd": "2026-08-01T00:00:00.000Z",
          "isUnlimited": false,
          "individualUsage": {
            "overall": {
              "enabled": true,
              "used": 5000,
              "limit": 160000,
              "remaining": 155000
            }
          }
        }
        """
        let data = Data(json.utf8)

        let response = try JSONDecoder().decode(CursorUsageSummaryResponse.self, from: data)

        #expect(response.isUnlimited == false)
        #expect(response.individualUsage?.overall?.used == 5000)
        #expect(response.individualUsage?.overall?.limit == 160000)
        #expect(response.individualUsage?.overall?.remaining == 155000)
    }

    @Test func decodesNullLimitAsNil() throws {
        let json = """
        {
          "isUnlimited": true,
          "individualUsage": {
            "overall": {
              "enabled": true,
              "used": 0,
              "limit": null,
              "remaining": null
            }
          }
        }
        """
        let data = Data(json.utf8)

        let response = try JSONDecoder().decode(CursorUsageSummaryResponse.self, from: data)

        #expect(response.isUnlimited == true)
        #expect(response.individualUsage?.overall?.limit == nil)
    }
}
