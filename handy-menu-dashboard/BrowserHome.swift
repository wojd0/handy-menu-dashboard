import Foundation
import Darwin

nonisolated enum BrowserHome {
    // Foundation's home-directory APIs resolve to the app container when sandboxed.
    static var current: URL {
        guard let directory = getpwuid(getuid())?.pointee.pw_dir else {
            return URL(fileURLWithPath: NSHomeDirectory())
        }
        return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
    }
}
