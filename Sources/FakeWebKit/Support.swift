#if os(tvOS)
    import Foundation

    // MARK: - Logging

    public protocol DebugLogger {
        func log(_ message: String)
        func logError(_ message: String)
    }

    // MARK: - Errors

    public let WKErrorDomain = "WKErrorDomain"

    public struct WKError: CustomNSError {
        public enum Code: Int, Sendable {
            case unknown = 1
            case webContentProcessTerminated = 2
            case webViewInvalidated = 3
            case javaScriptExceptionOccurred = 4
            case javaScriptResultTypeIsUnsupported = 5
        }

        public let code: Code
        public let errorUserInfo: [String: Any]

        public init(_ code: Code, userInfo: [String: Any] = [:]) {
            self.code = code
            self.errorUserInfo = userInfo
        }

        public static var errorDomain: String { WKErrorDomain }
        public var errorCode: Int { code.rawValue }
    }

    // MARK: - Internal helpers

    @inlinable
    func sel(_ name: String) -> Selector { Selector(name) }

    /// Encodes a Swift string as a quoted JavaScript string literal.
    func jsStringLiteral(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: string, options: .fragmentsAllowed),
              let literal = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return literal
    }
#endif
