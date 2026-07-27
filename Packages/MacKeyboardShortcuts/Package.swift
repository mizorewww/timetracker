// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MacKeyboardShortcuts",
    platforms: [
        .macOS(.v15),
        .iOS(.v15),
    ],
    products: [
        .library(
            name: "MacKeyboardShortcuts",
            targets: ["MacKeyboardShortcuts"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/sindresorhus/KeyboardShortcuts",
            exact: "3.0.1"
        ),
    ],
    targets: [
        .target(
            name: "MacKeyboardShortcuts",
            dependencies: [
                .product(
                    name: "KeyboardShortcuts",
                    package: "KeyboardShortcuts",
                    condition: .when(platforms: [.macOS])
                ),
            ]
        ),
    ]
)
