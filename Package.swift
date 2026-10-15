// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-frp",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "FRPClient",
            targets: ["FRPClient"]
        ),
        .executable(
            name: "frpc-swift",
            targets: ["FRPClientCLI"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FRPClient",
            dependencies: [],
            path: "Sources/FRPClient"
        ),
        .executableTarget(
            name: "FRPClientCLI",
            dependencies: ["FRPClient"],
            path: "Sources/FRPClientCLI"
        ),
        .testTarget(
            name: "FRPClientTests",
            dependencies: ["FRPClient"],
            path: "Tests/FRPClientTests"
        )
    ]
)
