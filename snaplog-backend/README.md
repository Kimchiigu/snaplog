# SnapLog Vapor Backend

Vapor 4 (Swift 6) backend for SnapLog: Apple Sign-In auth, rooms, media
logging, R2 pre-signed uploads, FFmpeg stitching worker, and real-time
presence over WebSockets.

## Stack

- **Vapor 4 + Fluent** — HTTP + ORM (PostgreSQL / NeonDB)
- **Leaf** — admin test dashboard at `/admin/*`
- **Redis 7** (Docker) — timeline ZSETs, Pub/Sub (`room_events`), job queue
- **Cloudflare R2** — S3-compatible object storage via SigV4 pre-signed URLs
- **FFmpeg** — 4-pane grid compositing in `StitchVideoJob`

## Setup

1. Copy `.env.example` → `.env` and fill in:
   - `DATABASE_URL` (NeonDB Postgres, `?sslmode=require`)
   - `REDIS_HOST` / `REDIS_PORT` / `REDIS_PASSWORD`
   - `R2_*` credentials and `R2_ENDPOINT_URL`
   - `JWT_SECRET`, `APPLE_BUNDLE_ID`
2. Start local Redis:

   ```bash
   docker compose up -d
   ```

3. Install FFmpeg (needed by the worker):

   ```bash
   brew install ffmpeg
   ```

## Run

```bash
# 1. Run migrations
swift run SnaplogBackend migrate

# 2. Start the API + dashboard
swift run SnaplogBackend serve --hostname 0.0.0.0 --port 8080

# 3. Start the queue worker (video stitching)
swift run SnaplogBackend queues
```

## API

| Method | Path | Description |
|---|---|---|
| POST | `/api/auth/apple` | Apple identity token → session JWT |
| GET | `/api/rooms` | List rooms + members + Redis timeline |
| POST | `/api/rooms` | Create room (returns 6-char invite code) |
| POST | `/api/rooms/join` | Join by invite code |
| POST | `/api/logs/upload-url` | R2 pre-signed PUT URL |
| POST | `/api/logs/confirm` | Save log + enqueue stitch job → `202` |
| WS | `/presence?token=…` | Live `NEW_DIGEST_READY` events |

Admin dashboard: `/admin/dashboard`, `/admin/rooms`, `/admin/upload-test`,
`/admin/presence-test`.
