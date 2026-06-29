import SwiftUI
import WebKit

struct CursorLoginView: View {
    var cursorService: CursorService
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sign in to Cursor")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
            }
            .padding()

            ZStack {
                CursorWebView(
                    isLoading: $isLoading,
                    onCookiesExtracted: { cookies in
                        cursorService.saveCookies(cookies)
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

struct CursorWebView: NSViewRepresentable {
    @Binding var isLoading: Bool
    var onCookiesExtracted: ([HTTPCookie]) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = CursorService.browserUserAgent
        webView.load(URLRequest(url: URL(string: "https://www.cursor.com/settings")!))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: CursorWebView
        private var hasExtracted = false

        init(parent: CursorWebView) {
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
            guard let url = webView.url, url.host?.contains("cursor.com") == true else { return }

            let isDashboardOrSettings = url.path.contains("/settings") || url.path.contains("/dashboard")
            guard isDashboardOrSettings else { return }

            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.hasExtracted else { return }
                let cursorCookies = cookies.filter { $0.domain.contains("cursor.com") }
                let hasSession = cursorCookies.contains {
                    $0.name.lowercased().contains("session") ||
                    $0.name.lowercased().contains("token") ||
                    $0.name == "WorkosCursorSessionToken"
                }
                if hasSession {
                    self.hasExtracted = true
                    Task { @MainActor in
                        self.parent.onCookiesExtracted(cursorCookies)
                    }
                }
            }
        }
    }
}
