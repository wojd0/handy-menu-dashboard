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
        context.coordinator.observeCookies(in: webView)
        webView.load(URLRequest(url: Provider.cursor.harvest.startURL))
        return webView
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.stopObservingCookies(in: nsView)
        nsView.navigationDelegate = nil
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        let parent: CursorWebView
        private var hasExtracted = false
        private weak var webView: WKWebView?
        private var pendingExtraction: Task<Void, Never>?

        init(parent: CursorWebView) {
            self.parent = parent
        }

        func observeCookies(in webView: WKWebView) {
            self.webView = webView
            webView.configuration.websiteDataStore.httpCookieStore.add(self)
        }

        func stopObservingCookies(in webView: WKWebView) {
            pendingExtraction?.cancel()
            webView.configuration.websiteDataStore.httpCookieStore.remove(self)
            self.webView = nil
        }

        nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            MainActor.assumeIsolated {
                guard let webView else { return }
                scheduleExtraction(from: webView)
            }
        }

        nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            MainActor.assumeIsolated {
                parent.isLoading = false
                scheduleExtraction(from: webView)
            }
        }

        nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            MainActor.assumeIsolated {
                parent.isLoading = true
            }
        }

        private func scheduleExtraction(from webView: WKWebView) {
            pendingExtraction?.cancel()
            pendingExtraction = Task { @MainActor [weak self, weak webView] in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, let webView else { return }
                self.extractCookiesIfNeeded(from: webView)
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
