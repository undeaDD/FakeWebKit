#if os(tvOS)
    @testable import FakeWebKit
    import XCTest

    extension XCTestCase {
        /// Spins the main run loop until `condition` holds or the timeout passes.
        @discardableResult
        func waitUntil(timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while !condition() {
                if Date() > deadline {
                    XCTFail("Condition not met within \(timeout)s", file: file, line: line)
                    return false
                }
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            return true
        }

        /// Async variant of `waitUntil`: suspends instead of spinning, so main queue work can run.
        @discardableResult
        func waitUntilAsync(timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line,
                            _ condition: () -> Bool) async -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while !condition() {
                if Date() > deadline {
                    XCTFail("Condition not met within \(timeout)s", file: file, line: line)
                    return false
                }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            return true
        }

        /// Spins the main run loop for a fixed time.
        func spin(_ seconds: TimeInterval) {
            RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        }

        func makeTemporaryHTML(_ html: String, name: String = UUID().uuidString) throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).html")
            try html.write(to: url, atomically: true, encoding: .utf8)
            return url
        }
    }

    final class TestLogger: DebugLogger {
        var messages: [String] = []
        var errors: [String] = []

        func log(_ message: String) { messages.append(message) }
        func logError(_ message: String) { errors.append(message) }
    }

    /// Records navigation callbacks using the non-optional signatures of FakeWebKit 0.0.x.
    final class RecordingDelegate: NSObject, WKNavigationDelegate {
        var events: [String] = []
        var actions: [WKNavigationAction] = []
        var errors: [Error] = []
        var policy: WKNavigationActionPolicy = .allow

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation) {
            events.append("start")
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation) {
            events.append("commit")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation) {
            events.append("finish")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation, withError error: Error) {
            events.append("fail")
            errors.append(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation, withError error: Error) {
            events.append("fail-provisional")
            errors.append(error)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            actions.append(navigationAction)
            decisionHandler(policy)
        }
    }

    /// Uses the signatures Xcode generates for WebKit, including the async policy method.
    final class WebKitStyleDelegate: NSObject, WKNavigationDelegate {
        var events: [String] = []
        var blockedHosts: Set<String> = []
        var decidedURLs: [URL] = []

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            events.append("start")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            events.append("finish")
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            events.append("commit")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            events.append("fail")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            events.append("fail-provisional")
        }

        @available(iOS 15.0, macOS 13.0, *)
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if let url = navigationAction.request.url {
                decidedURLs.append(url)
                if let host = url.host, blockedHosts.contains(host) { return .cancel }
            }
            return .allow
        }
    }

    /// Answers the policy question later instead of inside the callback.
    final class LateDecisionDelegate: NSObject, WKNavigationDelegate {
        var events: [String] = []
        var policy: WKNavigationActionPolicy = .allow
        var decisions = 0

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            events.append("finish")
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisions += 1
            let policy = policy
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                decisionHandler(policy)
                decisionHandler(.cancel)
            }
        }
    }

    /// Implements no policy method at all.
    final class FinishOnlyDelegate: NSObject, WKNavigationDelegate {
        var finished = 0

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            finished += 1
        }
    }

    final class MessageRecorder: NSObject, WKScriptMessageHandler {
        var messages: [WKScriptMessage] = []

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            messages.append(message)
        }
    }

    final class CookieObserver: NSObject, WKHTTPCookieStoreObserver {
        var changes = 0

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            changes += 1
        }
    }

    final class SilentCookieObserver: NSObject, WKHTTPCookieStoreObserver {}
#endif
