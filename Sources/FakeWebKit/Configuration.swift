#if os(tvOS)
    import Foundation

    public class WKWebViewConfiguration {
        public init() {}

        public var websiteDataStore = WKWebsiteDataStore.default()
        public var userContentController = WKUserContentController()

        public var allowsInlineMediaPlayback: Bool = true {
            didSet {
                precondition(allowsInlineMediaPlayback == true,
                             "allowsInlineMediaPlayback can only be true")
            }
        }

        public var suppressesIncrementalRendering: Bool = false {
            didSet {
                precondition(suppressesIncrementalRendering == false,
                             "suppressesIncrementalRendering can only be false")
            }
        }

        public var allowsAirPlayForMediaPlayback: Bool = false {
            didSet {
                precondition(allowsAirPlayForMediaPlayback == false,
                             "allowsAirPlayForMediaPlayback can only be false")
            }
        }

        public var allowsPictureInPictureMediaPlayback: Bool = false {
            didSet {
                precondition(allowsPictureInPictureMediaPlayback == false,
                             "allowsPictureInPictureMediaPlayback can only be false")
            }
        }

        public var mediaTypesRequiringUserActionForPlayback: [Any] = [] {
            didSet {
                precondition(mediaTypesRequiringUserActionForPlayback.isEmpty,
                             "mediaTypesRequiringUserActionForPlayback must be empty")
            }
        }
    }
#endif
