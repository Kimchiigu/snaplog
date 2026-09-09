// swift-tools-version:6.3
import PackageDescription

let package = Package(
    name: "SnaplogBackend",
    platforms: [
       .macOS(.v13)
    ],
    dependencies: [
        // 💧 A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", from: "4.121.4"),
        // 📮 Apple Push Notification service client.
        .package(url: "https://github.com/vapor/apns.git", from: "4.0.0"),
        // 🍎 Low-level APNs protocol implementation used directly by the push service.
        .package(url: "https://github.com/kylebrowning/APNSwift.git", .upToNextMajor(from: "5.0.0")),
        // 🗄 An ORM for SQL and NoSQL databases.
        .package(url: "https://github.com/vapor/fluent.git", from: "4.13.0"),
        // 🐘 Fluent driver for Postgres.
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.12.0"),
        // 🍃 An expressive, performant, and extensible templating language built for Swift.
        .package(url: "https://github.com/vapor/leaf.git", from: "4.5.1"),
        // 🔐 JWT signing & verification (Apple Sign-In + our own session tokens).
        .package(url: "https://github.com/vapor/jwt.git", from: "4.2.2"),
        // 🍏 JWT primitives used to verify Apple identity tokens against Apple JWKS.
        .package(url: "https://github.com/vapor/jwt-kit.git", from: "4.0.0"),
        // ⏭ Background job queue.
        .package(url: "https://github.com/vapor/queues.git", from: "1.18.0"),
        // 🔴 Redis-backed queue driver.
        .package(url: "https://github.com/vapor/queues-redis-driver.git", from: "1.0.5"),
        // 🧰 Redis client (ZSET timelines + Pub/Sub).
        .package(url: "https://github.com/vapor/redis.git", from: "4.0.0"),
        // ☁️ SigV4 signing for Cloudflare R2 (S3-compatible pre-signed URLs).
        .package(url: "https://github.com/soto-project/soto-core.git", from: "7.2.0"),
        // 🔵 Non-blocking, event-driven networking for Swift. Used for custom executors
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.101.0"),
        // 🔏 SHA-256 for the admin login flow.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "SnaplogBackend",
            dependencies: [
                .product(name: "Fluent", package: "fluent"),
                .product(name: "VaporAPNS", package: "apns"),
                .product(name: "APNS", package: "APNSwift"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "Leaf", package: "leaf"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "JWT", package: "jwt"),
                .product(name: "JWTKit", package: "jwt-kit"),
                .product(name: "Queues", package: "queues"),
                .product(name: "QueuesRedisDriver", package: "queues-redis-driver"),
                .product(name: "Redis", package: "redis"),
                .product(name: "SotoSignerV4", package: "soto-core"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SnaplogBackendTests",
            dependencies: [
                .target(name: "SnaplogBackend"),
                .product(name: "VaporTesting", package: "vapor"),
            ],
            swiftSettings: swiftSettings
        )
    ]
)

var swiftSettings: [SwiftSetting] { [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("ImmutableWeakCaptures"),
] }
