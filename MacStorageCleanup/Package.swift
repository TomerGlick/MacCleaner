// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacStorageCleanup",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "MacStorageCleanup",
            targets: ["MacStorageCleanup"]
        ),
        .library(
            name: "MacStorageCleanupCore",
            targets: ["MacStorageCleanupCore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/typelift/SwiftCheck.git", from: "0.12.0")
    ],
    targets: [
        .target(
            name: "MacStorageCleanupCore",
            dependencies: [],
            path: "Sources",
            exclude: ["main.swift"]
        ),
        .executableTarget(
            name: "MacStorageCleanup",
            dependencies: ["MacStorageCleanupCore"],
            path: "Sources",
            sources: ["main.swift"]
        ),
        .testTarget(
            name: "MacStorageCleanupTests",
            dependencies: [
                "MacStorageCleanupCore",
                "SwiftCheck"
            ],
            path: "Tests"
        )
    ]
)
