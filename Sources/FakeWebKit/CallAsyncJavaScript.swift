#if os(tvOS)
    import Foundation

    // MARK: - Content worlds

    /// UIWebView has a single JavaScript world, so every content world runs in the page world.
    /// The type exists so `callAsyncJavaScript(_:arguments:in:contentWorld:)` call sites compile unchanged.
    public final class WKContentWorld {
        public let name: String?

        private init(name: String?) {
            self.name = name
        }

        public static let page = WKContentWorld(name: nil)
        public static let defaultClient = WKContentWorld(name: "defaultClient")

        public static func world(name: String) -> WKContentWorld {
            WKContentWorld(name: name)
        }
    }

    // MARK: - callAsyncJavaScript

    extension WKWebView {
        static let asyncResultHandler = "__fakeWebKitAsyncResult"

        /// Runs `functionBody` as the body of an async JavaScript function whose parameters are the keys of
        /// `arguments`. A returned promise is awaited. `frame` and `contentWorld` are accepted for WebKit
        /// compatibility; scripts always run in the main frame's page world.
        public func callAsyncJavaScript(_ functionBody: String, arguments: [String: Any] = [:], in frame: WKFrameInfo? = nil,
                                        in contentWorld: WKContentWorld,
                                        completionHandler: ((Result<Any, Error>) -> Void)? = nil) {
            _callAsync(functionBody, arguments: arguments) { value, error in
                if let error {
                    completionHandler?(.failure(error))
                } else {
                    completionHandler?(.success(value ?? NSNull()))
                }
            }
        }

        public func callAsyncJavaScript(_ functionBody: String, arguments: [String: Any] = [:], in frame: WKFrameInfo? = nil,
                                        contentWorld: WKContentWorld) async throws -> Any? {
            try await withCheckedThrowingContinuation { continuation in
                _callAsync(functionBody, arguments: arguments) { value, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: value)
                    }
                }
            }
        }

        func _callAsync(_ functionBody: String, arguments: [String: Any], completion: @escaping (Any?, Error?) -> Void) {
            WKWebView.logger?.log("Calling async JS: \(functionBody.prefix(80))")

            DispatchQueue.main.async {
                guard self._webView != nil else {
                    completion(nil, WKError(.webViewInvalidated))
                    return
                }
                guard JSONSerialization.isValidJSONObject(arguments),
                      let argumentData = try? JSONSerialization.data(withJSONObject: arguments),
                      let argumentJSON = String(data: argumentData, encoding: .utf8) else {
                    completion(nil, WKError(.unknown, userInfo: [NSLocalizedDescriptionKey: "Arguments must be JSON serializable"]))
                    return
                }

                self._nextAsyncCallID += 1
                let id = self._nextAsyncCallID
                self._asyncCallbacks[id] = completion
                self._evaluateNow(self._asyncScript(id: id, body: functionBody, argumentJSON: argumentJSON))
            }
        }

        func _asyncScript(id: Int, body: String, argumentJSON: String) -> String {
            """
            (function() {
                var w = window;
                if (typeof w.__fakeWebKitPost !== 'function') { \(_bridgeScript()) }
                var report = function(payload) { w.__fakeWebKitPost(\(jsStringLiteral(WKWebView.asyncResultHandler)), { id: \(id), r: payload }); };
                var encode = function(r) {
                    if (r === undefined) { return '{"u":1}'; }
                    if (typeof r === 'function' || typeof r === 'symbol') { return '{"x":1}'; }
                    if (r instanceof Date) { return JSON.stringify({ d: r.getTime() }); }
                    try { var s = JSON.stringify({ v: r }); return s === undefined ? '{"x":1}' : s; }
                    catch (e) { return '{"x":1}'; }
                };
                var fail = function(e) { report(JSON.stringify({ e: String(e && e.message !== undefined ? e.message : e) })); };
                try {
                    var args = \(argumentJSON);
                    var names = Object.keys(args);
                    var AsyncFunction = Object.getPrototypeOf(async function() {}).constructor;
                    var fn = AsyncFunction.apply(null, names.concat([\(jsStringLiteral(body))]));
                    fn.apply(w, names.map(function(n) { return args[n]; })).then(function(r) { report(encode(r)); }, fail);
                } catch (e) { fail(e); }
            })();
            """
        }

        func _finishAsyncCall(_ body: Any) {
            guard let message = body as? [String: Any],
                  let id = message["id"] as? Int,
                  let completion = _asyncCallbacks.removeValue(forKey: id) else { return }

            let (value, error) = _decodeJavaScriptResult(message["r"] as? String)
            completion(value, error)
        }

        /// A navigation replaces the document, so promises of the old one can never report back.
        func _failPendingAsyncCalls() {
            let callbacks = _asyncCallbacks
            _asyncCallbacks.removeAll()
            for completion in callbacks.values {
                let reason = "The page navigated before the async JavaScript finished"
                completion(nil, WKError(.unknown, userInfo: [NSLocalizedDescriptionKey: reason]))
            }
        }
    }
#endif
