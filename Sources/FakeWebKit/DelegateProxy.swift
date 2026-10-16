#if os(tvOS)
    import Foundation

    /// Receives the UIWebView delegate callbacks and translates them to `WKNavigationDelegate`.
    @MainActor
    @objc
    class _DelegateProxy: NSObject {
        weak var owner: WKWebView?

        init(owner: WKWebView) {
            self.owner = owner
            super.init()

            WKWebView.logger?.log("_DelegateProxy initialized")
        }

        override func responds(to aSelector: Selector!) -> Bool {
            let selectorString = String(describing: aSelector)
            let implementedSelectors = [
                "webViewDidStartLoad:",
                "webViewDidFinishLoad:",
                "webView:didFailLoadWithError:",
                "webView:shouldStartLoadWithRequest:navigationType:",
            ]
            return implementedSelectors.contains(selectorString) || super.responds(to: aSelector)
        }

        @objc
        func webViewDidStartLoad(_ webView: AnyObject) {
            WKWebView.logger?.log("webViewDidStartLoad")
            guard let owner else {
                WKWebView.logger?.log("owner has been deallocated, canceling callback")
                return
            }

            // Subframe loads also end up here; only main-frame loads start a navigation.
            guard owner._expectsMainFrameLoad else { return }
            owner._expectsMainFrameLoad = false
            owner._isNavigating = true
            let startedEarly = owner._documentStartedEarly
            owner._beginDocumentTracking()

            let delegate = owner.navigationDelegate
            delegate?.webView(owner, didStartProvisionalNavigation: WKNavigation())
            delegate?.webView(owner, didStartProvisionalNavigation: WKNavigation() as WKNavigation?)
            if startedEarly { owner._commitIfNeeded() }
        }

        @objc
        func webViewDidFinishLoad(_ webView: AnyObject) {
            WKWebView.logger?.log("webViewDidFinishLoad")
            guard let owner else {
                WKWebView.logger?.log("owner has been deallocated, canceling callback")
                return
            }

            owner._documentTick()
            guard owner._isNavigating, !owner.isLoading else { return }
            owner._isNavigating = false
            owner._endDocumentTracking()

            let delegate = owner.navigationDelegate
            delegate?.webView(owner, didFinish: WKNavigation())
            delegate?.webView(owner, didFinish: WKNavigation() as WKNavigation?)
        }

        @objc
        func webView(_ webView: AnyObject, didFailLoadWithError error: NSError) {
            if let failingURL = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL,
               failingURL.scheme == WKWebView.bridgeScheme {
                return
            }

            WKWebView.logger?.logError("Error: \(error)")
            guard let owner else {
                WKWebView.logger?.log("owner has been deallocated, canceling callback")
                return
            }

            guard owner._isNavigating, !owner.isLoading else { return }
            owner._isNavigating = false
            owner._endDocumentTracking()

            // Before the new document exists the navigation is still provisional, like in WebKit.
            let delegate = owner.navigationDelegate
            if owner._didCommitDocument {
                delegate?.webView(owner, didFail: WKNavigation(), withError: error)
                delegate?.webView(owner, didFail: WKNavigation() as WKNavigation?, withError: error)
            } else {
                delegate?.webView(owner, didFailProvisionalNavigation: WKNavigation(), withError: error)
                delegate?.webView(owner, didFailProvisionalNavigation: WKNavigation() as WKNavigation?, withError: error)
            }
        }

        @objc(webView:shouldStartLoadWithRequest:navigationType:)
        func webView_shouldStartLoadWithRequest(_ webView: AnyObject, shouldStartLoadWithRequest request: URLRequest,
                                                navigationType: Int) -> Bool {
            handleShouldStartLoad(request: request, navigationType: navigationType)
        }

        func handleShouldStartLoad(request: URLRequest, navigationType: Int) -> Bool {
            guard let owner else {
                WKWebView.logger?.log("owner has been deallocated, canceling callback")
                return true
            }

            if owner._handleJSBridge(request: request) { return false }

            WKWebView.logger?.log("Navigation request: \(request.url?.absoluteString ?? "nil") (Type: \(navigationType))")

            let isMainFrame = request.mainDocumentURL == nil || request.mainDocumentURL == request.url
            let replay = isMainFrame ? owner._pendingReplay : nil
            if isMainFrame { owner._pendingReplay = nil }

            if isMainFrame, let url = request.url, let index = owner._preapprovedURLs.firstIndex(of: url) {
                owner._preapprovedURLs.remove(at: index)
                owner._expectsMainFrameLoad = true
                return true
            }

            let action = WKNavigationAction(
                request: request,
                navigationType: WKNavigationType(uiWebViewNavigationType: navigationType),
                targetFrame: WKFrameInfo(isMainFrame: isMainFrame, request: request)
            )

            let decision = owner._decidePolicy(for: action) { [weak owner] policy in
                WKWebView.logger?.log("Deferred decision: \(policy == .allow ? "ALLOW" : "CANCEL")")
                guard policy == .allow, let owner, let url = request.url else { return }
                owner._preapprovedURLs.append(url)
                if let replay {
                    replay()
                } else {
                    owner.load(request)
                }
            }

            switch decision {
            case .allow?:
                WKWebView.logger?.log("Decision: ALLOW")
                if isMainFrame { owner._expectsMainFrameLoad = true }
                return true
            case .cancel?:
                WKWebView.logger?.log("Decision: CANCEL")
                return false
            case nil:
                // UIWebView needs an answer now. Main-frame loads are paused and restarted once the
                // delegate allows them; subframes can't be restarted on their own, so they continue.
                WKWebView.logger?.log("Decision pending")
                return !isMainFrame
            }
        }
    }
#endif
