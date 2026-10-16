<p align="center">
  <img src="docs/logo.png" alt="FakeWebKit logo" width="160" height="160">
</p>

<h1 align="center">FakeWebKit</h1>

<p align="center">
  <a href="https://github.com/undeaDD/FakeWebKit/actions/workflows/ci.yml"><img src="https://github.com/undeaDD/FakeWebKit/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/test%20coverage-96%25-brightgreen" alt="Test coverage: 96%">
  <a href="https://github.com/undeaDD/FakeWebKit/releases/latest"><img src="https://img.shields.io/github/v/release/undeaDD/FakeWebKit?label=version" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/tvOS-13%2B-000000?logo=apple" alt="Platform: tvOS 13+">
  <img src="https://img.shields.io/badge/Swift%20Package%20Manager-compatible-orange" alt="Swift Package Manager">
  <a href="LICENSE.md"><img src="https://img.shields.io/badge/license-GPLv3-blue" alt="License: GPLv3"></a>
</p>

A lightweight drop-in `WKWebView` for tvOS. Write your web view code once against the WebKit API,
and on tvOS import FakeWebKit instead of WebKit. User scripts, JavaScript message handlers, cookies,
website data and navigation delegates work without any WebKit dependency.

> **Notice:** `WKWebView` from FakeWebKit uses `UIWebView` internally, which is a private API on tvOS.
> Use with caution, as it may be rejected by App Store review.

## Installation

Add the package via Swift Package Manager:

> In Xcode: File > Add Package Dependencies...

```
https://github.com/undeaDD/FakeWebKit.git
```

or in `Package.swift`:

```swift
.package(url: "https://github.com/undeaDD/FakeWebKit.git", from: "1.0.1")
```

## Usage

Use it just like `WKWebView` from WebKit. Only the import differs:

```swift
#if os(tvOS)
    import FakeWebKit
#else
    import WebKit
#endif

// Add a JS message handler
let configuration = WKWebViewConfiguration()
configuration.userContentController.add(MyMessageHandler(), name: "scriptTest")

// Inject a user script
configuration.userContentController.addUserScript(WKUserScript(
    source: "window.webkit.messageHandlers.scriptTest.postMessage({ title: document.title });",
    injectionTime: .atDocumentEnd,
    forMainFrameOnly: true
))

// Create the web view and load a URL
let webView = WKWebView(frame: .zero, configuration: configuration)
webView.navigationDelegate = self
webView.load(URLRequest(url: URL(string: "https://example.com")!))
```

Navigation delegates can use the WebKit signatures Xcode generates, including the async policy method:

```swift
extension Monitor: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        navigationAction.request.url?.host == "ads.example.com" ? .cancel : .allow
    }
}
```

Cookies and website data:

```swift
let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
cookieStore.getAllCookies { cookies in
    print(cookies.map(\.name))
}

await WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeCookies], modifiedSince: .distantPast)
```

## Supported API

| Area | API |
| --- | --- |
| `WKWebView` | `init(frame:)`, `init(frame:configuration:)`, `load(_:)`, `load(_:mimeType:characterEncodingName:baseURL:)`, `loadHTMLString(_:baseURL:)`, `loadFileURL(_:allowingReadAccessTo:)`, `reload()`, `reloadFromOrigin()`, `stopLoading()`, `goBack()`, `goForward()`, `evaluateJavaScript(_:completionHandler:)`, `evaluateJavaScript(_:) async`, `callAsyncJavaScript` (completion handler and async), `url`, `title`, `isLoading`, `canGoBack`, `canGoForward`, `scrollView`, `customUserAgent`, `navigationDelegate`, `configuration` |
| `WKNavigationDelegate` | `didStartProvisionalNavigation`, `didCommit`, `didFinish`, `didFail`, `didFailProvisionalNavigation`, `decidePolicyFor` (completion handler and async), all optional, `WKNavigation` and `WKNavigation!` variants |
| `WKNavigationAction` | `request`, `navigationType`, `targetFrame` (`WKFrameInfo` with `isMainFrame`, `request`) |
| `WKUserContentController` | `addUserScript(_:)`, `removeAllUserScripts()`, `userScripts`, `add(_:name:)`, `removeScriptMessageHandler(forName:)`, `removeAllScriptMessageHandlers()` |
| `WKUserScript` | `source`, `injectionTime` (`.atDocumentStart`, `.atDocumentEnd`), `isForMainFrameOnly` |
| `WKScriptMessage` | `name`, `body`, `webView` |
| `WKWebsiteDataStore` | `default()`, `allWebsiteDataTypes()`, `httpCookieStore`, `isPersistent`, `removeData(ofTypes:modifiedSince:)` (completion handler and async) |
| `WKHTTPCookieStore` | `getAllCookies(_:)`, `allCookies()`, `setCookie(_:)`, `delete(_:)`, `deleteCookie(_:)`, `add(_:)` / `remove(_:)` observers |
| `WKContentWorld` | `.page`, `.defaultClient`, `world(name:)` (all run in the page world) |
| Errors | `WKError`, `WKErrorDomain` |

FakeWebKit additions that WebKit doesn't have:

- `WKWebView.logger`: set any `DebugLogger` to see what happens under the hood.
- `WKWebView.isHiddenByDefault`: initial `isHidden` value of new web views (default `true`). Set it to `false`
  for visible web views like on iOS. `isHidden` itself can be changed at any time.

## Limitations

`UIWebView` is not `WKWebView`, so a few things behave differently:

- `.atDocumentStart` scripts and `window.webkit.messageHandlers` are installed through a private `UIWebView`
  callback, before the first inline script of the page runs. If that callback is ever missing, FakeWebKit falls
  back to polling the web view, and inline scripts that call `postMessage` while the page is still parsing can
  miss the bridge again.
- Script messages and user scripts only reach the main frame.
- `UIWebView` has one JavaScript world, so every `WKContentWorld` runs in the page world, and
  `callAsyncJavaScript` always runs in the main frame.
- `evaluateJavaScript` runs the script through an indirect `eval`, so top-level `let` and `const` declarations
  don't persist between calls (`var` and functions do).
- `removeData(ofTypes:)` removes cookies and cached responses. Other storage types are ignored.
- All web views share `HTTPCookieStorage.shared` and `URLCache.shared`. There is no
  `WKWebsiteDataStore.nonPersistent()`, every store works on the same app-wide cookie jar.
- `customUserAgent` is applied through the app-wide `UserAgent` user default, so it can affect every web view
  in the app, not just the one it was set on.
- `callAsyncJavaScript` arguments must be JSON values (strings, numbers, booleans, arrays, dictionaries, `NSNull`).
- `WKNavigation` is a value type, so navigations can't be compared by identity. `didCommit` fires when the new
  document's JavaScript context exists.
- `WKScriptMessage` has no `frameInfo`, and `WKNavigationAction` has no `sourceFrame`.
- When a policy decision does not arrive synchronously (an async delegate on tvOS 25 or older, or a
  completion handler that is called later), the main-frame load is paused and restarted once the delegate allows it.
  Subframe loads can't be paused and continue without waiting for the decision.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for additions and breaking changes per release.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Security issues go through [SECURITY.md](SECURITY.md).

If FakeWebKit saves you time, you can [buy me a coffee](https://www.paypal.com/paypalme/undeaDD).

## License

FakeWebKit is licensed under the [GNU General Public License v3.0](LICENSE.md).
