#if os(tvOS)
    @testable import FakeWebKit
    import XCTest

    @MainActor
    final class JavaScriptTests: XCTestCase {
        private func makeWebView() -> WKWebView {
            WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 360), configuration: WKWebViewConfiguration())
        }

        private func evaluate(_ webView: WKWebView, _ script: String) async -> (Any?, Error?) {
            await withCheckedContinuation { continuation in
                webView.evaluateJavaScript(script) { result, error in
                    continuation.resume(returning: (result, error))
                }
            }
        }

        func testTypedResults() async throws {
            let webView = makeWebView()

            let number = try await webView.evaluateJavaScript("1 + 2")
            XCTAssertEqual(number as? Int, 3)

            let string = try await webView.evaluateJavaScript("'a' + 'b'")
            XCTAssertEqual(string as? String, "ab")

            let bool = try await webView.evaluateJavaScript("1 < 2")
            XCTAssertEqual(bool as? Bool, true)

            let object = try await webView.evaluateJavaScript("({ ok: true, ids: [1, 2], name: 'x' })")
            let dictionary = try XCTUnwrap(object as? [String: Any])
            XCTAssertEqual(dictionary["ok"] as? Bool, true)
            XCTAssertEqual(dictionary["ids"] as? [Int], [1, 2])
            XCTAssertEqual(dictionary["name"] as? String, "x")

            let null = try await webView.evaluateJavaScript("null")
            XCTAssertTrue(null is NSNull)

            let date = try await webView.evaluateJavaScript("new Date(1000)")
            XCTAssertEqual(date as? Date, Date(timeIntervalSince1970: 1))
        }

        func testGlobalDeclarationsPersist() async throws {
            let webView = makeWebView()
            _ = await evaluate(webView, "var fakeWebKitCounter = 41;")
            let result = try await webView.evaluateJavaScript("fakeWebKitCounter + 1")
            XCTAssertEqual(result as? Int, 42)
        }

        func testUndefinedResult() async {
            let webView = makeWebView()
            let (result, error) = await evaluate(webView, "undefined")
            XCTAssertNil(result)
            XCTAssertNil(error)

            do {
                _ = try await webView.evaluateJavaScript("void 0")
                XCTFail("Expected an error")
            } catch let error as WKError {
                XCTAssertEqual(error.code, .javaScriptResultTypeIsUnsupported)
            } catch {
                XCTFail("Unexpected error \(error)")
            }
        }

        func testExceptionsAndUnsupportedResults() async {
            let webView = makeWebView()

            let (thrown, exception) = await evaluate(webView, "throw new Error('boom')")
            XCTAssertNil(thrown)
            let wkError = exception as? WKError
            XCTAssertEqual(wkError?.code, .javaScriptExceptionOccurred)
            XCTAssertEqual(wkError?.errorUserInfo["WKJavaScriptExceptionMessage"] as? String, "boom")

            let (_, plainThrow) = await evaluate(webView, "throw 'text'")
            XCTAssertEqual((plainThrow as? WKError)?.errorUserInfo["WKJavaScriptExceptionMessage"] as? String, "text")

            let (function, functionError) = await evaluate(webView, "(function() {})")
            XCTAssertNil(function)
            XCTAssertEqual((functionError as? WKError)?.code, .javaScriptResultTypeIsUnsupported)

            let (cyclic, cyclicError) = await evaluate(webView, "var c = {}; c.c = c; c")
            XCTAssertNil(cyclic)
            XCTAssertEqual((cyclicError as? WKError)?.code, .javaScriptResultTypeIsUnsupported)
        }

        func testDecodeInvalidPayloads() {
            let webView = makeWebView()
            XCTAssertEqual((webView._decodeJavaScriptResult(nil).1 as? WKError)?.code, .javaScriptResultTypeIsUnsupported)
            XCTAssertEqual((webView._decodeJavaScriptResult("{}").1 as? WKError)?.code, .javaScriptResultTypeIsUnsupported)
        }

        func testWithoutBackingView() async {
            let webView = makeWebView()
            webView._webView = nil

            let (_, error) = await evaluate(webView, "1")
            XCTAssertEqual((error as? WKError)?.code, .webViewInvalidated)

            do {
                _ = try await webView.evaluateJavaScript("1")
                XCTFail("Expected an error")
            } catch let error as WKError {
                XCTAssertEqual(error.code, .webViewInvalidated)
            } catch {
                XCTFail("Unexpected error \(error)")
            }
        }
    }
#endif
