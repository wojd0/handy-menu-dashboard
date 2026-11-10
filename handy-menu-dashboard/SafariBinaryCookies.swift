import Foundation

nonisolated enum SafariBinaryCookies {
    static func parse(_ data: Data, now: Date = Date()) throws(BrowserCookieError) -> [BrowserCookie] {
        let bytes = [UInt8](data)
        guard bytes.count >= 8, Array(bytes[0..<4]) == Array("cook".utf8) else {
            throw .unreadable
        }

        let pageCount = Int(readUInt32BE(bytes, at: 4))
        guard pageCount <= (bytes.count - 8) / 4 else { throw .unreadable }
        var offset = 8
        var pageSizes: [Int] = []
        pageSizes.reserveCapacity(pageCount)
        for _ in 0..<pageCount {
            guard offset + 4 <= bytes.count else { throw .unreadable }
            pageSizes.append(Int(readUInt32BE(bytes, at: offset)))
            offset += 4
        }

        var cookies: [BrowserCookie] = []
        var pageStart = offset
        for size in pageSizes {
            guard pageStart + size <= bytes.count else { throw .unreadable }
            cookies.append(contentsOf: parsePage(bytes, start: pageStart, size: size, now: now))
            pageStart += size
        }
        return cookies
    }

    private static func parsePage(_ bytes: [UInt8], start: Int, size: Int, now: Date) -> [BrowserCookie] {
        guard size >= 8 else { return [] }
        let cookieCount = Int(readUInt32LE(bytes, at: start + 4))

        var cookies: [BrowserCookie] = []
        var cursor = start + 8
        for _ in 0..<cookieCount {
            guard cursor + 4 <= start + size else { break }
            let recordOffset = start + Int(readUInt32LE(bytes, at: cursor))
            cursor += 4
            if let cookie = parseRecord(bytes, at: recordOffset, pageEnd: start + size, now: now) {
                cookies.append(cookie)
            }
        }
        return cookies
    }

    private static func parseRecord(_ bytes: [UInt8], at offset: Int, pageEnd: Int, now: Date) -> BrowserCookie? {
        guard offset + 48 <= pageEnd else { return nil }

        let expiry = readFloat64LE(bytes, at: offset + 40)
        guard expiry <= 0 || Date(timeIntervalSinceReferenceDate: expiry) > now else { return nil }

        let urlOffset = offset + Int(readUInt32LE(bytes, at: offset + 16))
        let nameOffset = offset + Int(readUInt32LE(bytes, at: offset + 20))
        let pathOffset = offset + Int(readUInt32LE(bytes, at: offset + 24))
        let valueOffset = offset + Int(readUInt32LE(bytes, at: offset + 28))

        guard let domain = cString(bytes, at: urlOffset, limit: pageEnd),
              let name = cString(bytes, at: nameOffset, limit: pageEnd),
              let path = cString(bytes, at: pathOffset, limit: pageEnd),
              let value = cString(bytes, at: valueOffset, limit: pageEnd) else {
            return nil
        }

        return BrowserCookie(domain: domain, name: name, value: value, path: path.isEmpty ? "/" : path)
    }

    private static func cString(_ bytes: [UInt8], at offset: Int, limit: Int) -> String? {
        guard offset >= 0, offset < limit else { return nil }
        var end = offset
        while end < limit && bytes[end] != 0 { end += 1 }
        return String(bytes: bytes[offset..<end], encoding: .utf8)
    }

    private static func readUInt32BE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24) | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8) | UInt32(bytes[offset + 3])
    }

    private static func readFloat64LE(_ bytes: [UInt8], at offset: Int) -> Double {
        var bits: UInt64 = 0
        for index in 0..<8 {
            bits |= UInt64(bytes[offset + index]) << (8 * UInt64(index))
        }
        return Double(bitPattern: bits)
    }

    private static func readUInt32LE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16) | (UInt32(bytes[offset + 3]) << 24)
    }
}
