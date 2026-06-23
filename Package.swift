// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ModelQuotaBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ModelQuotaBar", targets: ["ModelQuotaBar"]),
        .library(name: "ModelQuotaCore", targets: ["ModelQuotaCore"])
    ],
    targets: [
        .target(name: "ModelQuotaCore"),
        .executableTarget(
            name: "ModelQuotaBar",
            dependencies: ["ModelQuotaCore"]
        )
    ]
)
