#if os(tvOS)
    @testable import FakeWebKit
    import XCTest

    /// Mirrors code from apps that use FakeWebKit, so those call sites keep compiling without `#if !os(tvOS)`.
    @MainActor
    final class SnippetCompatibilityTests: XCTestCase {
        private final class NetworkMonitor: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
            var requests: [String] = []
            var cookies: [String: String] = [:]
            var blockedHost = "blocked.test"

            func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}
            func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {}

            @available(iOS 15.0, macOS 13.0, *)
            func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
                if let url = navigationAction.request.url {
                    if url.host == blockedHost { return .cancel }
                    requests.append(url.absoluteString)
                }
                return .allow
            }

            func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
                guard message.name == "networkLogger", let body = message.body as? [String: Any] else { return }

                if let url = body["url"] as? String {
                    requests.append(url)
                }
                if body["type"] as? String == "cookies", let cookiesData = body["cookies"] as? [String: String] {
                    cookies.merge(cookiesData) { _, new in new }
                }
            }
        }

        func testNetworkMonitorSnippet() {
            let monitor = NetworkMonitor()
            let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
            let ucc = webView.configuration.userContentController
            ucc.removeAllUserScripts()
            ucc.add(monitor, name: "networkLogger")
            ucc.addUserScript(WKUserScript(source: """
            window.webkit.messageHandlers.networkLogger.postMessage({ url: 'https://api.test/1' });
            window.webkit.messageHandlers.networkLogger.postMessage({ type: 'cookies', cookies: { cf: 'x' } });
            """, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            webView.navigationDelegate = monitor

            webView.loadHTMLString("<p>page</p>", baseURL: URL(string: "https://allowed.test/"))

            _ = withExtendedLifetime(webView) {
                waitUntil { monitor.cookies["cf"] == "x" }
            }
            XCTAssertTrue(monitor.requests.contains("https://allowed.test/"))
            XCTAssertTrue(monitor.requests.contains("https://api.test/1"))
        }

        func testClearCookiesSnippet() async throws {
            let cookie = try XCTUnwrap(HTTPCookie(properties: [.name: "cf_clearance", .value: "v", .domain: ".site.test", .path: "/"]))
            HTTPCookieStorage.shared.setCookie(cookie)

            await Task { @MainActor in
                await WKWebsiteDataStore.default().removeData(
                    ofTypes: [WKWebsiteDataTypeCookies],
                    modifiedSince: .distantPast
                )
            }.value

            XCTAssertFalse((HTTPCookieStorage.shared.cookies ?? []).contains { $0.name == "cf_clearance" })
        }

        func testExtractClearanceCookieSnippet() throws {
            let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
            webView.customUserAgent = "SnippetAgent"
            let cookie = try XCTUnwrap(HTTPCookie(properties: [.name: "cf_clearance", .value: "token", .domain: ".site.test", .path: "/"]))
            HTTPCookieStorage.shared.setCookie(cookie)
            defer { HTTPCookieStorage.shared.deleteCookie(cookie) }

            let host = "www.site.test"
            let solvedUA = webView.customUserAgent ?? ""
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            var header = ""
            cookieStore.getAllCookies { cookies in
                guard let clearance = cookies.first(where: {
                    guard $0.name == "cf_clearance" else { return false }
                    let domain = $0.domain.hasPrefix(".") ? String($0.domain.dropFirst()) : $0.domain
                    return host == domain || host.hasSuffix("." + domain)
                }) else { return }
                header = "\(clearance.name)=\(clearance.value)"
            }

            XCTAssertEqual(header, "cf_clearance=token")
            XCTAssertEqual(solvedUA, "SnippetAgent")
        }
    }
#endif
