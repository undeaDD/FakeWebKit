#if os(tvOS)
    @testable import FakeWebKit
    import XCTest

    @MainActor
    final class ModelTests: XCTestCase {
        // MARK: Errors and helpers

        func testWKErrorBridgesToNSError() {
            let error = WKError(.javaScriptExceptionOccurred, userInfo: ["key": "value"])
            let nsError = error as NSError

            XCTAssertEqual(nsError.domain, WKErrorDomain)
            XCTAssertEqual(nsError.code, 4)
            XCTAssertEqual(nsError.userInfo["key"] as? String, "value")
            XCTAssertEqual(WKError(.unknown).code, .unknown)
        }

        func testJavaScriptStringLiteral() {
            XCTAssertEqual(jsStringLiteral("plain"), "\"plain\"")
            XCTAssertEqual(jsStringLiteral("a'b\"c"), "\"a'b\\\"c\"")
        }

        // MARK: User scripts and content controller

        func testUserScriptProperties() {
            let script = WKUserScript(source: "1", injectionTime: .atDocumentStart, forMainFrameOnly: true)
            XCTAssertEqual(script.source, "1")
            XCTAssertEqual(script.injectionTime, .atDocumentStart)
            XCTAssertTrue(script.isForMainFrameOnly)

            let defaults = WKUserScript(source: "2")
            XCTAssertEqual(defaults.injectionTime, .atDocumentEnd)
            XCTAssertFalse(defaults.isForMainFrameOnly)
            XCTAssertEqual(WKUserScriptInjectionTime.atDocumentEnd.rawValue, 1)
        }

        func testUserContentControllerScripts() {
            let controller = WKUserContentController()
            controller.addUserScript(WKUserScript(source: "a"))
            controller.addUserScript(WKUserScript(source: "b"))
            XCTAssertEqual(controller.userScripts.map(\.source), ["a", "b"])

            controller.removeAllUserScripts()
            XCTAssertTrue(controller.userScripts.isEmpty)
        }

        func testUserContentControllerHandlers() {
            let controller = WKUserContentController()
            controller.add(MessageRecorder(), name: "one")
            controller.add(MessageRecorder(), name: "two")
            XCTAssertEqual(controller.scriptMessageHandlers.keys.sorted(), ["one", "two"])

            controller.removeScriptMessageHandler(forName: "one")
            XCTAssertEqual(controller.scriptMessageHandlers.keys.sorted(), ["two"])

            controller.removeAllScriptMessageHandlers()
            XCTAssertTrue(controller.scriptMessageHandlers.isEmpty)
        }

        // MARK: Navigation values

        func testNavigationTypeMapping() {
            XCTAssertEqual(WKNavigationType(uiWebViewNavigationType: 0), .linkActivated)
            XCTAssertEqual(WKNavigationType(uiWebViewNavigationType: 1), .formSubmitted)
            XCTAssertEqual(WKNavigationType(uiWebViewNavigationType: 2), .backForward)
            XCTAssertEqual(WKNavigationType(uiWebViewNavigationType: 3), .reload)
            XCTAssertEqual(WKNavigationType(uiWebViewNavigationType: 4), .formResubmitted)
            XCTAssertEqual(WKNavigationType(uiWebViewNavigationType: 5), .other)
        }

        func testPolicyRawValuesMatchWebKit() {
            XCTAssertEqual(WKNavigationActionPolicy.cancel.rawValue, 0)
            XCTAssertEqual(WKNavigationActionPolicy.allow.rawValue, 1)
        }

        func testNavigationActionDefaults() throws {
            let request = URLRequest(url: try XCTUnwrap(URL(string: "https://example.com")))
            let action = WKNavigationAction(request: request)
            XCTAssertEqual(action.navigationType, .other)
            XCTAssertNil(action.targetFrame)
        }

        func testDefaultDelegateImplementations() throws {
            let webView = WKWebView(frame: .zero)
            let delegate = FinishOnlyDelegate()
            let navigation = WKNavigation()
            let error = NSError(domain: "test", code: 1)

            delegate.webView(webView, didStartProvisionalNavigation: navigation)
            delegate.webView(webView, didStartProvisionalNavigation: navigation as WKNavigation?)
            delegate.webView(webView, didFinish: navigation)
            delegate.webView(webView, didCommit: navigation)
            delegate.webView(webView, didCommit: navigation as WKNavigation?)
            delegate.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
            delegate.webView(webView, didFailProvisionalNavigation: navigation as WKNavigation?, withError: error)
            delegate.webView(webView, didFail: navigation, withError: error)
            delegate.webView(webView, didFail: navigation as WKNavigation?, withError: error)
            XCTAssertEqual(delegate.finished, 0)

            let request = URLRequest(url: try XCTUnwrap(URL(string: "https://example.com")))
            var policy: WKNavigationActionPolicy?
            delegate.webView(webView, decidePolicyFor: WKNavigationAction(request: request)) { policy = $0 }
            waitUntil { policy != nil }
            XCTAssertEqual(policy, .allow)
        }

        @MainActor
        func testDefaultAsyncPolicyMarksProbe() async throws {
            let webView = WKWebView(frame: .zero)
            let request = URLRequest(url: try XCTUnwrap(URL(string: "https://example.com")))
            let probe = _PolicyProbe()

            let policy = await _PolicyProbe.$current.withValue(probe) {
                await FinishOnlyDelegate().webView(webView, decidePolicyFor: WKNavigationAction(request: request))
            }
            XCTAssertEqual(policy, .allow)
            XCTAssertTrue(probe.usedDefaultImplementation)
        }

        func testDeferredDefaultPolicyTask() throws {
            WKWebView._allowsImmediatePolicyTasks = false
            defer { WKWebView._allowsImmediatePolicyTasks = true }

            var policy: WKNavigationActionPolicy?
            WKWebView._resolvePolicy({ .cancel }, completion: { policy = $0 })
            XCTAssertNil(policy)
            waitUntil { policy != nil }
            XCTAssertEqual(policy, .cancel)
        }

        func testImmediateDefaultPolicyTaskAnswersSynchronously() {
            var policy: WKNavigationActionPolicy?
            WKWebView._resolvePolicy({ .cancel }, completion: { policy = $0 })
            if #available(tvOS 26.0, *) {
                XCTAssertEqual(policy, .cancel)
            } else {
                waitUntil { policy != nil }
            }
        }

        // MARK: Configuration

        func testConfigurationDefaults() {
            let configuration = WKWebViewConfiguration()
            configuration.allowsInlineMediaPlayback = true
            configuration.suppressesIncrementalRendering = false
            configuration.allowsAirPlayForMediaPlayback = false
            configuration.allowsPictureInPictureMediaPlayback = false
            configuration.mediaTypesRequiringUserActionForPlayback = []

            XCTAssertTrue(configuration.allowsInlineMediaPlayback)
            XCTAssertFalse(configuration.suppressesIncrementalRendering)
            XCTAssertFalse(configuration.allowsAirPlayForMediaPlayback)
            XCTAssertFalse(configuration.allowsPictureInPictureMediaPlayback)
            XCTAssertTrue(configuration.mediaTypesRequiringUserActionForPlayback.isEmpty)
        }
    }
#endif
