import Foundation

nonisolated enum Browser: String, CaseIterable, Codable, Identifiable, Sendable {
    case firefox
    case firefoxDeveloperEdition
    case firefoxNightly
    case zen
    case chrome
    case brave
    case edge
    case arc
    case vivaldi
    case chromium
    case safari

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .firefox: "Firefox"
        case .firefoxDeveloperEdition: "Firefox Developer Edition"
        case .firefoxNightly: "Firefox Nightly"
        case .zen: "Zen"
        case .chrome: "Chrome"
        case .brave: "Brave"
        case .edge: "Edge"
        case .arc: "Arc"
        case .vivaldi: "Vivaldi"
        case .chromium: "Chromium"
        case .safari: "Safari"
        }
    }

    var bundleIDs: [String] {
        switch self {
        case .firefox: ["org.mozilla.firefox"]
        case .firefoxDeveloperEdition: ["org.mozilla.firefoxdeveloperedition"]
        case .firefoxNightly: ["org.mozilla.nightly"]
        case .zen: ["app.zen-browser.zen"]
        case .chrome: ["com.google.Chrome", "com.google.Chrome.canary"]
        case .brave: ["com.brave.Browser", "com.brave.Browser.nightly"]
        case .edge: ["com.microsoft.edgemac"]
        case .arc: ["company.thebrowser.Browser"]
        case .vivaldi: ["com.vivaldi.Vivaldi"]
        case .chromium: ["org.chromium.Chromium"]
        case .safari: ["com.apple.Safari"]
        }
    }

    static func resolve(bundleID: String) -> Browser? {
        allCases.first { $0.bundleIDs.contains(bundleID) }
    }

    enum Engine: Equatable {
        case gecko(profilesRoot: URL)
        case chromium(userDataRoot: URL, safeStorageService: String, safeStorageAccount: String)
        case webkit(cookieFile: URL)
    }

    func engine(home: URL) -> Engine {
        let appSupport = home.appending(path: "Library/Application Support")
        switch self {
        case .firefox, .firefoxDeveloperEdition, .firefoxNightly:
            return .gecko(profilesRoot: appSupport.appending(path: "Firefox"))
        case .zen:
            return .gecko(profilesRoot: appSupport.appending(path: "zen"))
        case .chrome:
            return .chromium(
                userDataRoot: appSupport.appending(path: "Google/Chrome"),
                safeStorageService: "Chrome Safe Storage",
                safeStorageAccount: "Chrome"
            )
        case .brave:
            return .chromium(
                userDataRoot: appSupport.appending(path: "BraveSoftware/Brave-Browser"),
                safeStorageService: "Brave Safe Storage",
                safeStorageAccount: "Brave"
            )
        case .edge:
            return .chromium(
                userDataRoot: appSupport.appending(path: "Microsoft Edge"),
                safeStorageService: "Microsoft Edge Safe Storage",
                safeStorageAccount: "Microsoft Edge"
            )
        case .arc:
            return .chromium(
                userDataRoot: appSupport.appending(path: "Arc/User Data"),
                safeStorageService: "Arc Safe Storage",
                safeStorageAccount: "Arc"
            )
        case .vivaldi:
            return .chromium(
                userDataRoot: appSupport.appending(path: "Vivaldi"),
                safeStorageService: "Vivaldi Safe Storage",
                safeStorageAccount: "Vivaldi"
            )
        case .chromium:
            return .chromium(
                userDataRoot: appSupport.appending(path: "Chromium"),
                safeStorageService: "Chromium Safe Storage",
                safeStorageAccount: "Chromium"
            )
        case .safari:
            return .webkit(
                cookieFile: home.appending(
                    path: "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"
                )
            )
        }
    }
}
