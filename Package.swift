// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AlitiesEngine",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // Generator dependencies
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.14.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.19.0"),
        // Profile dependencies
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "AlitiesEngine",
            dependencies: [
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ]
)
