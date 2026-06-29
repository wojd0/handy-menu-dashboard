import WebKit

enum WebAuthSession {
    static func clearCookies(matching domain: String) {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: types) { records in
            let matching = records.filter { $0.displayName.contains(domain) }
            store.removeData(ofTypes: types, for: matching) {}
        }
    }
}
