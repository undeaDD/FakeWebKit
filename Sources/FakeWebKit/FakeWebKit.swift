import UIKit

// MARK: - ✅ - Cookie + DataStore

public struct WKCookie {
    public let name: String
    public let value: String
}

public class WKCookieStore {
    fileprivate let cookieStorage = HTTPCookieStorage.shared

    public func getAllCookies(_ callback: ([WKCookie]) -> Void) {
        let wkCookies = cookieStorage.cookies?.map {
            WKCookie(name: $0.name, value: $0.value)
        } ?? []

        callback(wkCookies)
    }

    public func setCookie(_ cookie: WKCookie) {
        if let httpCookie = HTTPCookie(properties: [
            .name: cookie.name,
            .value: cookie.value
        ]) {
            cookieStorage.setCookie(httpCookie)
        }
    }
}

public struct WKDataStore {
    public let httpCookieStore = WKCookieStore()
}

// MARK: - ✅ - Script Message Handler

public struct WKScriptMessage {
    public let name: String
    public let body: AnyObject
}

public protocol WKScriptMessageHandler : NSObjectProtocol {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage)
}

// MARK: - ✅ - User Scripts + Messaging

public enum WKUserScriptInjectionTime {
    case atDocumentStart
    case atDocumentEnd
}

public struct WKUserScript {
    public let source: String
    public let injectionTime: WKUserScriptInjectionTime
    public let forMainFrameOnly: Bool

    public init(source: String, injectionTime: WKUserScriptInjectionTime = .atDocumentEnd, forMainFrameOnly: Bool = false) {
        self.source = source
        self.injectionTime = injectionTime
        self.forMainFrameOnly = forMainFrameOnly
    }
}

public class WKUserContentController {
    fileprivate weak var owner: WKWebView?
    fileprivate var scripts: [WKUserScript] = []
    fileprivate var scriptMessageHandlers: [String : WKScriptMessageHandler] = [:]

    public func addUserScript(_ script: WKUserScript) {
        scripts.append(script)
    }

    public func removeScriptMessageHandler(forName name: String) {
        scriptMessageHandlers.removeValue(forKey: name)
        Task { @MainActor [weak owner] in
            owner?._updateJSBridgeBindings()
        }
    }

    public func add(_ scriptMessageHandler: any WKScriptMessageHandler, name: String) {
        scriptMessageHandlers[name] = scriptMessageHandler
        Task { @MainActor [weak owner] in
            owner?._updateJSBridgeBindings()
        }
    }
}

// MARK: - ✅ - Configuration

public class WKWebViewConfiguration {
    public init() {}

    public var websiteDataStore = WKDataStore()
    public var userContentController = WKUserContentController()

    public var allowsInlineMediaPlayback: Bool = true {
        didSet {
            precondition(allowsInlineMediaPlayback == true,
                         "allowsInlineMediaPlayback can only be true")
        }
    }

    public var suppressesIncrementalRendering: Bool = false {
        didSet {
            precondition(suppressesIncrementalRendering == false,
                         "suppressesIncrementalRendering can only be false")
        }
    }

    public var allowsAirPlayForMediaPlayback: Bool = false {
        didSet {
            precondition(allowsAirPlayForMediaPlayback == false,
                         "allowsAirPlayForMediaPlayback can only be false")
        }
    }

    public var allowsPictureInPictureMediaPlayback: Bool = false {
        didSet {
            precondition(allowsPictureInPictureMediaPlayback == false,
                         "allowsPictureInPictureMediaPlayback can only be false")
        }
    }

    public var mediaTypesRequiringUserActionForPlayback: [Any] = [] {
        didSet {
            precondition(mediaTypesRequiringUserActionForPlayback.isEmpty,
                         "mediaTypesRequiringUserActionForPlayback must be empty")
        }
    }
}

// MARK: - ✅ - Navigation + Delegates

public struct WKNavigation {
    @available(*, unavailable, message: "The effectiveContentMode property is not supported.")
    public var effectiveContentMode: Any {
        fatalError("This property is unavailable.")
    }
}

public struct WKNavigationAction {
    public let request: URLRequest

