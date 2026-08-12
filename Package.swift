// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "TrainingCompassKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v15),
    ],
    products: [
        .library(name: "TrainingDomain", targets: ["TrainingDomain"]),
        .library(name: "TrainingInsights", targets: ["TrainingInsights"]),
        .library(name: "TrainingApplication", targets: ["TrainingApplication"]),
        .library(name: "TrainingPersistence", targets: ["TrainingPersistence"]),
        .library(name: "HealthKitAdapter", targets: ["HealthKitAdapter"]),
        .executable(name: "training-fixtures", targets: ["TrainingFixtureGenerator"]),
        .executable(
            name: "training-migration-verifier",
            targets: ["TrainingMigrationVerifier"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", "7.11.1"..<"8.0.0"),
    ],
    targets: [
        .target(name: "TrainingDomain"),
        .target(
            name: "TrainingInsights",
            dependencies: ["TrainingDomain"]
        ),
        .target(
            name: "TrainingApplication",
            dependencies: ["TrainingDomain", "TrainingInsights"]
        ),
        .target(
            name: "TrainingPersistence",
            dependencies: [
                "TrainingApplication",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .target(
            name: "HealthKitAdapter",
            dependencies: ["TrainingApplication"]
        ),
        .executableTarget(
            name: "TrainingFixtureGenerator",
            dependencies: ["TrainingApplication"]
        ),
        .executableTarget(
            name: "TrainingMigrationVerifier",
            dependencies: [
                "TrainingPersistence",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "TrainingDomainTests",
            dependencies: ["TrainingDomain"]
        ),
        .testTarget(
            name: "TrainingInsightsTests",
            dependencies: ["TrainingInsights"]
        ),
        .testTarget(
            name: "TrainingApplicationTests",
            dependencies: ["TrainingApplication"]
        ),
        .testTarget(
            name: "TrainingPersistenceTests",
            dependencies: [
                "TrainingPersistence",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "HealthKitAdapterTests",
            dependencies: ["HealthKitAdapter"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
