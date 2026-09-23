import Testing
@testable import handy_menu_dashboard

@Suite("App runtime")
struct AppRuntimeTests {
    @Test func sharedSchemeEnablesTestHostMode() {
        #expect(AppRuntime.isTestHost())
    }

    @Test func testHostModeIsExplicitlyEnabled() {
        let environment = [AppRuntime.testHostEnvironmentKey: "1"]

        #expect(AppRuntime.isTestHost(environment: environment))
    }

    @Test func normalLaunchDoesNotUseTestHostMode() {
        #expect(!AppRuntime.isTestHost(environment: [:]))
    }

    @Test func otherEnvironmentValuesDoNotEnableTestHostMode() {
        let environment = [AppRuntime.testHostEnvironmentKey: "true"]

        #expect(!AppRuntime.isTestHost(environment: environment))
    }
}
