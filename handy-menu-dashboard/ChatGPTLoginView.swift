import SwiftUI
import WebKit

struct ChatGPTLoginView: View {
    var chatGPTService: ChatGPTService
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true

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

            ZStack {
                ChatGPTWebView(
                    isLoading: $isLoading,
                    onCookiesExtracted: { cookies in
                        chatGPTService.saveCookies(cookies)
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

struct ChatGPTWebView: NSViewRepresentable {
    @Binding var isLoading: Bool
    var onCookiesExtracted: ([HTTPCookie]) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = ChatGPTService.browserUserAgent
        webView.load(URLRequest(url: URL(string: "https://chatgpt.com/")!))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: ChatGPTWebView
        private var hasExtracted = false

        init(parent: ChatGPTWebView) {
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
            guard webView.url?.host?.contains("chatgpt.com") == true else { return }

            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.hasExtracted else { return }
                let chatGPTCookies = cookies.filter { $0.domain.contains("chatgpt.com") }
                let hasSession = chatGPTCookies.contains {
                    $0.name.hasPrefix("__Secure-next-auth.session-token")
                }
                let hasAccount = chatGPTCookies.contains { $0.name == "_account" }
                guard hasSession, hasAccount else { return }

                self.hasExtracted = true
                Task { @MainActor in
                    self.parent.onCookiesExtracted(chatGPTCookies)
                }
            }
        }
    }
}
