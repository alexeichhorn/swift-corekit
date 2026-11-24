// swift-tools-version:6.4
import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "swift-corekit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CoreKit", targets: ["CoreKit"]),
        .library(name: "CoreKitHummingbird", targets: ["CoreKitHummingbird"]),
        .library(name: "CoreKitHTTPClient", targets: ["CoreKitHTTPClient"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0"),
        .package(url: "https://github.com/apple/swift-configuration.git", from: "1.4.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.28.1"),
        // Pinned: 5.0.0-beta.3 changed the part protocols `UploadedFile` implements.
        .package(url: "https://github.com/vapor/multipart-kit.git", exact: "5.0.0-beta.2"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.37.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
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
        // Reads the ELF section the route macros write to; macOS uses dyld instead.
        .target(name: "CCoreKitRoutes"),
        .target(
            name: "CoreKitHummingbird",
            dependencies: [
                "CCoreKitRoutes",
                "CoreKit",
                "CoreKitMacros",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "MultipartKit", package: "multipart-kit"),
            ]
        ),
        .target(
            name: "CoreKitHTTPClient",
            dependencies: [
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
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
        .testTarget(
            name: "CoreKitHTTPClientTests",
            dependencies: [
                "CoreKitHTTPClient",
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ]
        ),
        .testTarget(
            name: "CoreKitHummingbirdTests",
            dependencies: [
                "CoreKitHummingbird",
                .product(name: "HummingbirdTesting", package: "hummingbird"),
                .product(name: "MultipartKit", package: "multipart-kit"),
            ]
        ),
    ]
)
