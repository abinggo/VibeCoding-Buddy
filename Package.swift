// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VibeBuddy",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "VibeBuddy",
            resources: [
                .copy("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit")
            ]
        )
    ]
)
