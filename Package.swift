// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FlowMate",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "FlowMate", targets: ["FlowMate"])
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.0.0")
    ],
    targets: [
        .executableTarget(
            name: "FlowMate",
            dependencies: [
                "Alamofire"
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
