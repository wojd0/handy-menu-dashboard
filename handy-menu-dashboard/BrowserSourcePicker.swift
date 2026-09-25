import SwiftUI

struct BrowserSourcePicker: View {
    let title: String
    @Binding var source: BrowserCookieSource
    @State private var defaultBrowser = DefaultBrowser.current()
    @State private var installed = DefaultBrowser.installed()

    var body: some View {
        Picker(title, selection: $source) {
            if let defaultBrowser {
                Text("Default (\(defaultBrowser.displayName))").tag(BrowserCookieSource.automatic)
            } else {
                Text("Default browser").tag(BrowserCookieSource.automatic)
            }
            ForEach(installed) { browser in
                Text(browser.displayName).tag(BrowserCookieSource.browser(browser))
            }
        }
    }
}