    @available(*, unavailable, message: "The navigationType property is not supported.")
    public var navigationType: Any {
        fatalError("This property is unavailable.")
    }
}

public enum WKNavigationActionPolicy {
    case allow
    case cancel

    @available(*, unavailable, message: "The .download policy is not supported.")
    case download
}

@MainActor
public protocol WKNavigationDelegate : NSObjectProtocol {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation)
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation, withError error: Error)
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void)
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation
    )
}

// MARK: - ✅ - WKWebView ( without WebKit )

@MainActor
public class WKWebView: UIView {
    fileprivate var _webView: AnyObject?
    fileprivate var _delegateProxy: _DelegateProxy?
    public static var logger: DebugLogger?

    public var customUserAgent: String? = nil { didSet { _applyCustomUserAgent() } }
    public var navigationDelegate: WKNavigationDelegate? = nil
    public var configuration: WKWebViewConfiguration

    public init(frame: CGRect, configuration: WKWebViewConfiguration) {
        WKWebView.logger?.log("Creating WKWebView")
        self.configuration = configuration
        super.init(frame: frame)

        let className = getInternalClassName().reversed().joined()
        if let webViewClass = NSClassFromString(className) as? UIView.Type {
            self._webView = webViewClass.init(frame: frame)
            WKWebView.logger?.log("WKWebView initialized")

            self._applyCustomUserAgent()
            self._applyWebViewPreferences()

            self.configuration.userContentController.owner = self
            self._updateJSBridgeBindings()

            self._delegateProxy = _DelegateProxy(owner: self)
            if let webView = _webView {
                webView.setValue(self._delegateProxy, forKey: "delegate")
                WKWebView.logger?.log("Delegate set successfully")
            }

            if let webUIView = _webView as? UIView {
                self.addSubview(webUIView)
                self.isHidden = true
                webUIView.frame = self.bounds
                webUIView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            } else {
                WKWebView.logger?.log("⚠️ _webView is no UIView Subclass")
            }
        } else {
            WKWebView.logger?.logError("⚠️ UIWebView not found at runtime (tvOS)")
        }
    }

    required init?(coder: NSCoder) {
        fatalError("⚠️ init(coder:) has not been implemented")
    }

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

    public func load(_ request: URLRequest) {
        WKWebView.logger?.log("Loading URL: \(request.url?.absoluteString ?? "nil")")

        DispatchQueue.main.async {
            _ = self._webView?.perform(sel("loadRequest:"), with: request)
        }
    }

    public func stopLoading() {
        WKWebView.logger?.log("Stopping load")

        DispatchQueue.main.async {
            _ = self._webView?.perform(sel("stopLoading"))
        }
    }

    public func reload() {
        WKWebView.logger?.log("Reloading")

        DispatchQueue.main.async {
            _ = self._webView?.perform(sel("reload"))
        }
    }

    public func loadHTMLString(_ htmlContent: String, baseURL: String? = nil) {
        let base = baseURL.flatMap { URL(string: $0) } as NSURL?
        WKWebView.logger?.log("Loading HTML content with baseURL: \(baseURL ?? "nil")")

        DispatchQueue.main.async {
            let loadHTMLSel = sel("loadHTMLString:baseURL:")
            if self._webView?.responds(to: loadHTMLSel) == true {
                _ = self._webView?.perform(loadHTMLSel, with: htmlContent, with: base)
            } else {
                 WKWebView.logger?.log("⚠️ Selector not found for loadHTMLString:")
            }
        }
    }

    public func evaluateJavaScript(_ script: String, completionHandler: ((Any?, Error?) -> Void)? = nil) {
        WKWebView.logger?.log("Evaluating JS: \(script.prefix(80))")

        DispatchQueue.main.async {
            let result = self._webView?.perform(sel("stringByEvaluatingJavaScriptFromString:"), with: script)
            completionHandler?(result?.takeUnretainedValue(), nil)
        }
    }
}

// MARK: Internal Helper Functions

public protocol DebugLogger {
    func log(_ message: String)
    func logError(_ message: String)
}

@inlinable
func sel(_ name: String) -> Selector { Selector(name) }

