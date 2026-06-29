import SwiftUI
import WebKit

struct ClaudeLoginView: View {
    var claudeService: ClaudeService
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sign in to Claude")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
            }
            .padding()

            ZStack {
                ClaudeWebView(
                    isLoading: $isLoading,
                    onCookiesExtracted: { cookies in
                        claudeService.saveCookies(cookies)
                        dismiss()
                    }
                )

                if isLoading {
                    ProgressView()
                }
            }
        }
        .frame(width: 500, height: 600)
    }
}

struct ClaudeWebView: NSViewRepresentable {
    @Binding var isLoading: Bool
    var onCookiesExtracted: ([HTTPCookie]) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = ClaudeService.chromeUserAgent
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: ClaudeWebView
        private var hasExtracted = false

        init(parent: ClaudeWebView) {
            self.parent = parent
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
            guard !hasExtracted else { return }
            guard let url = webView.url, url.host?.contains("claude.ai") == true else { return }

            let isPostLogin = !url.path.contains("/login")
            guard isPostLogin else { return }

            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.hasExtracted else { return }
                let claudeCookies = cookies.filter { $0.domain.contains("claude.ai") }
                let hasSession = claudeCookies.contains { $0.name == "sessionKey" }
                if hasSession {
                    self.hasExtracted = true
                    Task { @MainActor in
                        self.parent.onCookiesExtracted(claudeCookies)
                    }
                }
            }
        }
    }
}
