// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "TextureCore",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(
            name: "AsyncDisplayKit",
            targets: ["AsyncDisplayKit"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "AsyncDisplayKit",
            path: "Artifacts/AsyncDisplayKit.xcframework"
        ),
    ]
)
