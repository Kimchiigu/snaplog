# SnapLog Backend — Run & Test Guide

All commands assume you are in the `snaplog-backend/` directory:

```bash
cd snaplog-backend
```

---

## 1. Starting the Backend (Docker — recommended)

Everything (Redis + API server + FFmpeg worker) runs via Docker Compose:

```bash
# Build & start the whole stack (first build takes a few minutes)
docker compose up -d --build

# Run database migrations (one-shot container)
docker compose run --rm migrate

# Check everything is healthy
docker compose ps                # app + worker Up, redis healthy
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/admin/dashboard   # 200

# Follow logs
docker compose logs -f app       # API server
docker compose logs -f worker    # FFmpeg stitch jobs

# Stop everything
docker compose down
```

That's it — no local Redis, no local FFmpeg needed. Only `.env` credentials
(NeonDB, R2) and Docker Desktop are required.

### Alternative: running natively on macOS (no Docker)

```bash
docker compose up -d redis                    # still need Redis
swift run SnaplogBackend migrate              # terminal 1
swift run SnaplogBackend serve --hostname 0.0.0.0 --port 8080   # terminal 2
swift run SnaplogBackend queues               # terminal 3 (worker; needs brew ffmpeg)
```

---

## 2. Testing from the Browser (easiest)

With the server running, open:

| URL | What it does |
|---|---|
| http://127.0.0.1:8080/admin/dashboard | Lists all users, rooms, media logs |
| http://127.0.0.1:8080/admin/rooms | Forms to create & join rooms |
| http://127.0.0.1:8080/admin/upload-test | Full upload flow: pre-sign → PUT → confirm |
| http://127.0.0.1:8080/admin/presence-test | WebSocket live-event tester |

Every page that asks for a **Bearer Token** wants the `token` from step 3.1
below (dev login).

---

## 3. Testing from the Terminal (curl)

### 3.1 Get a dev token (no Apple account needed)

```bash
TOKEN=$(curl -s -X POST http://127.0.0.1:8080/api/auth/dev \
  -H 'Content-Type: application/json' \
  -d '{"displayName":"Chris"}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')

echo $TOKEN   # sanity check
```

> `dev` login only exists while `ENVIRONMENT=development`. Real clients use
> `POST /api/auth/apple` with an Apple identity token.

### 3.2 Create a room

```bash
curl -s -X POST http://127.0.0.1:8080/api/rooms \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"name":"Beach Trip","roomType":"log","maxMembers":4}'
```

Note the `id` and `inviteCode` in the response.

### 3.3 Join a room

```bash
curl -s -X POST http://127.0.0.1:8080/api/rooms/join \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"inviteCode":"BUVBLA"}'
```

### 3.4 List rooms + timeline

```bash
curl -s http://127.0.0.1:8080/api/rooms -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
```

### 3.5 Upload a video (full flow)

```bash
# 0. Make a test clip if you don't have one
ffmpeg -y -f lavfi -i testsrc=duration=3:size=640x640:rate=24 \
  -c:v libx264 -preset veryfast /tmp/clip.mp4

ROOM_ID="<room-id-from-step-3.2>"

# 1. Get a pre-signed R2 upload URL
RESP=$(curl -s -X POST http://127.0.0.1:8080/api/logs/upload-url \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{\"roomId\":\"$ROOM_ID\",\"fileExtension\":\"mp4\"}")

UPLOAD_URL=$(echo $RESP | python3 -c 'import json,sys; print(json.load(sys.stdin)["uploadURL"])')
S3KEY=$(echo $RESP     | python3 -c 'import json,sys; print(json.load(sys.stdin)["s3Key"])')

# 2. Upload the file straight to Cloudflare R2
curl -s -o /dev/null -w "%{http_code}\n" -X PUT \
  -H 'Content-Type: video/mp4' \
  --data-binary @/tmp/clip.mp4 "$UPLOAD_URL"          # expect 200

# 3. Confirm — enqueues the stitch job (expect 202)
curl -s -o /dev/null -w "%{http_code}\n" -X POST http://127.0.0.1:8080/api/logs/confirm \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{\"s3Key\":\"$S3KEY\",\"duration\":3,\"roomId\":\"$ROOM_ID\"}"
```

With the **worker container running**, the stitch job then:
downloads the clip → composites with FFmpeg → uploads the digest to R2 →
adds it to the room's Redis timeline → publishes `NEW_DIGEST_READY`.

### 3.6 Verify the stitched digest landed

```bash
# Timeline should now contain a digests/... entry
curl -s http://127.0.0.1:8080/api/rooms \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool

# Raw Redis timeline
docker exec snaplog-local-redis redis-cli -a local_redis_pass --no-auth-warning \
  --no-raw ZRANGE "room:$ROOM_ID:timeline" 0 -1 WITHSCORES
```

### 3.7 Watch live events (WebSocket)

Open http://127.0.0.1:8080/admin/presence-test in a browser, paste `$TOKEN`,
click **Connect**, then upload another clip (step 3.5) — you'll see
`NEW_DIGEST_READY` arrive in real time.

---

## 4. Useful Maintenance Commands

```bash
# Rebuild the Docker image after code changes
docker compose up -d --build

# Revert the last migration
docker compose run --rm migrate --revert

# See migration status
docker compose run --rm migrate --status

# Restart just one service
docker compose restart app

# View logs
docker compose logs -f app worker
docker compose logs worker --tail 20

# Rebuild natively from scratch (fixes weird build states)
swift package clean && swift build

# Stop everything (add -v to also wipe Redis data)
docker compose down

# Inspect the R2 bucket contents ( Cloudflare dashboard )
# https://dash.cloudflare.com → R2 → snaplog-media-dev

# Redis: watch the Pub/Sub channel live
docker exec -it snaplog-local-redis redis-cli -a local_redis_pass --no-auth-warning \
  SUBSCRIBE room_events
```

---

## 5. Connecting the iOS App

Run the server bound to all interfaces (as in terminal 3, `--hostname 0.0.0.0`),
find your Mac's IP:

```bash
ipconfig getifaddr en0
```

Then in the iOS app use `http://<that-ip>:8080` as the base URL (and allow
arbitrary loads / local networking in the app's Info.plist for HTTP).
Real sign-ins go through `POST /api/auth/apple` and are verified against
Apple's public keys automatically.
