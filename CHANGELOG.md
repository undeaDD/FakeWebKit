# Changelog

## 1.0.1

Most code written against 0.0.1 keeps compiling. The changes below bring FakeWebKit in line with WebKit,
check them before updating.

### Breaking changes

- **`evaluateJavaScript` returns typed results**, the same as `WKWebView` on iOS. Code that expected
  `UIWebView` strings has to be updated:

  | JavaScript | 0.0.1 | 1.0.1 |
  | --- | --- | --- |
  | `1 + 2` | `"3"` | `3` (`NSNumber`) |
  | `({ ok: true })` | `"[object Object]"` | `["ok": true]` |
  | `null` | `""` | `NSNull` |
  | `undefined` | `""` | `nil` (the async variant throws `WKError.javaScriptResultTypeIsUnsupported`) |
  | `throw new Error("x")` | `""` | `nil` and `WKError.javaScriptExceptionOccurred` |
  | `new Date(0)` | date string | `Date` |

  Without a backing web view the completion handler now gets `WKError.webViewInvalidated` instead of `(nil, nil)`.
- **`navigationDelegate` is `weak`**, like in WebKit. Keep a strong reference to your delegate, otherwise it
  is released right away.
- **Inside `async` functions**, `webView.evaluateJavaScript("...")` resolves to the new async overload, the same
  as with WebKit. Use `try await` or pass `completionHandler: nil`.
- **`WKNavigationDelegate`, `WKScriptMessageHandler` and `WKHTTPCookieStoreObserver` are `@MainActor`**, like
  in WebKit. Conforming types get main actor isolated methods, and calls from nonisolated code need `await` or
  `@MainActor`.
- **Load errors before the new page exists arrive in `didFailProvisionalNavigation`**, like in WebKit (for
  example an unreachable host or a missing file). `didFail` is only called once the page was committed.
  Implement both if you handled every load error in `didFail` before.

### Added

- `WKWebView.isHiddenByDefault` (FakeWebKit only): initial `isHidden` of new web views, `true` by default as before.
- `WKWebView.callAsyncJavaScript(_:arguments:in:in:completionHandler:)` and
  `callAsyncJavaScript(_:arguments:in:contentWorld:) async throws -> Any?`, with `WKContentWorld`
  (`.page`, `.defaultClient`, `world(name:)`). Promises are awaited, arguments become named parameters.
- `WKNavigationDelegate`: `didCommit` and `didFailProvisionalNavigation`.
- `WKWebView`: `init(frame:)`, `title`, `isLoading`, `canGoBack`, `canGoForward`, `goBack()`, `goForward()`,
  `reloadFromOrigin()`, `scrollView`, `load(_:mimeType:characterEncodingName:baseURL:)`,
  `loadFileURL(_:allowingReadAccessTo:)`, `loadHTMLString(_:baseURL: URL?)`, `evaluateJavaScript(_:) async`.
  Loading methods now return a discardable `WKNavigation?`.
- `WKNavigationDelegate`: every method is optional, `WKNavigation!` variants and the async
  `webView(_:decidePolicyFor:) async -> WKNavigationActionPolicy`.
- `WKNavigationAction.navigationType` (`WKNavigationType`) and `targetFrame` (`WKFrameInfo`).
- `WKUserContentController`: public `init()`, `userScripts`, `removeAllUserScripts()`, `removeAllScriptMessageHandlers()`.
- `WKUserScript.isForMainFrameOnly`, `WKScriptMessage.webView`.
- `WKWebsiteDataStore` with `default()`, `allWebsiteDataTypes()`, `removeData(ofTypes:modifiedSince:)` and the
  `WKWebsiteDataType...` constants. `WKDataStore` stays as a typealias.
- `WKHTTPCookieStore` with the `HTTPCookie` API (`getAllCookies`, `allCookies`, `setCookie`, `delete`,
  `deleteCookie`) and `WKHTTPCookieStoreObserver`. `WKCookieStore` stays as a typealias.
- `WKError` and `WKErrorDomain`.

### Fixed

- Several `postMessage` calls in the same tick are all delivered (they used to overwrite each other).
- `.atDocumentStart` scripts run in the new document instead of the previous one, `.atDocumentEnd` scripts run once
  the document was parsed, and both run once per navigation.
- `window.webkit.messageHandlers` and `.atDocumentStart` scripts are in place before the first inline script of
  the page runs, so `postMessage` calls made while the page is parsing are delivered.
- `didStartProvisionalNavigation` / `didFinish` / `didFail` fire once per main-frame navigation, not for every iframe.
- Policy decisions that arrive later no longer block the main thread for up to 5 seconds.
- Web view preferences (`scalesPageToFit`, ...) are applied with their real values.
- `setCookie(_: WKCookie)` stores the cookie when a domain is given and logs an error otherwise.
