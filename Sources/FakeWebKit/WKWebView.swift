#if os(tvOS)
    import UIKit

    // MARK: - WKWebView ( without WebKit )

    public class WKWebView: UIView {
        var _webView: AnyObject?
        var _delegateProxy: _DelegateProxy?
        public static var logger: DebugLogger?

        /// Initial `isHidden` value of new web views. FakeWebKit hides them by default, set this to
        /// `false` to get visible web views like on iOS. `isHidden` itself can be changed at any time.
        public static var isHiddenByDefault = true

        public var customUserAgent: String? { didSet { _applyCustomUserAgent() } }
        public weak var navigationDelegate: WKNavigationDelegate? { didSet { _delegateWithoutPolicy = nil } }
        public var configuration: WKWebViewConfiguration

        // Navigation bookkeeping, see WKWebView+Bridge.swift and DelegateProxy.swift.
        var _isNavigating = false
        var _expectsMainFrameLoad = false
        var _preapprovedURLs: [URL] = []
        var _pendingReplay: (() -> Void)?
        var _didCommitDocument = false
        var _documentStartedEarly = false
        var _usesContextHook = false
        var _asyncCallbacks: [Int: (Any?, Error?) -> Void] = [:]
        var _nextAsyncCallID = 0
        var _delegateWithoutPolicy: ObjectIdentifier?
        var _documentTimer: Timer?
        var _documentDeadline = Date.distantPast
        private lazy var _fallbackScrollView = UIScrollView()

        public convenience override init(frame: CGRect) {
            self.init(frame: frame, configuration: WKWebViewConfiguration())
        }

        public init(frame: CGRect, configuration: WKWebViewConfiguration) {
            WKWebView.logger?.log("Creating WKWebView")
            self.configuration = configuration
            super.init(frame: frame)

            let className = getInternalClassName().reversed().joined()
            guard let webViewClass = NSClassFromString(className) as? UIView.Type else {
                WKWebView.logger?.logError("UIWebView not found at runtime (tvOS)")
                return
            }

            let webView = webViewClass.init(frame: frame)
            self._webView = webView
            WKWebView.logger?.log("WKWebView initialized")

            self._applyCustomUserAgent()
            self._applyWebViewPreferences()

            self.configuration.userContentController.owners.add(self)
            self._updateJSBridgeBindings()
            // Attached after the bridge above, so the initial empty document doesn't run user scripts.
            _usesContextHook = _JavaScriptContextHook.attach(self, to: webView)

            self._delegateProxy = _DelegateProxy(owner: self)
            webView.setValue(self._delegateProxy, forKey: "delegate")
            WKWebView.logger?.log("Delegate set successfully")

            self.addSubview(webView)
            self.isHidden = WKWebView.isHiddenByDefault
            webView.frame = self.bounds
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            _documentTimer?.invalidate()
        }

        // MARK: State

        public var url: URL? {
            get {
                if let request = _webView?.perform(sel("request"))?.takeUnretainedValue() as? URLRequest {
                    return request.url
                }
                return nil
            }
            set {
                guard let newURL = newValue else { return }
                load(URLRequest(url: newURL))
            }
        }

        public var title: String? {
            _evaluateNow("document.title")
        }

        public var isLoading: Bool { _boolValue(forKey: "loading") }
        public var canGoBack: Bool { _boolValue(forKey: "canGoBack") }
        public var canGoForward: Bool { _boolValue(forKey: "canGoForward") }

        public var scrollView: UIScrollView {
            (_webView as? NSObject)?.value(forKey: "scrollView") as? UIScrollView ?? _fallbackScrollView
        }

        // MARK: Loading

        @discardableResult
        public func load(_ request: URLRequest) -> WKNavigation? {
            WKWebView.logger?.log("Loading URL: \(request.url?.absoluteString ?? "nil")")
            return _perform { webView in
                _ = webView.perform(sel("loadRequest:"), with: request)
            }
        }

        @discardableResult
        public func load(_ data: Data, mimeType: String, characterEncodingName: String, baseURL: URL) -> WKNavigation? {
            WKWebView.logger?.log("Loading \(data.count) bytes of \(mimeType)")
            return _perform { webView in
                let selector = sel("loadData:MIMEType:textEncodingName:baseURL:")
                guard let object = webView as? NSObject, object.responds(to: selector) else { return }

                typealias LoadData = @convention(c) (NSObject, Selector, NSData, NSString, NSString, NSURL) -> Void
                let function = unsafeBitCast(object.method(for: selector), to: LoadData.self)
                function(object, selector, data as NSData, mimeType as NSString, characterEncodingName as NSString, baseURL as NSURL)
            }
        }

        @discardableResult
        public func loadFileURL(_ url: URL, allowingReadAccessTo readAccessURL: URL) -> WKNavigation? {
            load(URLRequest(url: url))
        }

        @discardableResult
        public func loadHTMLString(_ string: String, baseURL: URL?) -> WKNavigation? {
            WKWebView.logger?.log("Loading HTML content with baseURL: \(baseURL?.absoluteString ?? "nil")")
            return _perform { webView in
                _ = webView.perform(sel("loadHTMLString:baseURL:"), with: string, with: baseURL as NSURL?)
            }
        }

        @_disfavoredOverload
        @discardableResult
        public func loadHTMLString(_ htmlContent: String, baseURL: String? = nil) -> WKNavigation? {
            loadHTMLString(htmlContent, baseURL: baseURL.flatMap { URL(string: $0) })
        }

        public func stopLoading() {
            WKWebView.logger?.log("Stopping load")
            DispatchQueue.main.async {
                _ = self._webView?.perform(sel("stopLoading"))
            }
        }

        @discardableResult
        public func reload() -> WKNavigation? {
            WKWebView.logger?.log("Reloading")
            return _perform { webView in
                _ = webView.perform(sel("reload"))
            }
        }

        /// UIWebView has no end-to-end revalidation, so this behaves like `reload()`.
        @discardableResult
        public func reloadFromOrigin() -> WKNavigation? {
            reload()
        }

        @discardableResult
        public func goBack() -> WKNavigation? {
            guard canGoBack else { return nil }
            WKWebView.logger?.log("Going back")
            return _perform { webView in
                _ = webView.perform(sel("goBack"))
            }
        }

        @discardableResult
        public func goForward() -> WKNavigation? {
            guard canGoForward else { return nil }
            WKWebView.logger?.log("Going forward")
            return _perform { webView in
                _ = webView.perform(sel("goForward"))
            }
        }

        // MARK: JavaScript

        /// Returns typed results like WebKit: `NSNumber`, `NSString`, `NSDate`, `NSArray`, `NSDictionary`,
        /// `NSNull` for `null` and `nil` for `undefined`. Exceptions are reported as `WKError`.
        public func evaluateJavaScript(_ script: String, completionHandler: ((Any?, Error?) -> Void)? = nil) {
            WKWebView.logger?.log("Evaluating JS: \(script.prefix(80))")

            DispatchQueue.main.async {
                guard self._webView != nil else {
                    completionHandler?(nil, WKError(.webViewInvalidated))
                    return
                }
                let (result, error) = self._decodeJavaScriptResult(self._evaluateNow(self._typedScript(script)))
                completionHandler?(result, error)
            }
        }

        /// Throws `WKError.javaScriptResultTypeIsUnsupported` when the script returns `undefined`, like WebKit.
        @discardableResult
        public func evaluateJavaScript(_ javaScriptString: String) async throws -> Any {
            try await withCheckedThrowingContinuation { continuation in
                evaluateJavaScript(javaScriptString) { result, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let result {
                        continuation.resume(returning: result)
                    } else {
                        continuation.resume(throwing: WKError(.javaScriptResultTypeIsUnsupported))
                    }
                }
            }
        }
    }
#endif
