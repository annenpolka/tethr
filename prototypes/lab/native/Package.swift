// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "TethrNative", platforms: [.macOS(.v13)], products: [.executable(name: "TethrNative", targets: ["TethrNative"])], targets: [.target(name: "NativeCore"), .executableTarget(name: "TethrNative", dependencies: ["NativeCore"]), .testTarget(name: "NativeCoreTests", dependencies: ["NativeCore"])])
