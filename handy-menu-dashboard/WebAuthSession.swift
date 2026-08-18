import WebKit

enum WebAuthSession {
    static func clearCookies(matching domain: String) {
        clearWebsiteData(matching: [domain])
    }

    static func clearWebsiteData(
        matching domains: [String],
        in store: WKWebsiteDataStore = .default(),
        completion: @escaping () -> Void = {}
    ) {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: types) { records in
            let matching = records.filter { record in
                domains.contains { domain in
                    record.displayName.localizedCaseInsensitiveContains(domain)
                }
            }
            guard !matching.isEmpty else {
                completion()
                return
            }
            store.removeData(ofTypes: types, for: matching, completionHandler: completion)
        }
    }
}
