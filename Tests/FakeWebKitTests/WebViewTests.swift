#if os(tvOS)
    @testable import FakeWebKit
    import XCTest

    @MainActor
    final class WebViewTests: XCTestCase {
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

        private func loadAndWait(_ webView: WKWebView, html: String, file: StaticString = #filePath, line: UInt = #line) {
            let delegate = webView.navigationDelegate as? RecordingDelegate ?? RecordingDelegate()
            if webView.navigationDelegate == nil { webView.navigationDelegate = delegate }
            let finished = delegate.events.filter { $0 == "finish" }.count
            webView.loadHTMLString(html, baseURL: nil)
            waitUntil(file: file, line: line) { delegate.events.filter { $0 == "finish" }.count > finished }
        }

        // MARK: Setup

        func testInitCreatesBackingWebView() {
            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
            XCTAssertNotNil(webView._webView)
            XCTAssertEqual(webView.subviews.count, 1)
            XCTAssertTrue(webView.configuration.userContentController.owners.contains(webView))
            XCTAssertTrue(logger.messages.contains("Applied scalesPageToFit -> false"))
            XCTAssertNotNil(webView.scrollView)
        }

        func testWebViewWithoutBackingView() {
            let webView = makeWebView()
            webView._webView = nil

            XCTAssertNil(webView.load(URLRequest(url: FileManager.default.temporaryDirectory)))
            XCTAssertNil(webView.reload())
            XCTAssertNil(webView.url)
            XCTAssertNil(webView.title)
            XCTAssertFalse(webView.isLoading)
            XCTAssertTrue(webView.scrollView === webView.scrollView)
            webView._applyWebViewPreferences()
        }

        func testIsHiddenByDefault() {
            defer { WKWebView.isHiddenByDefault = true }
            XCTAssertTrue(makeWebView().isHidden)

            WKWebView.isHiddenByDefault = false
            let visible = makeWebView()
            XCTAssertFalse(visible.isHidden)
            visible.isHidden = true
            XCTAssertTrue(visible.isHidden)
        }

        func testNavigationDelegateIsWeak() {
            let webView = makeWebView()
            autoreleasepool {
                let delegate = RecordingDelegate()
                webView.navigationDelegate = delegate
                XCTAssertNotNil(webView.navigationDelegate)
            }
            XCTAssertNil(webView.navigationDelegate)
        }

        func testCustomUserAgent() {
            let webView = makeWebView()
            webView.customUserAgent = "FakeWebKitTests/1.0"
            XCTAssertEqual(UserDefaults.standard.string(forKey: "UserAgent"), "FakeWebKitTests/1.0")
            XCTAssertTrue(logger.messages.contains("Applying custom user agent: FakeWebKitTests/1.0"))

            webView.customUserAgent = nil
            XCTAssertTrue(logger.messages.contains("Clearing custom user agent"))
        }

        // MARK: Loading

        func testLoadHTMLStringFiresNavigationEventsOnce() {
            let webView = makeWebView()
            let delegate = RecordingDelegate()
            webView.navigationDelegate = delegate

            webView.loadHTMLString("<html><head><title>Hello</title></head><body><iframe src='about:blank'></iframe></body></html>",
                                   baseURL: URL(string: "https://fakewebkit.test/"))
            waitUntil { delegate.events.contains("finish") }
            spin(0.3)

            XCTAssertEqual(delegate.events, ["start", "commit", "finish"])
            XCTAssertEqual(webView.title, "Hello")
            XCTAssertFalse(webView.isLoading)
            XCTAssertEqual(delegate.actions.first?.targetFrame?.isMainFrame, true)
        }

        func testLegacyLoadHTMLStringWithStringBaseURL() {
            let webView = makeWebView()
            let delegate = RecordingDelegate()
            webView.navigationDelegate = delegate

            XCTAssertNotNil(webView.loadHTMLString("<title>Legacy</title>"))
            waitUntil { delegate.events.contains("finish") }
            XCTAssertEqual(webView.title, "Legacy")

            webView.loadHTMLString("<title>Base</title>", baseURL: "https://fakewebkit.test/")
            waitUntil { delegate.events.filter { $0 == "finish" }.count == 2 }
            XCTAssertEqual(webView.url?.host, "fakewebkit.test")
        }

        func testWebKitStyleDelegateReceivesEvents() {
            let webView = makeWebView()
            let delegate = WebKitStyleDelegate()
            webView.navigationDelegate = delegate

            webView.loadHTMLString("<p>hi</p>", baseURL: URL(string: "https://fakewebkit.test/"))
            waitUntil { delegate.events.contains("finish") }

            XCTAssertEqual(delegate.events, ["start", "commit", "finish"])
            XCTAssertEqual(delegate.decidedURLs.first?.host, "fakewebkit.test")
        }

        func testFileLoadingHistoryAndReload() throws {
            let first = try makeTemporaryHTML("<title>First</title>")
            let second = try makeTemporaryHTML("<title>Second</title>")
            let webView = makeWebView()
            let delegate = RecordingDelegate()
            webView.navigationDelegate = delegate

            XCTAssertNil(webView.goBack())
            XCTAssertNil(webView.goForward())

            webView.url = first
            waitUntil { webView.title == "First" && delegate.events.contains("finish") }
            XCTAssertEqual(webView.url, first)

            webView.loadFileURL(second, allowingReadAccessTo: second.deletingLastPathComponent())
            waitUntil { webView.title == "Second" && !webView.isLoading }
            XCTAssertTrue(webView.canGoBack)

            XCTAssertNotNil(webView.goBack())
            waitUntil { webView.title == "First" && !webView.isLoading }
            XCTAssertTrue(webView.canGoForward)
            XCTAssertEqual(delegate.actions.last?.navigationType, .backForward)

            XCTAssertNotNil(webView.goForward())
            waitUntil { webView.title == "Second" && !webView.isLoading }

            let finishes = delegate.events.filter { $0 == "finish" }.count
            XCTAssertNotNil(webView.reloadFromOrigin())
            waitUntil { delegate.events.filter { $0 == "finish" }.count > finishes }
            XCTAssertEqual(delegate.actions.last?.navigationType, .reload)

            webView.url = nil
            webView.stopLoading()
            spin(0.1)
            XCTAssertEqual(webView.url, second)
        }

        func testLoadData() throws {
            let webView = makeWebView()
            let delegate = RecordingDelegate()
            webView.navigationDelegate = delegate

            let baseURL = try XCTUnwrap(URL(string: "https://fakewebkit.test/"))
            webView.load(Data("<title>Data</title>".utf8), mimeType: "text/html", characterEncodingName: "utf-8", baseURL: baseURL)
            waitUntil { delegate.events.contains("finish") }
            XCTAssertEqual(webView.title, "Data")
        }

        func testFailedLoadCallsDidFail() {
            let webView = makeWebView()
            let delegate = RecordingDelegate()
            webView.navigationDelegate = delegate

            let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).html")
            webView.load(URLRequest(url: missing))
            waitUntil { delegate.events.contains("fail-provisional") }
            XCTAssertEqual(delegate.events, ["start", "fail-provisional"])
            XCTAssertFalse(delegate.errors.isEmpty)
        }

        // MARK: Navigation policy

        func testCancelPolicyBlocksNavigation() {
            let webView = makeWebView()
            let delegate = RecordingDelegate()
            delegate.policy = .cancel
            webView.navigationDelegate = delegate

            webView.loadHTMLString("<title>Blocked</title>", baseURL: nil)
            waitUntil { !delegate.actions.isEmpty }
            spin(0.3)

            XCTAssertTrue(delegate.events.isEmpty)
            XCTAssertTrue(logger.messages.contains("Decision: CANCEL"))
        }

        func testAsyncPolicyCanCancel() {
            let webView = makeWebView()
            let delegate = WebKitStyleDelegate()
            delegate.blockedHosts = ["blocked.test"]
            webView.navigationDelegate = delegate

            webView.loadHTMLString("<title>Blocked</title>", baseURL: URL(string: "https://blocked.test/"))
            waitUntil { !delegate.decidedURLs.isEmpty }
            spin(0.3)
            XCTAssertTrue(delegate.events.isEmpty)
        }

        func testLateDecisionRestartsMainFrameLoad() throws {
            let page = try makeTemporaryHTML("<title>Late</title>")
            let webView = makeWebView()
            let delegate = LateDecisionDelegate()
            webView.navigationDelegate = delegate

            webView.load(URLRequest(url: page))
            waitUntil { delegate.events.contains("finish") }
            XCTAssertEqual(webView.title, "Late")
            XCTAssertEqual(delegate.decisions, 1)
            XCTAssertTrue(logger.messages.contains("Decision pending"))
        }

        func testLateCancelKeepsPageUnloaded() throws {
            let page = try makeTemporaryHTML("<title>Never</title>")
            let webView = makeWebView()
            let delegate = LateDecisionDelegate()
            delegate.policy = .cancel
            webView.navigationDelegate = delegate

            webView.load(URLRequest(url: page))
            waitUntil { self.logger.messages.contains("Deferred decision: CANCEL") }
            spin(0.2)
            XCTAssertTrue(delegate.events.isEmpty)
        }

        func testDeferredAsyncPolicyOnOlderSystems() {
            WKWebView._allowsImmediatePolicyTasks = false
            let webView = makeWebView()
            let delegate = WebKitStyleDelegate()
            webView.navigationDelegate = delegate

            webView.loadHTMLString("<title>Async</title>", baseURL: URL(string: "https://fakewebkit.test/"))
            waitUntil { delegate.events.contains("finish") }
            XCTAssertEqual(webView.title, "Async")
            XCTAssertEqual(delegate.decidedURLs.count, 1)
        }

        func testDelegateWithoutPolicyIsRememberedOnOlderSystems() {
            WKWebView._allowsImmediatePolicyTasks = false
            let webView = makeWebView()
            let delegate = FinishOnlyDelegate()
            webView.navigationDelegate = delegate

            webView.loadHTMLString("<title>One</title>", baseURL: nil)
            waitUntil { delegate.finished == 1 }
            XCTAssertNotNil(webView._delegateWithoutPolicy)

            webView.loadHTMLString("<title>Two</title>", baseURL: nil)
            waitUntil { delegate.finished == 2 }
            XCTAssertEqual(webView.title, "Two")

            webView.navigationDelegate = nil
            XCTAssertNil(webView._delegateWithoutPolicy)
        }
    }
#endif
