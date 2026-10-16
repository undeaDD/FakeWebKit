#if os(tvOS)
    @testable import FakeWebKit
    import XCTest

    @MainActor
    final class DataStoreTests: XCTestCase {
        private let domain = "fakewebkit.test"

        override func setUp() {
            super.setUp()
            removeTestCookies()
        }

        override func tearDown() {
            removeTestCookies()
            WKWebView.logger = nil
            super.tearDown()
        }

        private func removeTestCookies() {
            for cookie in HTTPCookieStorage.shared.cookies ?? [] where cookie.domain.hasSuffix(domain) {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }

        private func makeCookie(_ name: String, value: String = "1") throws -> HTTPCookie {
            try XCTUnwrap(HTTPCookie(properties: [.name: name, .value: value, .domain: domain, .path: "/"]))
        }

        private func testCookieNames() -> [String] {
            (HTTPCookieStorage.shared.cookies ?? []).filter { $0.domain.hasSuffix(domain) }.map(\.name).sorted()
        }

        // MARK: Data store

        func testDefaultStoreIsShared() {
            XCTAssertTrue(WKWebsiteDataStore.default() === WKWebsiteDataStore.default())
            XCTAssertTrue(WKWebViewConfiguration().websiteDataStore === WKWebsiteDataStore.default())
            XCTAssertTrue(WKWebsiteDataStore.default().isPersistent)
        }

        func testLegacyDataStoreNameStillWorks() {
            let store: WKDataStore = WKDataStore()
            XCTAssertFalse(store === WKWebsiteDataStore.default())
            let cookieStore: WKCookieStore = store.httpCookieStore
            XCTAssertTrue(cookieStore.cookieStorage === HTTPCookieStorage.shared)
        }

        func testAllWebsiteDataTypes() {
            let types = WKWebsiteDataStore.allWebsiteDataTypes()
            XCTAssertEqual(types.count, 9)
            XCTAssertTrue(types.contains(WKWebsiteDataTypeCookies))
            XCTAssertTrue(types.contains(WKWebsiteDataTypeLocalStorage))
        }

        func testRemoveCookiesWithCompletionHandler() throws {
            let logger = TestLogger()
            WKWebView.logger = logger
            HTTPCookieStorage.shared.setCookie(try makeCookie("session"))
            XCTAssertEqual(testCookieNames(), ["session"])

            let done = expectation(description: "removed")
            WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeCookies], modifiedSince: .distantPast) {
                XCTAssertTrue(Thread.isMainThread)
                done.fulfill()
            }
            wait(for: [done], timeout: 2)
            XCTAssertEqual(testCookieNames(), [])
            XCTAssertTrue(logger.messages.contains("Removed website data: WKWebsiteDataTypeCookies"))
        }

        func testRemoveCookiesAsync() async throws {
            HTTPCookieStorage.shared.setCookie(try makeCookie("session"))
            await WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeCookies], modifiedSince: .distantPast)
            XCTAssertEqual(testCookieNames(), [])
        }

        func testRemoveCachesKeepsCookies() throws {
            HTTPCookieStorage.shared.setCookie(try makeCookie("keep"))
            let url = try XCTUnwrap(URL(string: "https://\(domain)/cached"))
            let request = URLRequest(url: url)
            let cache = URLCache(memoryCapacity: 1_000_000, diskCapacity: 0, diskPath: nil)
            let store = WKWebsiteDataStore()
            store.urlCache = cache

            cache.storeCachedResponse(CachedURLResponse(
                response: URLResponse(url: url, mimeType: "text/plain", expectedContentLength: 2, textEncodingName: nil),
                data: Data("ok".utf8)
            ), for: request)
            waitUntil { cache.cachedResponse(for: request) != nil }

            // A date only applies to the disk cache, so this must leave the memory-only cache alone.
            store.removeDataNow(ofTypes: [WKWebsiteDataTypeMemoryCache], modifiedSince: Date(timeIntervalSinceNow: 60))
            store.removeDataNow(ofTypes: [WKWebsiteDataTypeDiskCache], modifiedSince: .distantPast)
            waitUntil { cache.cachedResponse(for: request) == nil }
            XCTAssertEqual(testCookieNames(), ["keep"])
        }

        // MARK: Cookie store

        func testLegacyCookieAPI() {
            let store = WKWebsiteDataStore.default().httpCookieStore
            store.setCookie(WKCookie(name: "legacy", value: "v", domain: domain))

            var cookies: [WKCookie] = []
            store.getAllCookies { (all: [WKCookie]) in cookies = all }

            let cookie = cookies.first { $0.name == "legacy" }
            XCTAssertEqual(cookie?.value, "v")
            XCTAssertEqual(cookie?.domain, domain)
            XCTAssertEqual(cookie?.path, "/")
        }

        func testLegacyCookieWithoutDomainIsRejected() {
            let logger = TestLogger()
            WKWebView.logger = logger
            WKWebsiteDataStore.default().httpCookieStore.setCookie(WKCookie(name: "nodomain", value: "v"))
            XCTAssertEqual(logger.errors, ["Invalid cookie 'nodomain', a domain is required"])
        }

        func testHTTPCookieAPIWithCompletionHandlers() throws {
            let store = WKWebsiteDataStore.default().httpCookieStore
            let cookie = try makeCookie("modern", value: "42")

            var setCalled = false
            store.setCookie(cookie) { setCalled = true }
            XCTAssertTrue(setCalled)

            var found: HTTPCookie?
            store.getAllCookies { cookies in
                found = cookies.first { $0.name == "modern" && $0.domain == self.domain }
            }
            XCTAssertEqual(found?.value, "42")

            var deleteCalled = false
            store.delete(cookie) { deleteCalled = true }
            XCTAssertTrue(deleteCalled)
            XCTAssertEqual(testCookieNames(), [])

            store.setCookie(cookie)
            store.delete(cookie)
            XCTAssertEqual(testCookieNames(), [])
        }

        func testHTTPCookieAPIAsync() async throws {
            let store = WKWebsiteDataStore.default().httpCookieStore
            let cookie = try makeCookie("async")

            await store.setCookie(cookie)
            let cookies = await store.allCookies()
            XCTAssertTrue(cookies.contains { $0.name == "async" })

            await store.deleteCookie(cookie)
            XCTAssertEqual(testCookieNames(), [])
        }

        func testCookieObservers() throws {
            let store = WKHTTPCookieStore()
            let observer = CookieObserver()
            let silent = SilentCookieObserver()
            store.add(observer)
            store.add(silent)

            HTTPCookieStorage.shared.setCookie(try makeCookie("observed"))
            waitUntil { observer.changes > 0 }

            store.remove(observer)
            let changes = observer.changes
            store.notifyObservers()
            XCTAssertEqual(observer.changes, changes)
        }
    }
#endif
