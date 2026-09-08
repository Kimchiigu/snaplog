# SnapLog

SnapLog is a shared video-log app: members of a room record short video "logs", upload them straight to object storage, and watch them back on a collaborative timeline. The project has two parts that live side by side in this repository:

| Folder | What it is |
|---|---|
| [`snaplog-ios/`](snaplog-ios/) | SwiftUI iOS client (camera capture, rooms, auth, presence) |
| [`snaplog-backend/`](snaplog-backend/) | Vapor 4 API server, background worker, admin dashboard, and infrastructure |

Product requirements: [`PRD-IOS.md`](PRD-IOS.md) · [`PRD-BACKEND.md`](PRD-BACKEND.md)

---

## Architecture at a glance

```
iOS App ──HTTPS──▶ Caddy ──▶ Vapor API ──▶ PostgreSQL (Neon)
  │                              │  │
  │                              │  └──▶ Redis (timelines · pub/sub · queues · netlog)
  │                              └──▶ Cloudflare R2 (presigned uploads)
  └─── direct media upload ─────────────▶ Cloudflare R2
                                         Queue Worker (FFmpeg stitch) ◀── Redis queues
```

An interactive version lives at [`snaplog-backend/docs/snaplog-architecture.html`](snaplog-backend/docs/snaplog-architecture.html).

**Key design decisions**

- **Direct-to-R2 uploads** — the API issues short-lived presigned PUT URLs so large video files never pass through the API servers.
- **Redis does the realtime work** — room timelines are cached in Redis, presence and live network logs stream over WebSocket backed by Redis Pub/Sub, and stitch jobs travel through Redis queues.
- **Async stitching** — the FFmpeg worker runs outside the request path as a separate process, so the API stays responsive.
- **Horizontal scale** — every pod (app and worker) registers itself in Redis via heartbeats; Caddy, Kubernetes HPA (CPU 70%, 2–10 replicas), and a PodDisruptionBudget handle traffic growth and node churn.

---

## iOS client (`snaplog-ios/`)

A SwiftUI app (iOS 26 target, Swift 6 strict concurrency) built with XcodeGen (`project.yml` → `SnapLog.xcodeproj`).

**Structure** (`snaplog-ios/SnapLog/SnapLog/`)

- `App/` — app entry, `AppState`, dependency container
- `Features/Auth/` — Sign in with Apple flow (`AuthViewModel`, `LoginView`), JWT kept in the Keychain
- `Features/HomePages/` — room list, create room, join-by-code sheets
- `Features/Camera/` — in-app camera capture (`CameraSessionManager`, AVFoundation), pending-log model and upload flow
- `Core/Network/` — `APIClient` (async/await), typed `APIError`, `WebSocketManager` for presence
- `Core/Analytics/` — Mixpanel event tracking
- `Commons/` — `KeychainStore`, `PendingLogStore` (offline retry queue), reusable UI components

**Environment config** (`Commons/Utilities/AppConfig.swift`): debug builds point at `http://localhost:8080` / `ws://localhost:8080/presence`; release builds at your production host.

**Run it**

```bash
cd snaplog-ios/SnapLog
xcodegen generate          # regenerate SnapLog.xcodeproj from project.yml
open SnapLog.xcodeproj     # needs a development team for Sign in with Apple
```

The app requires the **Sign in with Apple** capability (see `SnapLog.entitlements`) and camera/microphone usage strings (already set in `project.yml`).

**Tests** — unit tests for `AuthViewModel`, `CameraViewModel`, `RoomListViewModel`, and `PendingLogStore` live in `SnapLogTests/` (run with ⌘U in Xcode; `MockAPIClient` stubs the network).

---

## Backend (`snaplog-backend/`)

Vapor 4 on Swift 6 with PostgreSQL (Fluent), Redis (RediStack), Cloudflare R2, and a Leaf admin portal. See [`snaplog-backend/README.md`](snaplog-backend/README.md) for full details.

**Quick start**

```bash
cd snaplog-backend
cp .env.example .env        # fill in DATABASE_URL, REDIS_URL, R2 + JWT secrets
docker compose up -d --build
docker compose run --rm migrate
```

- Public entry point: **http://localhost** (Caddy) — proxies the API on `:8080`
- Admin dashboard: **http://localhost/admin/login** (JWT cookie session; default test creds `admin` / `admin123` — override `ADMIN_USERNAME`/`ADMIN_PASSWORD` in `.env`)
- Health check: `GET /api/health`

**What's inside**

- `Sources/SnaplogBackend/Controllers/` — auth (Apple identity tokens), rooms, media logs, admin CRUD
- `Sources/SnaplogBackend/Services/` — `NetworkMonitor` (pod heartbeats, live request logging), presence and log-stream WebSocket handlers
- `k8s/` — namespace, StatefulSet Redis, HPA, PDB, migrate Job, Caddy ingress ([deploy guide](snaplog-backend/k8s/README.md))
- `Tests/` — SwiftTesting suites (API + HPA/K8s simulator) — `swift test`
- `snaplog-backend.postman_collection.json` — ready-to-run Postman suite covering the whole API, including presigned uploads and negative cases
- [`ERD.md`](snaplog-backend/ERD.md) — data model (User, Room, RoomMember, MediaLog)

**Testing** — tests run against a throwaway Postgres on `:5433` and revert their migrations; they never touch the production database:

```bash
docker run -d -p 5433:5432 -e POSTGRES_PASSWORD=test -e POSTGRES_DB=snaplog_test postgres:16
swift test
```

---

## Repository layout

```
snaplog/
├── PRD-IOS.md · PRD-BACKEND.md    # product requirement documents
├── snaplog-ios/SnapLog/           # SwiftUI app + XcodeGen project
├── snaplog-backend/               # Vapor API, worker, admin, k8s
│   ├── docs/snaplog-architecture.html
│   ├── ERD.md
│   └── snaplog-backend.postman_collection.json
└── start_claude.sh
```
