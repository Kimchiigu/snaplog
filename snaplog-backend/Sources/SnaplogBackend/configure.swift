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
    if var databaseURL = Environment.get("DATABASE_URL") {
        // Neon and other managed Postgres require TLS; local docker Postgres doesn't
        // support it, so only force sslmode for remote hosts.
        let isLocal: Bool
        if let host = URL(string: databaseURL)?.host() {
            isLocal = host == "localhost" || host == "127.0.0.1" || host == "::1"
        } else {
            isLocal = false
        }
        if !databaseURL.contains("sslmode=") && !isLocal {
            databaseURL += databaseURL.contains("?") ? "&sslmode=require" : "?sslmode=require"
        }
        // Cap per-event-loop Postgres connections: with HPA running up to 10 app pods +
        // workers against Neon, unbounded pools would exhaust the connection limit.
        // For production prefer Neon's pooled (-pooler) connection string.
        try app.databases.use(.postgres(
            url: databaseURL,
            maxConnectionsPerEventLoop: Environment.get("POSTGRES_MAX_CONNECTIONS").flatMap(Int.init(_:)) ?? 1
        ), as: .psql)
    } else {
        let hostname = Environment.get("DATABASE_HOST") ?? "localhost"
        let port = Environment.get("DATABASE_PORT").flatMap(Int.init(_:)) ?? SQLPostgresConfiguration.ianaPortNumber
        let username = Environment.get("DATABASE_USERNAME") ?? "vapor_username"
        let password = Environment.get("DATABASE_PASSWORD") ?? "vapor_password"
        let database = Environment.get("DATABASE_NAME") ?? "vapor_database"
        let maxConnections = Environment.get("POSTGRES_MAX_CONNECTIONS").flatMap(Int.init(_:)) ?? 1
        let tls: PostgresConnection.Configuration.TLS = .prefer(try .init(configuration: .clientDefault))
        let sqlConfig = SQLPostgresConfiguration(
            hostname: hostname,
            port: port,
            username: username,
            password: password,
            database: database,
            tls: tls
        )
        app.databases.use(
            .postgres(configuration: sqlConfig, maxConnectionsPerEventLoop: maxConnections),
            as: .psql
        )
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
    app.middleware.use(TraceMiddleware(), at: .beginning)
    app.middleware.use(NetworkLogMiddleware(), at: .beginning)
    NetworkMonitor.startHeartbeat(on: app)
    app.migrations.add(CreateUser())
    app.migrations.add(AddUserPassword())
    app.migrations.add(CreateRoom())
    app.migrations.add(CreateRoomMember())
    app.migrations.add(CreateMediaLog())
    app.migrations.add(AlterMediaLogStatus())
    app.migrations.add(CreateDeviceToken())
    app.queues.add(StitchVideoJob())
    try PushNotificationService.configure(app)
    
    try routes(app)
}
