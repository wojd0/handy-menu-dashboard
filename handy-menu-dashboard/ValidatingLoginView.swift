import SwiftUI
import WebKit

struct ValidatingLoginView: View {
    let provider: Provider
    let authenticate: ([HTTPCookie]) async -> LoginOutcome
    @Environment(\.dismiss) private var dismiss
    @State private var flow: LoginFlow
    @State private var isLoading = true
    @State private var retryAttempt = 0

    init(provider: Provider, authenticate: @escaping ([HTTPCookie]) async -> LoginOutcome) {
        self.provider = provider
        self.authenticate = authenticate
        _flow = State(initialValue: LoginFlow(harvest: provider.harvest, authenticate: authenticate))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(provider.signInTitle)
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
            }
            .padding()

            if let errorMessage = flow.errorMessage {
                HStack(spacing: 12) {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Retry") { retryAttempt += 1 }
                        .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }

            ZStack {
                ValidatingWebView(
                    harvest: provider.harvest,
                    flow: flow,
                    retryAttempt: retryAttempt,
                    isLoading: $isLoading,
                    onAuthenticated: { dismiss() }
                )

                if isLoading || flow.isValidating {
                    ProgressView()
                }
            }
        }
        .frame(width: 500, height: 600)
    }
}

struct ValidatingWebView: NSViewRepresentable {
    let harvest: CookieHarvest
    let flow: LoginFlow
    var retryAttempt: Int
    @Binding var isLoading: Bool
    let onAuthenticated: () -> Void

    static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        return configuration
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: Self.makeConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = BrowserIdentity.userAgent

        let startURL = harvest.startURL
        flow.effects = LoginFlow.Effects(
            clearWebsiteData: { [weak webView] domains in
                guard let store = webView?.configuration.websiteDataStore else { return }
                await WebAuthSession.clearWebsiteData(matching: domains, in: store)
            },
            reload: { [weak webView] in
                webView?.load(URLRequest(url: startURL))
            },
            authenticated: onAuthenticated
        )

        context.coordinator.observeCookies(in: webView)
        webView.load(URLRequest(url: startURL))
        return webView
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.stopObservingCookies(in: nsView)
        nsView.navigationDelegate = nil
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.retryIfNeeded(from: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        var parent: ValidatingWebView
        private weak var webView: WKWebView?

        init(parent: ValidatingWebView) {
            self.parent = parent
        }

        func observeCookies(in webView: WKWebView) {
            self.webView = webView
            webView.configuration.websiteDataStore.httpCookieStore.add(self)
        }

        func stopObservingCookies(in webView: WKWebView) {
            webView.configuration.websiteDataStore.httpCookieStore.remove(self)
            self.webView = nil
        }

        nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            MainActor.assumeIsolated {
                guard let webView else { return }
                extractCookiesIfNeeded(from: webView)
            }
        }

        nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            MainActor.assumeIsolated {
                parent.isLoading = false
                extractCookiesIfNeeded(from: webView)
            }
        }

        nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            MainActor.assumeIsolated {
                parent.isLoading = true
            }
        }

        func retryIfNeeded(from webView: WKWebView) {
            let flow = parent.flow
            let attempt = parent.retryAttempt
            Task { @MainActor [weak self, weak webView] in
                let action = await flow.retry(attempt: attempt)
                guard action == .needsFreshCookies, let self, let webView else { return }
                self.extractCookiesIfNeeded(from: webView)
            }
        }

        private func extractCookiesIfNeeded(from webView: WKWebView) {
            let harvest = parent.harvest
            let flow = parent.flow
            guard harvest.acceptsNavigation(to: webView.url) else { return }

            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                guard let sessionCookies = harvest.sessionCookies(from: cookies) else { return }
                Task { @MainActor in
                    await flow.harvested(sessionCookies)
                }
            }
        }
    }
}
