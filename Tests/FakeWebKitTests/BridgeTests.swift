#if os(tvOS)
    @testable import FakeWebKit
    import XCTest

    @MainActor
    final class BridgeTests: XCTestCase {
        private var logger: TestLogger!

        override func setUp() {
            super.setUp()
            logger = TestLogger()
            WKWebView.logger = logger
        }

        override func tearDown() {
            WKWebView.logger = nil
            WKWebView._allowsImmediatePolicyTasks = true
            super.tearDown()
        }

        private func makeWebView(_ configuration: WKWebViewConfiguration = WKWebViewConfiguration()) -> WKWebView {
            WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 360), configuration: configuration)
        }

        private func loadAndWait(_ webView: WKWebView, html: String, baseURL: URL? = nil,
                                 file: StaticString = #filePath, line: UInt = #line) {
            let delegate = webView.navigationDelegate as? RecordingDelegate ?? RecordingDelegate()
            if webView.navigationDelegate == nil { webView.navigationDelegate = delegate }
            let finished = delegate.events.filter { $0 == "finish" }.count
            webView.loadHTMLString(html, baseURL: baseURL)
            waitUntil(file: file, line: line) { delegate.events.filter { $0 == "finish" }.count > finished }
        }

        // MARK: JavaScript

        func testUserScriptsRunAtDocumentStartAndEnd() {
            let configuration = WKWebViewConfiguration()
            configuration.userContentController.addUserScript(
                WKUserScript(source: "window.order = (window.order || []).concat('start');", injectionTime: .atDocumentStart)
            )
            configuration.userContentController.addUserScript(
                WKUserScript(source: "window.order = (window.order || []).concat('end:' + document.readyState);",
                             injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            )
            let webView = makeWebView(configuration)

            loadAndWait(webView, html: "<p>first</p>")
            XCTAssertEqual(webView._evaluateNow("window.order.join(',')")?.hasPrefix("start,end:"), true)

            loadAndWait(webView, html: "<p>second</p>")
            XCTAssertEqual(webView._evaluateNow("String(window.order.length)"), "2")
            XCTAssertNil(webView._documentTimer)
        }

        func testDocumentTrackingStopsAfterDeadline() {
            let webView = makeWebView()
            webView._startDocumentTimer()
            XCTAssertNotNil(webView._documentTimer)

            webView._documentDeadline = .distantPast
            webView._documentTick()
            XCTAssertNil(webView._documentTimer)
        }

        // MARK: Script messages

        func testScriptMessagesAreDeliveredInOrder() {
            let configuration = WKWebViewConfiguration()
            let recorder = MessageRecorder()
            configuration.userContentController.add(recorder, name: "logger")
            let webView = makeWebView(configuration)

            loadAndWait(webView, html: "<p>messages</p>")
            webView._evaluateNow("""
            window.webkit.messageHandlers.logger.postMessage({ url: 'https://a.test', type: 'cookies', cookies: { a: '1' } });
            window.webkit.messageHandlers.logger.postMessage('plain string');
            window.webkit.messageHandlers.logger.postMessage(42);
            window.webkit.messageHandlers.logger.postMessage();
            """)
            waitUntil { recorder.messages.count == 4 }

            let first = recorder.messages[0]
            XCTAssertEqual(first.name, "logger")
            XCTAssertTrue(first.webView === webView)
            let body = first.body as? [String: Any]
            XCTAssertEqual(body?["url"] as? String, "https://a.test")
            XCTAssertEqual((body?["cookies"] as? [String: String])?["a"], "1")
            XCTAssertEqual(recorder.messages[1].body as? String, "plain string")
            XCTAssertEqual(recorder.messages[2].body as? Int, 42)
            XCTAssertTrue(recorder.messages[3].body is NSNull)
        }

        func testInlineScriptsCanPostMessagesWhileThePageLoads() {
            let configuration = WKWebViewConfiguration()
            let recorder = MessageRecorder()
            configuration.userContentController.add(recorder, name: "logger")
            configuration.userContentController.addUserScript(
                WKUserScript(source: "window.startScript = 'ran';", injectionTime: .atDocumentStart)
            )
            let webView = makeWebView(configuration)
            loadAndWait(webView, html: "<p>first</p>")
            recorder.messages.removeAll()

            // A new origin gets a fresh window, so nothing from the previous document carries over.
            loadAndWait(webView, html: """
            <html><head><script>
            window.webkit.messageHandlers.logger.postMessage({ phase: 'head', startScript: window.startScript });
            </script></head>
            <body><iframe srcdoc="<p>subframe</p>"></iframe>
            <script>window.webkit.messageHandlers.logger.postMessage('body');</script></body></html>
            """, baseURL: URL(string: "https://inline.fakewebkit.test/"))
            waitUntil { recorder.messages.count == 2 }

            let head = recorder.messages.first?.body as? [String: Any]
            XCTAssertEqual(head?["phase"] as? String, "head")
            XCTAssertEqual(head?["startScript"] as? String, "ran")
            XCTAssertEqual(recorder.messages.last?.body as? String, "body")
            XCTAssertEqual(webView._evaluateNow("String(window.startScript)"), "ran")
        }

        func testJavaScriptContextHookFallsBackToPolling() {
            let configuration = WKWebViewConfiguration()
            configuration.userContentController.add(MessageRecorder(), name: "logger")
            configuration.userContentController.addUserScript(
                WKUserScript(source: "window.startScript = 'polled';", injectionTime: .atDocumentStart)
            )
            let webView = makeWebView(configuration)
            XCTAssertFalse(_JavaScriptContextHook.attach(webView, to: NSObject()))
            XCTAssertTrue(logger.messages.contains("JavaScript context hook unavailable, polling only"))

            // A delegate class with its own implementation is left alone.
            XCTAssertFalse(_JavaScriptContextHook._hook(ContextAwareDelegate.self))

            // Delegates without an owner are ignored.
            _JavaScriptContextHook._didCreateContext(delegate: NSObject(), webView: NSObject(), context: NSObject(), frame: NSObject())

            // Without the hook, polling starts a document that has no marker yet.
            loadAndWait(webView, html: "<p>polling</p>")
            webView._evaluateNow("delete window.__fakeWebKitDocument; delete window.webkit; delete window.startScript;")
            webView._documentDeadline = .distantFuture
            webView._documentTick()
            XCTAssertEqual(webView._evaluateNow("typeof window.webkit.messageHandlers.logger"), "object")
            XCTAssertEqual(webView._evaluateNow("window.startScript"), "polled")
            XCTAssertEqual(webView._evaluateNow("window.__fakeWebKitDocument"), "end")
        }

        func testHandlersAddedAfterLoadAreAvailable() {
            let webView = makeWebView()
            loadAndWait(webView, html: "<p>late handler</p>")

            let recorder = MessageRecorder()
            webView.configuration.userContentController.add(recorder, name: "late")
            webView._evaluateNow("window.webkit.messageHandlers.late.postMessage('hi')")
            waitUntil { recorder.messages.count == 1 }

            webView.configuration.userContentController.removeScriptMessageHandler(forName: "late")
            XCTAssertEqual(webView._evaluateNow("typeof window.webkit.messageHandlers.late"), "undefined")
        }

        func testBridgeIgnoresInvalidPayloadsAndUnknownHandlers() throws {
            let webView = makeWebView()
            webView._deliverMessages("not json")
            XCTAssertTrue(logger.errors.contains("Invalid JSBridge payload"))

            webView._deliverMessages("[{\"body\": 1}, {\"name\": \"unknown\", \"body\": 2}]")
            spin(0.05)

            let other = URLRequest(url: try XCTUnwrap(URL(string: "jsbridge://legacy?data=1")))
            XCTAssertTrue(webView._handleJSBridge(request: other))
            let http = URLRequest(url: try XCTUnwrap(URL(string: "https://fakewebkit.test")))
            XCTAssertFalse(webView._handleJSBridge(request: http))
        }

        // MARK: Delegate proxy

        func testDelegateProxyAnswersForUIWebViewSelectors() throws {
            let webView = makeWebView()
            let proxy = try XCTUnwrap(webView._delegateProxy)
            XCTAssertTrue(proxy.responds(to: sel("webViewDidFinishLoad:")))
            XCTAssertTrue(proxy.responds(to: sel("webView:shouldStartLoadWithRequest:navigationType:")))
            XCTAssertFalse(proxy.responds(to: sel("webView:unknownSelector:")))
        }

        func testDelegateProxySuppressesBridgeErrors() throws {
            let webView = makeWebView()
            let delegate = RecordingDelegate()
            webView.navigationDelegate = delegate
            webView._isNavigating = true
            let proxy = try XCTUnwrap(webView._delegateProxy)

            let bridgeURL = try XCTUnwrap(URL(string: "jsbridge://__flush__"))
            proxy.webView(webView, didFailLoadWithError: NSError(domain: NSURLErrorDomain, code: -1,
                                                                  userInfo: [NSURLErrorFailingURLErrorKey: bridgeURL]))
            XCTAssertTrue(delegate.events.isEmpty)

            proxy.webView(webView, didFailLoadWithError: NSError(domain: NSURLErrorDomain, code: -1))
            XCTAssertEqual(delegate.events, ["fail-provisional"])

            webView._isNavigating = true
            webView._didCommitDocument = true
            proxy.webView(webView, didFailLoadWithError: NSError(domain: NSURLErrorDomain, code: -1))
            XCTAssertEqual(delegate.events, ["fail-provisional", "fail"])
        }

        func testDelegateProxyWithoutOwner() throws {
            let request = URLRequest(url: try XCTUnwrap(URL(string: "https://fakewebkit.test")))
            var proxy: _DelegateProxy?
            autoreleasepool {
                proxy = _DelegateProxy(owner: makeWebView())
            }
            let orphan = try XCTUnwrap(proxy)
            XCTAssertNil(orphan.owner)

            orphan.webViewDidStartLoad(NSObject())
            orphan.webViewDidFinishLoad(NSObject())
            orphan.webView(NSObject(), didFailLoadWithError: NSError(domain: "test", code: 1))
            XCTAssertTrue(orphan.webView_shouldStartLoadWithRequest(NSObject(), shouldStartLoadWithRequest: request, navigationType: 0))
            XCTAssertEqual(logger.messages.filter { $0 == "owner has been deallocated, canceling callback" }.count, 4)
        }
    }

    private final class ContextAwareDelegate: NSObject {
        @objc(webView:didCreateJavaScriptContext:forFrame:)
        func webView(_ webView: NSObject, didCreateJavaScriptContext context: NSObject, forFrame frame: NSObject) {}
    }
#endif
