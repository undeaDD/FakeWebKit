// swift-tools-version: 5.9
// Package: FakeWebKit
// Author: undeaDD
// Repository: https://github.com/undeaDD/FakeWebKit
// License: MIT
// Version: 0.0.1

import PackageDescription

let package = Package(
    name: "FakeWebKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v13),
        .tvOS(.v13),
    ],
    products: [
        .library(
            name: "FakeWebKit",
            targets: ["FakeWebKit"]
        ),
    ],
    targets: [
        .target(
            name: "FakeWebKit"
        )
    ]
)
