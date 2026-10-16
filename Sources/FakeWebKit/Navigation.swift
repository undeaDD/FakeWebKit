#if os(tvOS)
    import Foundation

    // MARK: - Navigation values

    public struct WKNavigation {
        @available(*, unavailable, message: "The effectiveContentMode property is not supported.")
        public var effectiveContentMode: Any {
            fatalError("This property is unavailable.")
        }
    }

    public enum WKNavigationType: Int, Sendable {
        case linkActivated = 0
        case formSubmitted = 1
        case backForward = 2
        case reload = 3
        case formResubmitted = 4
        case other = -1

        /// Maps `UIWebViewNavigationType`, which uses `5` for "other".
        init(uiWebViewNavigationType rawValue: Int) {
            self = WKNavigationType(rawValue: rawValue) ?? .other
        }
    }

    public struct WKFrameInfo: Sendable {
        public let isMainFrame: Bool
        public let request: URLRequest
    }

    public struct WKNavigationAction: Sendable {
        public let request: URLRequest
        public let navigationType: WKNavigationType
        public let targetFrame: WKFrameInfo?

        init(request: URLRequest, navigationType: WKNavigationType = .other, targetFrame: WKFrameInfo? = nil) {
            self.request = request
            self.navigationType = navigationType
            self.targetFrame = targetFrame
        }
    }

    public enum WKNavigationActionPolicy: Int, Sendable {
        case cancel = 0
        case allow = 1

        @available(*, unavailable, message: "The .download policy is not supported.")
        case download = 2
    }

    // MARK: - Navigation delegate

    /// Every method has a default implementation, so conformers only implement what they need,
    /// just like the optional methods of WebKit's `WKNavigationDelegate`.
    /// The `WKNavigation!` variants match the signatures Xcode generates for WebKit.
    @MainActor
    public protocol WKNavigationDelegate: NSObjectProtocol {
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation)
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!)
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation)
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!)
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation, withError error: Error)
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error)
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation)
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!)
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation, withError error: Error)
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error)
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void)
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy
    }

    public extension WKNavigationDelegate {
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation) {}
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {}
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation) {}
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {}
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation, withError error: Error) {}
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {}
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation) {}
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation, withError error: Error) {}
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {}

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            WKWebView._resolvePolicy({ await self.webView(webView, decidePolicyFor: navigationAction) },
                                     completion: decisionHandler)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            _PolicyProbe.current?.usedDefaultImplementation = true
            return .allow
        }
    }

    /// Detects delegates that implement neither policy method, so their navigations
    /// are not deferred again on systems without `Task.immediate`.
    final class _PolicyProbe: @unchecked Sendable {
        @TaskLocal static var current: _PolicyProbe?
        var usedDefaultImplementation = false
    }
#endif
