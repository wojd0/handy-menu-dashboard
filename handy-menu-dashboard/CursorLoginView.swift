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
        webView.customUserAgent = BrowserIdentity.userAgent
        webView.load(URLRequest(url: Provider.cursor.harvest.startURL))
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
            let harvest = Provider.cursor.harvest
            guard harvest.acceptsNavigation(to: webView.url) else { return }

            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.hasExtracted else { return }
                guard let sessionCookies = harvest.sessionCookies(from: cookies) else { return }
                self.hasExtracted = true
                Task { @MainActor in
                    self.parent.onCookiesExtracted(sessionCookies)
                }
            }
        }
    }
}
