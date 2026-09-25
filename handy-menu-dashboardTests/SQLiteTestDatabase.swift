import Foundation
import SQLite3

enum SQLiteTestDatabase {
    static func create(at url: URL, statements: [String]) {
        try? FileManager.default.removeItem(at: url)

        var handle: OpaquePointer?
        sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        defer { sqlite3_close(handle) }

        for statement in statements {
            sqlite3_exec(handle, statement, nil, nil, nil)
        }
    }

    static func makeDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "hmd-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
