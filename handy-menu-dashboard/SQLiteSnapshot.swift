import Foundation
import SQLite3

nonisolated struct SQLiteSnapshot {
    private let database: OpaquePointer
    private let directory: URL

    init(of source: URL) throws(BrowserCookieError) {
        let fileManager = FileManager.default
        do {
            _ = try fileManager.attributesOfItem(atPath: source.path)
        } catch {
            let error = error as NSError
            if error.code == NSFileReadNoPermissionError { throw .accessDenied }
            if error.code == NSFileReadNoSuchFileError { throw .noProfile }
            throw .unreadable
        }

        let directory = fileManager.temporaryDirectory
            .appending(path: "hmd-cookie-\(UUID().uuidString)")
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw .unreadable
        }
        self.directory = directory
        var opened = false
        defer {
            if !opened {
                try? fileManager.removeItem(at: directory)
            }
        }

        let copyDestination = directory.appending(path: "db.sqlite")
        for suffix in ["", "-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: source.path + suffix)
            guard fileManager.fileExists(atPath: sidecar.path) else { continue }
            let destination = URL(fileURLWithPath: copyDestination.path + suffix)
            do {
                try? fileManager.removeItem(at: destination)
                try fileManager.copyItem(at: sidecar, to: destination)
            } catch {
                let code = (error as NSError).code
                if code == NSFileReadNoPermissionError {
                    throw .accessDenied
                }
                throw .unreadable
            }
        }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(copyDestination.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw .unreadable
        }
        database = handle
        opened = true
    }

    func rows(_ sql: String) throws(BrowserCookieError) -> [[SQLiteValue]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw .unreadable
        }
        defer { sqlite3_finalize(statement) }

        var result: [[SQLiteValue]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let columnCount = sqlite3_column_count(statement)
            var row: [SQLiteValue] = []
            row.reserveCapacity(Int(columnCount))
            for index in 0..<columnCount {
                row.append(value(in: statement, at: index))
            }
            result.append(row)
        }
        return result
    }

    private func value(in statement: OpaquePointer, at index: Int32) -> SQLiteValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_BLOB:
            if let bytes = sqlite3_column_blob(statement, index) {
                let count = Int(sqlite3_column_bytes(statement, index))
                return .blob(Data(bytes: bytes, count: count))
            }
            return .blob(Data())
        case SQLITE_NULL:
            return .null
        default:
            if let text = sqlite3_column_text(statement, index) {
                return .text(String(cString: text))
            }
            return .null
        }
    }

    func close() {
        sqlite3_close(database)
        try? FileManager.default.removeItem(at: directory)
    }
}

nonisolated enum SQLiteValue: Equatable {
    case integer(Int64)
    case text(String)
    case blob(Data)
    case null

    var text: String? {
        if case let .text(value) = self { return value }
        return nil
    }

    var blob: Data? {
        if case let .blob(value) = self { return value }
        return nil
    }

    var integer: Int64? {
        if case let .integer(value) = self { return value }
        return nil
    }
}
