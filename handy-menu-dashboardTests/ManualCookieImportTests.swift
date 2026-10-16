import Foundation
import Testing
@testable import handy_menu_dashboard

@Suite("Manual cookie import")
struct ManualCookieImportTests {
    private let home = URL(fileURLWithPath: "/Users/tester")

    @Test func geckoCommandTargetsMozCookiesAndPipesToPasteboard() {
        let command = ManualCookieImport.command(
            for: .firefox,
            filters: [.contains("claude.ai")],
            home: home
        )

        #expect(command.contains("moz_cookies"))
        #expect(command.contains("claude.ai"))
        #expect(command.contains("| pbcopy"))
    }

    @Test func geckoCommandUsesSelectedProfileAndQuotesShellCharacters() {
        let profile = URL(fileURLWithPath: "/external/Work's $(touch unwanted)")
        let command = ManualCookieImport.command(for: .firefox, filters: [], home: home, profile: profile)
        #expect(command.hasPrefix("DB='/external/Work'\"'\"'s $(touch unwanted)/cookies.sqlite' &&"))
        #expect(!command.contains("ls -t"))
    }

    @Test func chromiumCommandReadsTheSafeStoragePassword() {
        let command = ManualCookieImport.command(
            for: .chrome,
            filters: [.exactOrSuffix("github.com")],
            home: home
        )

        #expect(command.contains("security find-generic-password"))
        #expect(command.contains("Chrome Safe Storage"))
        #expect(command.contains("hex(encrypted_value)"))
        #expect(command.contains("| pbcopy"))
    }

    @Test func chromiumCommandUsesSelectedProfileAndQuotesShellCharacters() {
        let profile = URL(fileURLWithPath: "/external/Work's $(touch unwanted)")
        let command = ManualCookieImport.command(for: .chrome, filters: [], home: home, profile: profile)
        #expect(command.hasPrefix("DB='/external/Work'\"'\"'s $(touch unwanted)/Cookies' &&"))
        #expect(command.contains("cp \"$DB\""))
        #expect(!command.contains("last_used"))
    }

    @Test func safariCommandBase64EncodesTheCookieFile() {
        let command = ManualCookieImport.command(for: .safari, filters: [], home: home)

        #expect(command.contains("base64"))
        #expect(command.contains("Cookies.binarycookies"))
        #expect(command.contains("| pbcopy"))
    }

    @Test func parsesTabbedGeckoOutput() throws {
        let text = "C\t.claude.ai\tsessionKey\tabc\t/\nC\t.example.com\tother\txyz\t/"

        let cookies = try ManualCookieImport.parse(text, browser: .firefox, home: home)

        #expect(cookies.count == 2)
        #expect(cookies.first?.domain == ".claude.ai")
        #expect(cookies.first?.value == "abc")
    }

    @Test func parsesChromiumOutputWithAPlaintextValue() throws {
        let text = "K\tpeanuts\nV\t24\nC\tgithub.com\tuser_session\tlive\t/\t"

        let cookies = try ManualCookieImport.parse(text, browser: .chrome, home: home)

        #expect(cookies.count == 1)
        #expect(cookies.first?.name == "user_session")
        #expect(cookies.first?.value == "live")
    }

    @Test func chromiumParseFailsWithoutTheKeyLine() {
        let text = "V\t24\nC\tgithub.com\tuser_session\t\t/\tdeadbeef"

        var thrown: BrowserCookieError?
        do {
            _ = try ManualCookieImport.parse(text, browser: .chrome, home: home)
        } catch {
            thrown = error
        }

        #expect(thrown == .keyUnavailable)
    }
}