fileprivate extension WKWebView {

    @inline(never)
    func getInternalClassName() -> [String] {
        var parts: [String] = []
        parts.append("WebView")
        parts.append("UI")
        return parts
    }

    func _applyCustomUserAgent() {
        if let customUA = customUserAgent {
            WKWebView.logger?.log("Applying custom user agent: \(customUA)")

            UserDefaults.standard.register(defaults: ["UserAgent": customUA])
            if _webView?.responds(to: sel("setCustomUserAgent:")) == true {
                _ = _webView?.perform(sel("setCustomUserAgent:"), with: customUA)
            }
        } else {
            WKWebView.logger?.log("Clearing custom user agent")

            UserDefaults.standard.removeObject(forKey: "UserAgent")
            if _webView?.responds(to: sel("setCustomUserAgent:")) == true {
                _ = _webView?.perform(sel("setCustomUserAgent:"), with: nil)
            }
        }
    }

    func _applyWebViewPreferences() {
        let boolSettings: [(String, Bool)] = [
            ("setScalesPageToFit:", false),
            ("setAllowsLinkPreview:", false),
            ("setKeyboardDisplayRequiresUserAction:", true),
            ("setAllowsInlineMediaPlayback:", true),
            ("setMediaPlaybackRequiresUserAction:", false),
            ("setMediaPlaybackAllowsAirPlay:", false),
            ("setAllowsPictureInPictureMediaPlayback:", false)
        ]

        for (selectorName, value) in boolSettings {
            let selector = sel(selectorName)
            if _webView?.responds(to: selector) == true {
                _ = _webView?.perform(selector, with: value as NSNumber)
                WKWebView.logger?.log("Applied \(selectorName.dropFirst(3)) → \(value)")
            } else {
                WKWebView.logger?.log("⚠️ Missing selector: \(selectorName)")
            }
        }
    }

    @MainActor
    func _updateJSBridgeBindings() {
        let handlerNames = configuration.userContentController.scriptMessageHandlers.keys
        let bridgeJS = """
        (function() {
            window.webkit = window.webkit || {};
            window.webkit.messageHandlers = {};
            \(handlerNames.map { name in
                """
                window.webkit.messageHandlers['\(name)'] = {
                    postMessage: function(data) {
                        window.location = 'jsbridge://\(name)?data=' + encodeURIComponent(JSON.stringify(data));
                    }
                };
                """
            }.joined(separator: "\n"))
        })();
        """

        evaluateJavaScript(bridgeJS)
        WKWebView.logger?.log("Injected JSBridge handlers: \(handlerNames.joined(separator: ", "))")
    }

    func _injectUserScripts(at time: WKUserScriptInjectionTime) -> Int {
        let scriptsToInject = configuration.userContentController.scripts.filter { $0.injectionTime == time }

        for script in scriptsToInject {
            evaluateJavaScript(script.source)
            WKWebView.logger?.log("Injected script at \(time): \(script.source.prefix(60))")
        }

        return scriptsToInject.count
    }

    func _handleJSBridge(request: URLRequest) -> Bool {
        guard let url = request.url, url.scheme == "jsbridge",
              let handlerName = url.host else {
            return false
        }

        var body: AnyObject = [:] as NSDictionary
        if let query = url.query,
           let dataPart = query.removingPercentEncoding?
               .replacingOccurrences(of: "data=", with: "") {
            if let jsonData = dataPart.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as AnyObject {
                body = json
            } else {
                // Fallback: treat as raw string
                body = dataPart as AnyObject
            }
        }

        configuration.userContentController.scriptMessageHandlers[handlerName]?
            .userContentController(configuration.userContentController,
                                   didReceive: WKScriptMessage(name: handlerName, body: body))

        WKWebView.logger?.log("JSBridge message received for '\(handlerName)'")
        return true
    }
}

