// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Timefold",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Timefold", targets: ["Timefold"])],
    targets: [.executableTarget(name: "Timefold")]
)
