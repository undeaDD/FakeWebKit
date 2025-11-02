# FakeWebKit
A lightweight ( 520 lines of code ) drop-in WebKit wrapper for tvOS, supporting user scripts, JS message handlers, and cookies — no WebKit dependency.

> **Notice:** `FakeWebView` uses `UIWebView` internally, which is a private API on tvOS. Use with caution as it may be rejected by App Store review.

## Features
-    Drop-in replacement for WKWebView on tvOS
-    User scripts injection (atDocumentStart / atDocumentEnd)
-    JavaScript message handlers via window.webkit.messageHandlers
-    Cookie management via WKCookieStore
-    Supports custom user agent and basic navigation delegate callbacks
- ...

## Installation

Add the package via Swift Package Manager:

> In Xcode: File > Swift Packages > Add Package Dependency

https://github.com/undeadd/FakeWebKit.git

Usage
> Use it just like the normal WKWwebView from Webkit:

```swift

#if os(tvOS)
    import FakeWebKit
#else
    import WebKit
#endif

// Add a JS message handler
let configuration = WKWebViewConfiguration()
configuration.userContentController.add(MyMessageHandler(), name: "scriptTest")

// Create the WKWebView
let webView = WKWebView(frame: .zero, configuration: configuration)

// Inject a user script
let testScript = WKUserScript(
    source: """
    (function() {
        if (window.webkit?.messageHandlers?.scriptTest?.postMessage) {
            window.webkit.messageHandlers.scriptTest.postMessage("Hello from JS");
        }
    })();
    """,
    injectionTime: .atDocumentEnd,
    forMainFrameOnly: true
)
configuration.userContentController.addUserScript(testScript)

// Load a URL
webView.load(URLRequest(url: URL(string: "https://example.com")!))
```
