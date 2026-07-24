import Testing
@testable import handy_menu_dashboard

@Suite("Menu bar layout")
struct MenuBarLayoutTests {
    @Test func returnsNoColumnsForNoProviders() {
        #expect(MenuBarLayout.columns(from: [String]()).isEmpty)
    }

    @Test func keepsOneOrTwoProvidersInOneColumn() {
        #expect(MenuBarLayout.columns(from: ["Cursor"]) == [["Cursor"]])
        #expect(MenuBarLayout.columns(from: ["Cursor", "Claude"]) == [["Cursor", "Claude"]])
    }

    @Test func putsFirstProviderAloneForThreeProviders() {
        let providers = ["Cursor", "Claude", "ChatGPT"]

        #expect(MenuBarLayout.columns(from: providers) == [
            ["Cursor"],
            ["Claude", "ChatGPT"]
        ])
    }

    @Test func splitsFourProvidersIntoPairs() {
        let providers = ["Cursor", "Copilot", "Claude", "ChatGPT"]

        #expect(MenuBarLayout.columns(from: providers) == [
            ["Cursor", "Copilot"],
            ["Claude", "ChatGPT"]
        ])
    }

    @Test func keepsFirstProviderAloneForAnyOddProviderCount() {
        let providers = ["First", "Second", "Third", "Fourth", "Fifth"]

        #expect(MenuBarLayout.columns(from: providers) == [
            ["First"],
            ["Second", "Third"],
            ["Fourth", "Fifth"]
        ])
    }
}
