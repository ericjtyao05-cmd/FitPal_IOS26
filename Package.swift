// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FitPal",
    platforms: [.iOS(.v16)],
    products: [
        .executable(name: "FitPalApp", targets: ["FitPalApp"])
    ],
    targets: [
        .executableTarget(
            name: "FitPalApp",
            path: "Sources/FitPalApp",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
