// swift-tools-version:6.4
import PackageDescription

let package = Package(
    name: "swift-corekit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CoreKit", targets: ["CoreKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0")
    ],
    targets: [
        .target(name: "CoreKit"),
        .testTarget(
            name: "CoreKitTests",
            dependencies: ["CoreKit"]
        ),
        .testTarget(
            name: "CoreKitMacrosTests",
            dependencies: [
                "CoreKitMacros",
                .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
