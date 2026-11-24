// swift-tools-version:6.4
import PackageDescription

let package = Package(
    name: "swift-corekit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CoreKit", targets: ["CoreKit"])
    ],
    targets: [
        .target(name: "CoreKit"),
        .testTarget(
            name: "CoreKitTests",
            dependencies: ["CoreKit"]
        ),
    ]
)
