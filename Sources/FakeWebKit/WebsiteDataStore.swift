#if os(tvOS)
    import Foundation

    // MARK: - Website data types

    public let WKWebsiteDataTypeCookies = "WKWebsiteDataTypeCookies"
    public let WKWebsiteDataTypeDiskCache = "WKWebsiteDataTypeDiskCache"
    public let WKWebsiteDataTypeMemoryCache = "WKWebsiteDataTypeMemoryCache"
    public let WKWebsiteDataTypeFetchCache = "WKWebsiteDataTypeFetchCache"
    public let WKWebsiteDataTypeOfflineWebApplicationCache = "WKWebsiteDataTypeOfflineWebApplicationCache"
    public let WKWebsiteDataTypeLocalStorage = "WKWebsiteDataTypeLocalStorage"
    public let WKWebsiteDataTypeSessionStorage = "WKWebsiteDataTypeSessionStorage"
    public let WKWebsiteDataTypeIndexedDBDatabases = "WKWebsiteDataTypeIndexedDBDatabases"
    public let WKWebsiteDataTypeWebSQLDatabases = "WKWebsiteDataTypeWebSQLDatabases"

    // MARK: - Cookies

    /// Legacy FakeWebKit cookie value. Prefer the `HTTPCookie` based API, which matches WebKit.
    public struct WKCookie {
        public let name: String
        public let value: String
        public let domain: String
        public let path: String

        public init(name: String, value: String, domain: String = "", path: String = "/") {
            self.name = name
            self.value = value
            self.domain = domain
            self.path = path
        }
    }

    @MainActor
    public protocol WKHTTPCookieStoreObserver: NSObjectProtocol {
        func cookiesDidChange(in cookieStore: WKHTTPCookieStore)
    }

    public extension WKHTTPCookieStoreObserver {
        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {}
    }

    /// Cookie store backed by `HTTPCookieStorage.shared`, the storage UIWebView uses.
    public class WKHTTPCookieStore {
        let cookieStorage = HTTPCookieStorage.shared
        private let observers = NSHashTable<AnyObject>.weakObjects()
        private var changeToken: NSObjectProtocol?

        public init() {}

        deinit {
            if let changeToken {
                NotificationCenter.default.removeObserver(changeToken)
            }
        }

        // MARK: Legacy FakeWebKit API

        @_disfavoredOverload
        public func getAllCookies(_ callback: ([WKCookie]) -> Void) {
            let cookies = cookieStorage.cookies?.map {
                WKCookie(name: $0.name, value: $0.value, domain: $0.domain, path: $0.path)
            } ?? []
            callback(cookies)
        }

        public func setCookie(_ cookie: WKCookie) {
            if !cookie.domain.isEmpty, let httpCookie = HTTPCookie(properties: [
                .name: cookie.name,
                .value: cookie.value,
                .domain: cookie.domain,
                .path: cookie.path,
            ]) {
                cookieStorage.setCookie(httpCookie)
            } else {
                WKWebView.logger?.logError("Invalid cookie '\(cookie.name)', a domain is required")
            }
        }

        // MARK: WebKit API

        public func getAllCookies(_ completionHandler: @escaping ([HTTPCookie]) -> Void) {
            completionHandler(cookieStorage.cookies ?? [])
        }

        public func allCookies() async -> [HTTPCookie] {
            cookieStorage.cookies ?? []
        }

        public func setCookie(_ cookie: HTTPCookie, completionHandler: (() -> Void)? = nil) {
            cookieStorage.setCookie(cookie)
            completionHandler?()
        }

        public func setCookie(_ cookie: HTTPCookie) async {
            cookieStorage.setCookie(cookie)
        }

        public func delete(_ cookie: HTTPCookie, completionHandler: (() -> Void)? = nil) {
            cookieStorage.deleteCookie(cookie)
            completionHandler?()
        }

        public func deleteCookie(_ cookie: HTTPCookie) async {
            cookieStorage.deleteCookie(cookie)
        }

        public func add(_ observer: WKHTTPCookieStoreObserver) {
            observers.add(observer)
            guard changeToken == nil else { return }

            changeToken = NotificationCenter.default.addObserver(
                forName: .NSHTTPCookieManagerCookiesChanged,
                object: cookieStorage,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.notifyObservers() }
            }
        }

        public func remove(_ observer: WKHTTPCookieStoreObserver) {
            observers.remove(observer)
        }

        @MainActor
        func notifyObservers() {
            for case let observer as WKHTTPCookieStoreObserver in observers.allObjects {
                observer.cookiesDidChange(in: self)
            }
        }
    }

    public typealias WKCookieStore = WKHTTPCookieStore

    // MARK: - Website data store

    public class WKWebsiteDataStore {
        private static let defaultStore = WKWebsiteDataStore()

        public let httpCookieStore = WKHTTPCookieStore()
        var urlCache = URLCache.shared

        public init() {}

        public static func `default`() -> WKWebsiteDataStore { defaultStore }

        public static func allWebsiteDataTypes() -> Set<String> {
            [
                WKWebsiteDataTypeCookies,
                WKWebsiteDataTypeDiskCache,
                WKWebsiteDataTypeMemoryCache,
                WKWebsiteDataTypeFetchCache,
                WKWebsiteDataTypeOfflineWebApplicationCache,
                WKWebsiteDataTypeLocalStorage,
                WKWebsiteDataTypeSessionStorage,
                WKWebsiteDataTypeIndexedDBDatabases,
                WKWebsiteDataTypeWebSQLDatabases,
            ]
        }

        public var isPersistent: Bool { true }

        /// Removes cookies and cached responses. UIWebView keeps its other storage types
        /// (local storage, IndexedDB, ...) in private locations, so those types are ignored.
        public func removeData(ofTypes dataTypes: Set<String>, modifiedSince date: Date,
                               completionHandler: @escaping () -> Void) {
            removeDataNow(ofTypes: dataTypes, modifiedSince: date)
            DispatchQueue.main.async(execute: completionHandler)
        }

        public func removeData(ofTypes dataTypes: Set<String>, modifiedSince date: Date) async {
            removeDataNow(ofTypes: dataTypes, modifiedSince: date)
        }

        func removeDataNow(ofTypes dataTypes: Set<String>, modifiedSince date: Date) {
            if dataTypes.contains(WKWebsiteDataTypeCookies) {
                httpCookieStore.cookieStorage.removeCookies(since: date)
            }

            let cacheTypes: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeFetchCache]
            if !dataTypes.isDisjoint(with: cacheTypes) {
                if date <= .distantPast {
                    urlCache.removeAllCachedResponses()
                } else {
                    urlCache.removeCachedResponses(since: date)
                }
            }

            WKWebView.logger?.log("Removed website data: \(dataTypes.sorted().joined(separator: ", "))")
        }
    }

    public typealias WKDataStore = WKWebsiteDataStore
#endif
