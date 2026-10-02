// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "TrackpadSteeringKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "TrackpadSteeringKit", targets: ["TrackpadSteeringKit"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/mrkai77/Subsurface.git",
            branch: "main"
        )
    ],
    targets: [
        .target(
            name: "TrackpadSteeringKit",
            dependencies: [
                .product(name: "Subsurface", package: "Subsurface")
            ]
        )
    ]
)
