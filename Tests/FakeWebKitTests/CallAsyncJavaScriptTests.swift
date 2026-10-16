#if os(tvOS)
    @testable import FakeWebKit
    import XCTest

    @MainActor
    final class CallAsyncJavaScriptTests: XCTestCase {
        private func makeLoadedWebView() async -> WKWebView {
            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 360), configuration: WKWebViewConfiguration())
            let delegate = RecordingDelegate()
            webView.navigationDelegate = delegate
            webView.loadHTMLString("<p>async</p>", baseURL: URL(string: "https://fakewebkit.test/"))
            await waitUntilAsync { delegate.events.contains("finish") }
            return webView
        }

        func testContentWorlds() {
            XCTAssertNil(WKContentWorld.page.name)
            XCTAssertEqual(WKContentWorld.defaultClient.name, "defaultClient")
            XCTAssertEqual(WKContentWorld.world(name: "tests").name, "tests")
        }

        func testAwaitsPromisesWithArguments() async throws {
            let webView = await makeLoadedWebView()
            let result = try await webView.callAsyncJavaScript("""
            const value = await new Promise(resolve => setTimeout(() => resolve(a + b), 10));
            return { sum: value, target: target };
            """, arguments: ["a": 2, "b": 3, "target": "x"], contentWorld: .defaultClient)

            let dictionary = try XCTUnwrap(result as? [String: Any])
            XCTAssertEqual(dictionary["sum"] as? Int, 5)
            XCTAssertEqual(dictionary["target"] as? String, "x")
        }

        func testUndefinedAndPlainValues() async throws {
            let webView = await makeLoadedWebView()
            let undefined = try await webView.callAsyncJavaScript("await 0;", contentWorld: .page)
            XCTAssertNil(undefined)

            let string = try await webView.callAsyncJavaScript("return JSON.stringify({ status: 200 });",
                                                               arguments: [:], contentWorld: .defaultClient)
            XCTAssertEqual(string as? String, "{\"status\":200}")
        }

        func testRejectedPromiseThrows() async {
            let webView = await makeLoadedWebView()
            do {
                _ = try await webView.callAsyncJavaScript("throw new Error('nope');", contentWorld: .page)
                XCTFail("Expected an error")
            } catch let error as WKError {
                XCTAssertEqual(error.code, .javaScriptExceptionOccurred)
                XCTAssertEqual(error.errorUserInfo["WKJavaScriptExceptionMessage"] as? String, "nope")
            } catch {
                XCTFail("Unexpected error \(error)")
            }
        }

        func testSyntaxErrorAndInvalidArguments() async {
            let webView = await makeLoadedWebView()
            do {
                _ = try await webView.callAsyncJavaScript("return (", contentWorld: .page)
                XCTFail("Expected an error")
            } catch {
                XCTAssertEqual((error as? WKError)?.code, .javaScriptExceptionOccurred)
            }

            do {
                _ = try await webView.callAsyncJavaScript("return 1", arguments: ["bad": Date()], contentWorld: .page)
                XCTFail("Expected an error")
            } catch {
                XCTAssertEqual((error as? WKError)?.code, .unknown)
            }
        }

        func testCompletionHandlerVariant() async {
            let webView = await makeLoadedWebView()
            var outcomes: [Result<Any, Error>] = []
            webView.callAsyncJavaScript("return 7", in: nil, in: .page) { outcomes.append($0) }
            webView.callAsyncJavaScript("return undefined", in: nil, in: .page) { outcomes.append($0) }
            webView.callAsyncJavaScript("throw 'x'", in: nil, in: .page) { outcomes.append($0) }
            webView.callAsyncJavaScript("return 1", in: nil, in: .page)
            await waitUntilAsync { outcomes.count == 3 }

            XCTAssertEqual(try outcomes[0].get() as? Int, 7)
            XCTAssertTrue(try outcomes[1].get() is NSNull)
            XCTAssertThrowsError(try outcomes[2].get())
        }

        func testWithoutBackingViewAndNavigation() async {
            let webView = await makeLoadedWebView()
            var pending: Result<Any, Error>?
            webView.callAsyncJavaScript("await new Promise(() => {});", in: nil, in: .page) { pending = $0 }
            try? await Task.sleep(nanoseconds: 50_000_000)
            webView._beginDocumentTracking()
            await waitUntilAsync { pending != nil }
            XCTAssertThrowsError(try pending?.get())
            webView._endDocumentTracking()

            webView._webView = nil
            do {
                _ = try await webView.callAsyncJavaScript("return 1", contentWorld: .page)
                XCTFail("Expected an error")
            } catch {
                XCTAssertEqual((error as? WKError)?.code, .webViewInvalidated)
            }
            webView._finishAsyncCall("not a dictionary")
        }
    }
#endif
