#if os(tvOS)
    import UIKit

    // MARK: - Internal helpers

    extension WKWebView {
        static let bridgeScheme = "jsbridge"
        static let flushHost = "__flush__"
        static let documentPollInterval: TimeInterval = 0.016
        static let documentPollTimeout: TimeInterval = 30

        /// Switches the default policy bridge to `Task.immediate` where available. Tests turn it off
        /// to exercise the deferred path that older tvOS versions use.
        static var _allowsImmediatePolicyTasks = true

        @inline(never)
        func getInternalClassName() -> [String] {
            var parts: [String] = []
            parts.append("WebView")
            parts.append("UI")
            return parts
        }

        /// Runs a main-frame load on the main queue and returns a navigation token. The load is kept
        /// until its first policy check, so a deferred decision can repeat the original call.
        func _perform(_ body: @escaping (AnyObject) -> Void) -> WKNavigation? {
            guard _webView != nil else { return nil }

            DispatchQueue.main.async { [weak self] in
                guard let self, let webView = self._webView else { return }
                let replay = { [weak self] in
                    self?._expectsMainFrameLoad = true
                    body(webView)
                }
                replay()
                self._pendingReplay = replay
            }
            return WKNavigation()
        }

        func _boolValue(forKey key: String) -> Bool {
            (_webView as? NSObject)?.value(forKey: key) as? Bool ?? false
        }

        /// Evaluates JavaScript synchronously. Must be called on the main thread.
        @discardableResult
        func _evaluateNow(_ script: String) -> String? {
            _webView?.perform(sel("stringByEvaluatingJavaScriptFromString:"), with: script)?.takeUnretainedValue() as? String
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
                ("scalesPageToFit", false),
                ("allowsLinkPreview", false),
                ("keyboardDisplayRequiresUserAction", true),
                ("allowsInlineMediaPlayback", true),
                ("mediaPlaybackRequiresUserAction", false),
                ("mediaPlaybackAllowsAirPlay", false),
                ("allowsPictureInPictureMediaPlayback", false),
            ]

            guard let webView = _webView as? NSObject else { return }
            for (key, value) in boolSettings {
                let setter = sel("set\(key.prefix(1).uppercased())\(key.dropFirst()):")
                if webView.responds(to: setter) {
                    // KVC unboxes the NSNumber into a real BOOL argument.
                    webView.setValue(value, forKey: key)
                    WKWebView.logger?.log("Applied \(key) -> \(value)")
                } else {
                    WKWebView.logger?.log("Missing selector: \(NSStringFromSelector(setter))")
                }
            }
        }

        // MARK: Typed JavaScript results

        /// Wraps a script so its result comes back as JSON instead of UIWebView's string conversion.
        func _typedScript(_ script: String) -> String {
            """
            (function() {
                var r;
                try { r = (0, eval)(\(jsStringLiteral(script))); }
                catch (e) { return JSON.stringify({ e: String(e && e.message !== undefined ? e.message : e) }); }
                if (r === undefined) { return '{"u":1}'; }
                if (typeof r === 'function' || typeof r === 'symbol') { return '{"x":1}'; }
                if (r instanceof Date) { return JSON.stringify({ d: r.getTime() }); }
                try { var s = JSON.stringify({ v: r }); return s === undefined ? '{"x":1}' : s; }
                catch (e) { return '{"x":1}'; }
            })()
            """
        }

        func _decodeJavaScriptResult(_ payload: String?) -> (Any?, Error?) {
            guard let data = payload?.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return (nil, WKError(.javaScriptResultTypeIsUnsupported))
            }

            if let value = json["v"] {
                return (value, nil)
            }
            if let milliseconds = json["d"] as? Double {
                return (Date(timeIntervalSince1970: milliseconds / 1000), nil)
            }
            if let message = json["e"] as? String {
                return (nil, WKError(.javaScriptExceptionOccurred, userInfo: [
                    NSLocalizedDescriptionKey: "A JavaScript exception occurred",
                    "WKJavaScriptExceptionMessage": message,
                ]))
            }
            if json["u"] != nil {
                return (nil, nil)
            }
            return (nil, WKError(.javaScriptResultTypeIsUnsupported))
        }

        // MARK: Script message bridge

        /// Installs `window.webkit.messageHandlers`. Messages are queued in the page and fetched
        /// in one batch, so several `postMessage` calls in the same tick are all delivered.
        func _bridgeScript() -> String {
            let handlers = configuration.userContentController.scriptMessageHandlers.keys.sorted().map { name in
                let literal = jsStringLiteral(name)
                return "w.webkit.messageHandlers[\(literal)] = { postMessage: function(data) { post(\(literal), data); } };"
            }

            return """
            (function() {
                var w = window;
                w.webkit = w.webkit || {};
                w.webkit.messageHandlers = {};
                w.__fakeWebKitQueue = w.__fakeWebKitQueue || [];
                w.__fakeWebKitFlush = function() {
                    var queue = w.__fakeWebKitQueue;
                    w.__fakeWebKitQueue = [];
                    return '[' + queue.join(',') + ']';
                };
                var post = w.__fakeWebKitPost = function(name, data) {
                    w.__fakeWebKitQueue.push(JSON.stringify({ name: name, body: data === undefined ? null : data }));
                    var frame = document.createElement('iframe');
                    frame.style.display = 'none';
                    frame.src = '\(WKWebView.bridgeScheme)://\(WKWebView.flushHost)';
                    (document.body || document.documentElement).appendChild(frame);
                    setTimeout(function() { if (frame.parentNode) { frame.parentNode.removeChild(frame); } }, 0);
                };
                \(handlers.joined(separator: "\n    "))
            })();
            """
        }

        func _updateJSBridgeBindings() {
            let script = _bridgeScript()
            let handlerNames = configuration.userContentController.scriptMessageHandlers.keys.sorted()

            if Thread.isMainThread {
                _evaluateNow(script)
            } else {
                DispatchQueue.main.async { self._evaluateNow(script) }
            }
            WKWebView.logger?.log("Injected JSBridge handlers: \(handlerNames.joined(separator: ", "))")
        }

        func _handleJSBridge(request: URLRequest) -> Bool {
            guard let url = request.url, url.scheme == WKWebView.bridgeScheme else { return false }

            if url.host == WKWebView.flushHost, let payload = _evaluateNow("window.__fakeWebKitFlush ? window.__fakeWebKitFlush() : '[]'") {
                _deliverMessages(payload)
            }
            return true
        }

        func _deliverMessages(_ payload: String) {
            guard let data = payload.data(using: .utf8),
                  let messages = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                WKWebView.logger?.logError("Invalid JSBridge payload")
                return
            }

            let controller = configuration.userContentController
            for message in messages {
                guard let name = message["name"] as? String else { continue }
                let body = (message["body"] ?? NSNull()) as AnyObject

                DispatchQueue.main.async { [weak self] in
                    if name == WKWebView.asyncResultHandler {
                        self?._finishAsyncCall(body)
                        return
                    }
                    guard let handler = controller.scriptMessageHandlers[name] else { return }
                    handler.userContentController(controller, didReceive: WKScriptMessage(name: name, body: body, webView: self))
                    WKWebView.logger?.log("JSBridge message received for '\(name)'")
                }
            }
        }

        // MARK: User scripts

        @discardableResult
        func _injectUserScripts(at time: WKUserScriptInjectionTime) -> Int {
            let scriptsToInject = configuration.userContentController.scripts.filter { $0.injectionTime == time }

            for script in scriptsToInject {
                _evaluateNow(script.source)
                WKWebView.logger?.log("Injected script at \(time): \(script.source.prefix(60))")
            }

            return scriptsToInject.count
        }

        /// Marks the current document as started, then installs the bridge and runs the `.atDocumentStart`
        /// scripts through `evaluate`. Called by the JavaScript context hook or, as a fallback, by polling.
        func _startDocument(evaluate: (String) -> String?) {
            // The hook and polling can both see a new document, the first one claims it.
            let claim = "(function() { var d = window.__fakeWebKitDocument;"
                + " if (d === 'start' || d === 'end') { return '0'; } window.__fakeWebKitDocument = 'start'; return '1'; })()"
            guard evaluate(claim) == "1" else { return }
            _ = evaluate(_bridgeScript())
            let scripts = configuration.userContentController.scripts.filter { $0.injectionTime == .atDocumentStart }
            scripts.forEach { _ = evaluate($0.source) }
            WKWebView.logger?.log("Injected bridge and \(scripts.count) user scripts at document start")

            if _usesContextHook { _startDocumentTimer() }
            if _isNavigating {
                _commitIfNeeded()
            } else {
                // The JavaScript context hook can run before UIWebView reports the navigation start.
                _documentStartedEarly = true
            }
        }

        func _commitIfNeeded() {
            guard _isNavigating, !_didCommitDocument else { return }
            _didCommitDocument = true
            let delegate = navigationDelegate
            delegate?.webView(self, didCommit: WKNavigation())
            delegate?.webView(self, didCommit: WKNavigation() as WKNavigation?)
        }

        /// The JavaScript context hook (JavaScriptContextHook.swift) usually starts a new document before its
        /// first script runs. As a fallback, the current document gets marked as stale when a main-frame load
        /// starts and the web view is polled until a new document shows up (atDocumentStart) and until it
        /// finished parsing (atDocumentEnd).
        func _beginDocumentTracking() {
            _didCommitDocument = false
            _failPendingAsyncCalls()
            _documentStartedEarly = false

            // With the hook, the new document is claimed by the hook (in any order relative to this call),
            // which then starts the timer for the atDocumentEnd scripts.
            guard !_usesContextHook else { return }
            _evaluateNow("window.__fakeWebKitDocument = 'stale'")
            _startDocumentTimer()
        }

        func _startDocumentTimer() {
            _documentTimer?.invalidate()
            _documentDeadline = Date().addingTimeInterval(WKWebView.documentPollTimeout)

            let timer = Timer(timeInterval: WKWebView.documentPollInterval, repeats: true) { [weak self] _ in
                self?._documentTick()
            }
            RunLoop.main.add(timer, forMode: .common)
            _documentTimer = timer
        }

        func _endDocumentTracking() {
            _documentTimer?.invalidate()
            _documentTimer = nil
        }

        func _documentTick() {
            guard Date() < _documentDeadline,
                  let state = _evaluateNow("(window.__fakeWebKitDocument || '') + '|' + document.readyState"),
                  let separator = state.firstIndex(of: "|") else {
                if Date() >= _documentDeadline { _endDocumentTracking() }
                return
            }

            var marker = String(state[..<separator])
            let readyState = String(state[state.index(after: separator)...])

            if marker.isEmpty {
                _startDocument { _evaluateNow($0) }
                marker = "start"
            }

            if marker == "start", readyState == "interactive" || readyState == "complete" {
                _evaluateNow("window.__fakeWebKitDocument = 'end'")
                _updateJSBridgeBindings()
                let count = _injectUserScripts(at: .atDocumentEnd)
                WKWebView.logger?.log("Injected \(count) user scripts at document end")
                marker = "end"
            }

            if marker == "end" {
                _endDocumentTracking()
            }
        }

        // MARK: Navigation policy

        /// Runs a default policy decision on the main actor, synchronously when the system supports it.
        static func _resolvePolicy(_ operation: @escaping @MainActor () async -> WKNavigationActionPolicy,
                                   completion: @escaping (WKNavigationActionPolicy) -> Void) {
            #if compiler(>=6.2)
                if _allowsImmediatePolicyTasks, #available(tvOS 26.0, *) {
                    Task.immediate { @MainActor in completion(await operation()) }
                    return
                }
            #endif
            Task { @MainActor in completion(await operation()) }
        }

        /// Asks the navigation delegate for a policy. Returns `nil` when the decision did not arrive
        /// synchronously; `deferred` is then called on the main thread once it does.
        func _decidePolicy(for action: WKNavigationAction,
                           deferred: @escaping (WKNavigationActionPolicy) -> Void) -> WKNavigationActionPolicy? {
            guard let delegate = navigationDelegate else { return .allow }
            let delegateID = ObjectIdentifier(delegate)
            if _delegateWithoutPolicy == delegateID { return .allow }

            final class Decision {
                var policy: WKNavigationActionPolicy?
                var isPending = true
                var isAnswered = false
            }

            let decision = Decision()
            let probe = _PolicyProbe()

            _PolicyProbe.$current.withValue(probe) {
                delegate.webView(self, decidePolicyFor: action) { [weak self] policy in
                    let deliver = {
                        guard !decision.isAnswered else { return }
                        decision.isAnswered = true

                        if decision.isPending {
                            decision.policy = policy
                            return
                        }
                        if probe.usedDefaultImplementation {
                            self?._delegateWithoutPolicy = delegateID
                        }
                        deferred(policy)
                    }

                    if Thread.isMainThread { deliver() } else { DispatchQueue.main.async(execute: deliver) }
                }
            }

            decision.isPending = false
            return decision.policy
        }
    }
#endif
