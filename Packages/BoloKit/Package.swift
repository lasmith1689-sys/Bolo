// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BoloKit",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [
        .library(name: "BoloKit", targets: ["BoloKit"]),
    ],
    targets: [
        .target(
            name: "BoloKit",
            resources: [.copy("Resources/content.json")]
        ),
        .testTarget(
            name: "BoloKitTests",
            dependencies: ["BoloKit"]
        ),
    ]
)
