// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RemoteCore",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "RemoteCore", targets: ["RemoteCore"])
    ],
    targets: [
        .target(
            name: "RemoteCore",
            path: "Sources/RemoteCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "RemoteCoreTests",
            dependencies: ["RemoteCore"],
            path: "Tests/RemoteCoreTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
