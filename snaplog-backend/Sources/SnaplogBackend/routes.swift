import Fluent
import Vapor

func routes(_ app: Application) throws {
    app.get { req in
        req.redirect(to: "/admin/login")
    }

    let api = app.grouped("api")
    api.get("health") { _ in ["status": "ok"] }
    let auth = AuthController()
    try api.register(collection: auth)

    if app.environment == .development {
        api.post("auth", "dev", use: auth.devLogin)
    }

    let authenticated = api.grouped(JWTAuthMiddleware())
        .grouped(IdempotencyMiddleware())
    try authenticated.register(collection: RoomController())
    try authenticated.register(collection: MediaLogController())
    try authenticated.register(collection: UserController())
    let webhooks = WebhookController()
    webhooks.bootWebhook(routes: app)
    webhooks.bootDevices(routes: api)

    app.webSocket("presence") { req, ws in
        await PresenceWebSocketHandler.shared.connect(req: req, ws: ws)
    }
    app.webSocket("admin", "ws", "logs") { req, ws in
        await LogsWebSocketHandler.shared.connect(req: req, ws: ws)
    }
    app.webSocket("admin", "ws", "traces") { req, ws in
        await TracesWebSocketHandler.shared.connect(req: req, ws: ws)
    }
    app.webSocket("admin", "ws", "dlq") { req, ws in
        await DlqWebSocketHandler.shared.connect(req: req, ws: ws)
    }
    
    let admin = AdminController()
    let adminSessioned = app.grouped(app.sessions.middleware)
    adminSessioned.get("admin", "login", use: admin.loginPage)
    adminSessioned.post("admin", "login", use: admin.loginSubmit)
    adminSessioned.post("admin", "logout", use: admin.logout)
    let adminSecure = adminSessioned.grouped(AdminAuthMiddleware())
    try adminSecure.register(collection: admin)
}
