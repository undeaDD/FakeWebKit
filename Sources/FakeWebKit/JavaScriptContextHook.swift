#if os(tvOS)
    import ObjectiveC
    import UIKit

    /// UIWebView's frame load delegate receives the legacy `webView:didCreateJavaScriptContext:forFrame:`
    /// callback when a frame gets a new window object, before any script of the page runs. FakeWebKit adds
    /// that method to the delegate's class (a private class only UIWebView uses) and forwards main-frame
    /// calls to the WKWebView that owns the delegate. Document polling stays in place as a fallback.
    enum _JavaScriptContextHook {
        static let selector = sel("webView:didCreateJavaScriptContext:forFrame:")
        private static var ownerKey: UInt8 = 0
        private static var hookedClasses: Set<ObjectIdentifier> = []

        final class WeakOwner {
            weak var webView: WKWebView?
            init(_ webView: WKWebView) { self.webView = webView }
        }

        /// Routes the callback of `uiWebView` to `owner`. Returns `false` when the private API is missing,
        /// in which case only polling installs the bridge.
        @discardableResult
        static func attach(_ owner: WKWebView, to uiWebView: AnyObject) -> Bool {
            guard let webView = _legacyWebView(of: uiWebView),
                  let delegate = _object(webView, "frameLoadDelegate"),
                  _hook(type(of: delegate)) else {
                WKWebView.logger?.log("JavaScript context hook unavailable, polling only")
                return false
            }

            objc_setAssociatedObject(delegate, &ownerKey, WeakOwner(owner), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            // WebKit caches which delegate methods exist when the delegate is set, so set it again.
            _ = webView.perform(sel("setFrameLoadDelegate:"), with: delegate)
            WKWebView.logger?.log("JavaScript context hook attached")
            return true
        }

        static func _legacyWebView(of uiWebView: AnyObject) -> NSObject? {
            _object(uiWebView, "_documentView").flatMap { _object($0, "webView") }
        }

        static func _object(_ target: AnyObject, _ name: String) -> NSObject? {
            guard let target = target as? NSObject, target.responds(to: sel(name)) else { return nil }
            return target.perform(sel(name))?.takeUnretainedValue() as? NSObject
        }

        /// Adds the callback to `delegateClass` once. Fails if the class already has its own implementation.
        static func _hook(_ delegateClass: AnyClass) -> Bool {
            let id = ObjectIdentifier(delegateClass)
            if hookedClasses.contains(id) { return true }

            let block: @convention(block) (NSObject, NSObject, NSObject, NSObject) -> Void = { delegate, webView, context, frame in
                _didCreateContext(delegate: delegate, webView: webView, context: context, frame: frame)
            }
            guard class_addMethod(delegateClass, selector, imp_implementationWithBlock(block), "v@:@@@") else { return false }

            hookedClasses.insert(id)
            return true
        }

        static func _didCreateContext(delegate: NSObject, webView: NSObject, context: NSObject, frame: NSObject) {
            guard Thread.isMainThread,
                  let owner = (objc_getAssociatedObject(delegate, &ownerKey) as? WeakOwner)?.webView,
                  _object(webView, "mainFrame") === frame,
                  context.responds(to: sel("evaluateScript:")) else { return }

            owner._startDocument { script in
                let value = context.perform(sel("evaluateScript:"), with: script)?.takeUnretainedValue() as? NSObject
                return value?.perform(sel("toString"))?.takeUnretainedValue() as? String
            }
        }
    }
#endif
