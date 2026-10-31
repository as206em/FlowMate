// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FlowMate",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "FlowMate", targets: ["FlowMate"])
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "FlowMate",
            dependencies: [
                "Alamofire",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources",
            resources: [.process("../Resources")]
        ),
        .testTarget(
            name: "FlowMateTests",
            dependencies: ["FlowMate"],
            path: "Tests"
        )
    ]
)
