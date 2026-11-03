import SwiftUI

struct SessionUpdateSheet: View {
    let services: ServiceSet
    let providers: [Provider]?
    @State private var loginProvider: Provider?

    var body: some View {
        SessionUpdateDialog(
            coordinator: services.sessionUpdates,
            providers: providers,
            width: 420,
            onWebViewFallback: { loginProvider = $0 },
            onClose: { services.sessionUpdates.consentRequest = nil }
        )
        .sheet(item: $loginProvider) { provider in
            ProviderLoginSheet(provider: provider, services: services)
        }
    }
}
