// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KnockCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "KnockCore", targets: ["KnockCore"])],
    targets: [
        .target(name: "KnockCore", path: "Knock",
                exclude: ["Views", "KnockApp.swift", "Info.plist"],
                sources: ["Models", "Services"]),
        .testTarget(name: "KnockCoreTests", dependencies: ["KnockCore"], path: "Tests",
                    exclude: ["ActionMappingChecks.swift", "run-checks.sh"])
    ]
)
