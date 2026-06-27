// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mpbg",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Mpbg", targets: ["Mpbg"])
    ],
    targets: [
        .executableTarget(
            name: "Mpbg"
        ),
        .testTarget(
            name: "MpbgTests",
            dependencies: ["Mpbg"]
        )
    ]
)
