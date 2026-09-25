import Foundation
import Testing
@testable import handy_menu_dashboard

@Suite("Safari binary cookies")
struct SafariBinaryCookiesTests {
    @Test func parsesASingleCookieRecord() throws {
        let data = buildFile(cookie: ("github.com", "user_session", "abc123", "/"))

        let cookies = try SafariBinaryCookies.parse(data)

        #expect(cookies.count == 1)
        #expect(cookies.first?.domain == "github.com")
        #expect(cookies.first?.name == "user_session")
        #expect(cookies.first?.value == "abc123")
    }

    @Test func rejectsAPageCountLargerThanTheFile() {
        let data = Data("cook".utf8) + uint32BE(.max)

        #expect(throws: BrowserCookieError.unreadable) {
            try SafariBinaryCookies.parse(data)
        }
    }

    @Test func rejectsAFileWithoutTheMagicHeader() {
        let data = Data("nope".utf8) + Data(count: 8)

        var thrown: BrowserCookieError?
        do {
            _ = try SafariBinaryCookies.parse(data)
        } catch {
            thrown = error
        }

        #expect(thrown == .unreadable)
    }

    private func buildFile(cookie: (domain: String, name: String, value: String, path: String)) -> Data {
        let record = buildRecord(cookie)

        var page = Data()
        page.append(uint32BE(0x0000_0100))
        page.append(uint32LE(1))
        let recordOffset = 4 + 4 + 4 + 4
        page.append(uint32LE(UInt32(recordOffset)))
        page.append(uint32LE(0))
        page.append(record)

        var file = Data("cook".utf8)
        file.append(uint32BE(1))
        file.append(uint32BE(UInt32(page.count)))
        file.append(page)
        return file
    }

    private func buildRecord(_ cookie: (domain: String, name: String, value: String, path: String)) -> Data {
        let stringsStart = 48
        let domainBytes = Data((cookie.domain + "\0").utf8)
        let nameBytes = Data((cookie.name + "\0").utf8)
        let pathBytes = Data((cookie.path + "\0").utf8)
        let valueBytes = Data((cookie.value + "\0").utf8)

        let domainOffset = stringsStart
        let nameOffset = domainOffset + domainBytes.count
        let pathOffset = nameOffset + nameBytes.count
        let valueOffset = pathOffset + pathBytes.count

        var record = Data(count: stringsStart)
        record.replaceSubrange(16..<20, with: uint32LE(UInt32(domainOffset)))
        record.replaceSubrange(20..<24, with: uint32LE(UInt32(nameOffset)))
        record.replaceSubrange(24..<28, with: uint32LE(UInt32(pathOffset)))
        record.replaceSubrange(28..<32, with: uint32LE(UInt32(valueOffset)))
        record.append(domainBytes)
        record.append(nameBytes)
        record.append(pathBytes)
        record.append(valueBytes)
        return record
    }

    private func uint32LE(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private func uint32BE(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }
}
