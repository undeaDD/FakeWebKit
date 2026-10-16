#if os(tvOS)
    import Foundation

    // MARK: - Script messages

    public struct WKScriptMessage {
        public let name: String
        public let body: AnyObject
        public private(set) weak var webView: WKWebView?

        init(name: String, body: AnyObject, webView: WKWebView? = nil) {
            self.name = name
            self.body = body
            self.webView = webView
        }
    }

    @MainActor
    public protocol WKScriptMessageHandler: NSObjectProtocol {
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage)
    }

    // MARK: - User scripts

    public enum WKUserScriptInjectionTime: Int, Sendable {
        case atDocumentStart = 0
        case atDocumentEnd = 1
    }

    public struct WKUserScript {
        public let source: String
        public let injectionTime: WKUserScriptInjectionTime
        public let forMainFrameOnly: Bool

        public var isForMainFrameOnly: Bool { forMainFrameOnly }

        public init(source: String, injectionTime: WKUserScriptInjectionTime = .atDocumentEnd, forMainFrameOnly: Bool = false) {
            self.source = source
            self.injectionTime = injectionTime
            self.forMainFrameOnly = forMainFrameOnly
        }
    }

    // MARK: - User content controller

    public class WKUserContentController {
        let owners = NSHashTable<WKWebView>.weakObjects()
        var scripts: [WKUserScript] = []
        var scriptMessageHandlers: [String: WKScriptMessageHandler] = [:]

        public init() {}

        public var userScripts: [WKUserScript] { scripts }

        public func addUserScript(_ script: WKUserScript) {
            scripts.append(script)
        }

        public func removeAllUserScripts() {
            scripts.removeAll()
        }

        public func add(_ scriptMessageHandler: any WKScriptMessageHandler, name: String) {
            scriptMessageHandlers[name] = scriptMessageHandler
            updateOwners()
        }

        public func removeScriptMessageHandler(forName name: String) {
            scriptMessageHandlers.removeValue(forKey: name)
            updateOwners()
        }

        public func removeAllScriptMessageHandlers() {
            scriptMessageHandlers.removeAll()
            updateOwners()
        }

        private func updateOwners() {
            for owner in owners.allObjects {
                owner._updateJSBridgeBindings()
            }
        }
    }
#endif
