# SnapLog on Kubernetes

Auto-repair (probes + restarts + PDB) and auto-scaling (HPA) for the Vapor backend.

## One-time setup

```bash
# 1. Create the namespace
kubectl apply -f k8s/namespace.yaml

# 2. Create the secret from your local .env (NeonDB URL, R2 keys, JWT secret, admin creds)
kubectl -n snaplog create secret generic snaplog-env --from-env-file=.env

# 3. Redis password secret (must match REDIS_PASSWORD in .env)
kubectl -n snaplog create secret generic redis-pass --from-literal=REDIS_PASSWORD=local_redis_pass
```

## Deploy

```bash
kubectl apply -f k8s/redis.yaml
kubectl apply -f k8s/migrate.yaml && kubectl -n snaplog wait --for=condition=complete job/snaplog-migrate --timeout=120s
kubectl apply -f k8s/app.yaml      # Deployment + Service + HPA + PDB (auto-repair + auto-scaling)
kubectl apply -f k8s/worker.yaml   # Worker Deployment + its own HPA (queue-driven)
kubectl apply -f k8s/caddy.yaml    # Caddy reverse proxy (LoadBalancer, port 80)
```

## How auto-repair works

- **Liveness probe** (`GET /api/health` every 10s): if a pod hangs or crashes,
  kubelet restarts the container (restartPolicy: Always, 5 attempts/min window).
- **Readiness probe**: a pod failing readiness is removed from the Service
  endpoints immediately — no traffic is sent to it while it "repairs".
- **PodDisruptionBudget** (`minAvailable: 1`): voluntary evictions (node drains,
  upgrades) never take the last replica down.
- **Resource requests/limits** guard against noisy-neighbor and OOM cascades.

## How auto-scaling works

- **HPA on the app**: target 70% CPU, min 2 max 10 replicas. Scale-up is fast
  (stabilization 0s, +100%/period), scale-down is conservative (60s
  stabilization so bursts don't flap).
- **HPA on the worker**: same CPU mechanics for stitch-job bursts.
- Metrics-server is required: `kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml`
  (most managed clusters ship it already).

## Watch it work

```bash
kubectl -n snaplog get hpa -w                       # scaling decisions
kubectl -n snaplog get pods -w                      # pods being replaced/recreated
kubectl -n snaplog describe pod -l app=snaplog-app  # probe/restart events

# Generate load and watch replicas climb:
kubectl -n snaplog run load --rm -it --image=busybox -- /bin/sh -c \
  "while true; do wget -q -O- http://snaplog-app/api/health; done"
```

The mock tests in `Tests/SnaplogBackendTests/HPASimulatorTests.swift` model
these exact policies (scaling math, stabilization windows, crash replacement)
as pure in-memory simulations — `swift test` shows the behavior without a cluster.