@objc
@MainActor
fileprivate class _DelegateProxy: NSObject {
    fileprivate weak var owner: WKWebView?

    init(owner: WKWebView) {
        self.owner = owner
        super.init()

        WKWebView.logger?.log("_DelegateProxy initialized")
    }

    override func responds(to aSelector: Selector!) -> Bool {
        let selectorString = String(describing: aSelector)
        let implementedSelectors = [
            "webViewDidStartLoad:",
            "webViewDidFinishLoad:",
            "webView:didFailLoadWithError:",
            "webView:shouldStartLoadWithRequest:navigationType:"
        ]
        return implementedSelectors.contains(selectorString) || super.responds(to: aSelector)
    }

    @objc
    func webViewDidStartLoad(_ webView: AnyObject) {
        WKWebView.logger?.log("webViewDidStartLoad")
        guard let owner else {
            WKWebView.logger?.log("owner has been deallocated, canceling callback")
            return
        }

        do {
            owner._updateJSBridgeBindings()
            let count = owner._injectUserScripts(at: .atDocumentStart)
            WKWebView.logger?.log("Injected \(count) user scripts at document start")
        } catch let error {
            WKWebView.logger?.logError("Failed injecting scripts at document start: \(error)")
        }

        owner.navigationDelegate?.webView(owner, didStartProvisionalNavigation: WKNavigation())
    }

    @objc
    func webViewDidFinishLoad(_ webView: AnyObject) {
        WKWebView.logger?.log("webViewDidFinishLoad")
        guard let owner else {
            WKWebView.logger?.log("owner has been deallocated, canceling callback")
            return
        }

        do {
            owner._updateJSBridgeBindings()
            let count = owner._injectUserScripts(at: .atDocumentEnd)
            WKWebView.logger?.log("Injected \(count) user scripts at document end")
        } catch let error {
            WKWebView.logger?.logError("Failed injecting scripts at document end: \(error)")
        }

        owner.navigationDelegate?.webView(owner, didFinish: WKNavigation())
    }

    @objc
    func webView(_ webView: AnyObject, didFailLoadWithError error: NSError) {
        if let failingURL = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL,
           failingURL.scheme == "jsbridge" {
            // Suppress fake jsbridge:// URL errors
            return
        }

        WKWebView.logger?.logError("Error: \(error)")
        guard let owner else {
            WKWebView.logger?.log("owner has been deallocated, canceling callback")
            return
        }

        owner.navigationDelegate?.webView(owner, didFail: WKNavigation(), withError: error)
    }

    @objc(webView:shouldStartLoadWithRequest:navigationType:)
    func webView_shouldStartLoadWithRequest(_ webView: AnyObject, shouldStartLoadWithRequest request: URLRequest, navigationType: Int) -> Bool {
        return handleShouldStartLoad(request: request, navigationType: navigationType)
    }

    @objc
    func webView(_ webView: AnyObject, shouldStartLoadWith request: URLRequest, navigationType: Int) -> Bool {
        return handleShouldStartLoad(request: request, navigationType: navigationType)
    }

    private func handleShouldStartLoad(request: URLRequest, navigationType: Int) -> Bool {
        guard let owner else {
            WKWebView.logger?.log("owner has been deallocated, canceling callback")
            return true
        }

        if owner._handleJSBridge(request: request) { return false }

        WKWebView.logger?.log("Navigation request: \(request.url?.absoluteString ?? "nil") (Type: \(navigationType))")

        let action = WKNavigationAction(request: request)
        var decision: WKNavigationActionPolicy = .allow
        let semaphore = DispatchSemaphore(value: 0)

        // Call on main thread if we're not already there
        if Thread.isMainThread {
            owner.navigationDelegate?.webView(owner, decidePolicyFor: action) { policy in
                decision = policy
                semaphore.signal()
            }
        } else {
            DispatchQueue.main.async {
                owner.navigationDelegate?.webView(owner, decidePolicyFor: action) { policy in
                    decision = policy
                    semaphore.signal()
                }
            }
        }

        let timeout = DispatchTime.now() + .seconds(5)
        if semaphore.wait(timeout: timeout) == .timedOut {
            WKWebView.logger?.log("Decision timeout → defaulting to ALLOW")
        }

        WKWebView.logger?.log("Decision: \(decision == .allow ? "ALLOW" : "CANCEL")")
        return decision == .allow
    }
}
