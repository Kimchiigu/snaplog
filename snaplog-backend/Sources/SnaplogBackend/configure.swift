import Fluent
import FluentPostgresDriver
import JWT
import Leaf
import Queues
import QueuesRedisDriver
import Redis
import SotoSignerV4
import Vapor

func configure(_ app: Application) async throws {
    if let databaseURL = Environment.get("DATABASE_URL") {
        try app.databases.use(.postgres(url: databaseURL), as: .psql)
    } else {
        app.databases.use(DatabaseConfigurationFactory.postgres(configuration: .init(
            hostname: Environment.get("DATABASE_HOST") ?? "localhost",
            port: Environment.get("DATABASE_PORT").flatMap(Int.init(_:)) ?? SQLPostgresConfiguration.ianaPortNumber,
            username: Environment.get("DATABASE_USERNAME") ?? "vapor_username",
            password: Environment.get("DATABASE_PASSWORD") ?? "vapor_password",
            database: Environment.get("DATABASE_NAME") ?? "vapor_database",
            tls: .prefer(try .init(configuration: .clientDefault))
        )), as: .psql)
    }

    let redisConfig: RedisConfiguration

    if let redisURL = Environment.get("REDIS_URL") {
        redisConfig = try RedisConfiguration(url: redisURL)
    } else {
        redisConfig = try RedisConfiguration(
            hostname: Environment.get("REDIS_HOST") ?? "127.0.0.1",
            port: Environment.get("REDIS_PORT").flatMap(Int.init(_:)) ?? 6379,
            password: Environment.get("REDIS_PASSWORD")
        )
    }

    app.redis.configuration = redisConfig
    app.queues.use(.redis(redisConfig))
    app.jwt.signers.use(.hs256(key: Environment.get("JWT_SECRET") ?? "dev-secret-change-me"))
    app.r2 = Application.R2()
    app.views.use(.leaf)
    app.sessions.use(.memory)
    app.routes.defaultMaxBodySize = "64mb"
    app.middleware.use(NetworkLogMiddleware(), at: .beginning)
    NetworkMonitor.startHeartbeat(on: app)
    app.migrations.add(CreateUser())
    app.migrations.add(CreateRoom())
    app.migrations.add(CreateRoomMember())
    app.migrations.add(CreateMediaLog())
    app.queues.add(StitchVideoJob())
    
    try routes(app)
}
