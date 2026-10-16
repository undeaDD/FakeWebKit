// swift-tools-version: 5.9
// Package: FakeWebKit
// Author: undeaDD
// Repository: https://github.com/undeaDD/FakeWebKit
// License: GPL-3.0-or-later
// Version: 1.0.1

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
        ),
        .testTarget(
            name: "FakeWebKitTests",
            dependencies: ["FakeWebKit"]
        ),
    ]
)
