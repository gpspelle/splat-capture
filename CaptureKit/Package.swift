// swift-tools-version:5.9
// The parts of Splat Capture that don't need a camera: the package format, the point cloud,
// colour conversion. Tested on a Mac with `swift test --package-path CaptureKit`.
import PackageDescription

let package = Package(
    name: "CaptureKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "CaptureKit", targets: ["CaptureKit"])],
    targets: [
        .target(name: "CaptureKit"),
        .testTarget(name: "CaptureKitTests", dependencies: ["CaptureKit"]),
    ]
)
