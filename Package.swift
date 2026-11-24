// swift-tools-version:6.4
import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "swift-corekit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CoreKit", targets: ["CoreKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0"),
        .package(url: "https://github.com/apple/swift-configuration.git", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.17.0"),
    ],
    targets: [
        .macro(
            name: "CoreKitMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "CoreKit",
            dependencies: [
                "CoreKitMacros",
                .product(name: "Configuration", package: "swift-configuration"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
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
