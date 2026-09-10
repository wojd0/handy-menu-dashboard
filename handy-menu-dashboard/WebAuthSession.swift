import WebKit

enum WebAuthSession {
    static func clearAllWebsiteData() async {
        await clearAllWebsiteData(in: .default())
    }

    static func clearAllWebsiteData(in store: WKWebsiteDataStore) async {
        await withCheckedContinuation { continuation in
            store.removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: .distantPast
            ) {
                continuation.resume()
            }
        }
    }

    static func clearWebsiteData(matching domains: [String], in store: WKWebsiteDataStore) async {
        await withCheckedContinuation { continuation in
            clearWebsiteData(matching: domains, in: store) {
                continuation.resume()
            }
        }
    }

    static func clearWebsiteData(
        matching domains: [String],
        in store: WKWebsiteDataStore,
        completion: @escaping () -> Void
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
