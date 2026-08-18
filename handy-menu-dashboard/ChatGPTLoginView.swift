import SwiftUI
import WebKit

struct ChatGPTLoginView: View {
    var chatGPTService: ChatGPTService
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var isValidating = false
    @State private var loginError: String?
    @State private var retryAttempt = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sign in to ChatGPT")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
            }
            .padding()

            if let loginError {
                HStack(spacing: 12) {
                    Label(loginError, systemImage: "exclamationmark.triangle.fill")
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
                ChatGPTWebView(
                    isLoading: $isLoading,
                    retryAttempt: retryAttempt,
                    authenticate: { cookies in
                        await chatGPTService.authenticate(with: cookies)
                    },
                    onValidationChanged: { validating in
                        isValidating = validating
                        if validating {
                            loginError = nil
                        }
                    },
                    onAuthenticationError: { message in
                        loginError = message
                    },
                    onAuthenticated: {
                        dismiss()
                    }
                )

                if isLoading || isValidating {
                    ProgressView()
                }
            }
        }
        .frame(width: 500, height: 600)
    }
}

struct ChatGPTWebView: NSViewRepresentable {
    @Binding var isLoading: Bool
    var retryAttempt: Int
    var authenticate: ([HTTPCookie]) async -> ChatGPTAuthenticationResult
    var onValidationChanged: (Bool) -> Void
    var onAuthenticationError: (String) -> Void
    var onAuthenticated: () -> Void

    func makeNSView(context: Context) -> WKWebView {
        let configuration = Self.makeConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = ChatGPTService.browserUserAgent
        webView.load(URLRequest(url: URL(string: "https://chatgpt.com/")!))
        return webView
    }

    static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        return configuration
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.retryIfNeeded(from: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: ChatGPTWebView
        private var isAuthenticating = false
        private var lastCookies: [HTTPCookie]?
        private var handledRetryAttempt: Int

        init(parent: ChatGPTWebView) {
            self.parent = parent
            handledRetryAttempt = parent.retryAttempt
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

        private func extractCookiesIfNeeded(from webView: WKWebView) {
            guard !isAuthenticating else { return }
            guard webView.url?.host?.contains("chatgpt.com") == true else { return }

            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.isAuthenticating else { return }
                let chatGPTCookies = cookies.filter { $0.domain.contains("chatgpt.com") }
                let hasSession = chatGPTCookies.contains {
                    $0.name.hasPrefix("__Secure-next-auth.session-token")
                }
                let hasAccount = chatGPTCookies.contains { $0.name == "_account" }
                guard hasSession, hasAccount else { return }

                self.authenticate(chatGPTCookies, from: webView)
            }
        }

        func retryIfNeeded(from webView: WKWebView) {
            guard handledRetryAttempt != parent.retryAttempt else { return }
            handledRetryAttempt = parent.retryAttempt
            if let lastCookies {
                authenticate(lastCookies, from: webView)
            } else {
                extractCookiesIfNeeded(from: webView)
            }
        }

        private func authenticate(_ cookies: [HTTPCookie], from webView: WKWebView) {
            guard !isAuthenticating else { return }
            isAuthenticating = true
            lastCookies = cookies
            parent.onValidationChanged(true)

            Task { @MainActor [weak self, weak webView] in
                guard let self, let webView else { return }
                let result = await self.parent.authenticate(cookies)
                self.parent.onValidationChanged(false)

                switch result {
                case .authenticated:
                    self.parent.onAuthenticated()
                case .staleSession:
                    self.lastCookies = nil
                    self.parent.onAuthenticationError("Session expired. Please sign in again.")
                    WebAuthSession.clearWebsiteData(
                        matching: ChatGPTService.websiteDataDomains,
                        in: webView.configuration.websiteDataStore
                    ) { [weak self, weak webView] in
                        Task { @MainActor in
                            guard let self, let webView else { return }
                            self.isAuthenticating = false
                            webView.load(URLRequest(url: URL(string: "https://chatgpt.com/")!))
                        }
                    }
                case .failure(let message):
                    self.isAuthenticating = false
                    self.parent.onAuthenticationError(message)
                }
            }
        }
    }
}
