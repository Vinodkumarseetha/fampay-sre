# FamPay SRE Assignment — hodor & bran

> High-availability, auto-scaling microservices with full observability stack.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Quick Start (Local)](#2-quick-start-local)
3. [Services](#3-services)
4. [Dockerfiles](#4-dockerfiles)
5. [Orchestration & Deployment Strategy](#5-orchestration--deployment-strategy)
6. [Secrets & Config Management](#6-secrets--config-management)
7. [Network Topology & One-directional Connectivity](#7-network-topology--one-directional-connectivity)
8. [Horizontal Autoscaling](#8-horizontal-autoscaling)
9. [Continuous Delivery](#9-continuous-delivery)
10. [Observability: Metrics, Logs & Alerting](#10-observability-metrics-logs--alerting)
11. [Load Testing](#11-load-testing)
12. [Personal Notes](#12-personal-notes)

---

## 1. Architecture Overview

```
                         Internet
                             │
                       ┌─────▼──────┐
                       │   nginx    │  :8080
                       │  (ingress) │
                       └──┬──────┬──┘
              /hodor/*    │      │   /bran/*
              ┌───────────┘      └────────────┐
         ┌────▼─────┐                    ┌────▼─────┐
         │  hodor   │◄───────────────────│   bran   │
         │ (GoLang) │  internal only      │ (Django) │
         └──────────┘  bran→hodor ✅      └──────────┘
                       hodor→bran ❌

         ┌──────────────────────────────────────────┐
         │   Prometheus  │  Grafana  │  Alertmanager │
         └──────────────────────────────────────────┘
```

**Key design decisions:**

| Concern | Decision | Reason |
|---|---|---|
| Reverse proxy | nginx | Battle-tested, rate limiting, upstream health checks |
| Go service | scratch image | Minimal attack surface, ~5MB image |
| Django service | python:3.12-slim + gunicorn | Industry-standard WSGI with gthread workers |
| Network isolation | Docker `internal` network + K8s NetworkPolicy | hodor has no path to bran |
| Secret injection | Docker Secrets → K8s Secrets → External Secrets Operator | Never in env vars in git |
| Autoscaling | HPA on CPU + custom Prometheus metrics | Reacts to both system and business load |
| HA | minReplicas=2, PodDisruptionBudget, topologySpreadConstraints | Survives single node failure |

---

## 2. Quick Start (Local)

### Prerequisites

```bash
docker >= 24.0
docker compose >= 2.20
make
curl, python3   # for smoke tests
```

### One-command startup

```bash
# Clone the repo
git clone https://github.com/your-org/fampay-sre.git
cd fampay-sre

# Generate secrets, build images, start everything
make setup
make up
```

After ~30 seconds, services are live:

| URL | Service |
|---|---|
| http://localhost:8080/hodor/ | hodor root |
| http://localhost:8080/hodor/health | hodor health |
| http://localhost:8080/bran/ | bran root |
| http://localhost:8080/bran/health/ | bran health |
| http://localhost:8080/bran/reach-hodor/ | bran calling hodor (proves 1-way) |
| http://localhost:9090 | Prometheus |
| http://localhost:3000 | Grafana (admin/admin) |

### Run smoke tests

```bash
make test
```

### Scale manually (Docker Compose)

```bash
# Scale hodor to 4 replicas
REPLICAS=4 make scale-hodor

# Scale bran to 3 replicas
REPLICAS=3 make scale-bran
```

---

## 3. Services

### hodor (GoLang)

- **Port:** 8080
- **Endpoints:**
  - `GET /hodor/` — main response with host, version, env
  - `GET /hodor/health` — liveness check
  - `GET /hodor/ready` — readiness check
  - `GET /metrics` — Prometheus metrics (request count, latency histograms)
- Built as a **static binary** from `scratch` — zero OS dependencies
- Structured JSON logging to stdout

### bran (Django + gunicorn)

- **Port:** 8000
- **Endpoints:**
  - `GET /bran/` — main response
  - `GET /bran/health/` — liveness check
  - `GET /bran/ready/` — readiness check
  - `GET /bran/reach-hodor/` — demonstrates bran→hodor connectivity
  - `GET /metrics` — Prometheus metrics via `django-prometheus`
- 4 gunicorn workers × 2 threads = 8 concurrent requests per pod
- 12-factor: all config via environment variables

---

## 4. Dockerfiles

### hodor — multi-stage, scratch final image

```dockerfile
# Stage 1: Build static binary
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o hodor .

# Stage 2: Minimal production image (~5MB)
FROM scratch
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /app/hodor /hodor
USER 65534:65534
EXPOSE 8080
ENTRYPOINT ["/hodor"]
```

**Why scratch?**
- No shell, no package manager, no OS → massively reduced attack surface
- Image size ~5MB vs ~300MB for a full base image
- CVE surface near-zero (nothing to patch)

### bran — multi-stage, slim Python

```dockerfile
# Stage 1: Install dependencies
FROM python:3.12-slim AS builder
RUN pip install --prefix=/install -r requirements.txt

# Stage 2: Copy only runtime artifacts
FROM python:3.12-slim
COPY --from=builder /install /usr/local
COPY --chown=bran:bran . .
USER bran
CMD gunicorn bran.wsgi:application --bind 0.0.0.0:8000 --workers 4
```

**Why gunicorn with gthread?**
- `gthread` worker class handles I/O-bound work (DB, HTTP calls to hodor) efficiently
- Workers count tuned via env var `GUNICORN_WORKERS` — no image rebuild needed

---

## 5. Orchestration & Deployment Strategy

### Local: Docker Compose

Used for development and functional demo. Key configuration:

```yaml
networks:
  public:    # nginx ↔ hodor, nginx ↔ bran
  internal:
    internal: true  # bran ↔ hodor; no external egress
```

Docker `internal: true` means containers on this network have no route to the outside world, and — crucially — hodor is NOT attached to it.

### Production: Kubernetes

```
k8s/
├── hodor/
│   ├── deployment.yaml   # 2 replicas, RollingUpdate, probes
│   ├── service.yaml      # ClusterIP (internal only)
│   ├── hpa.yaml          # HPA: CPU + custom metrics
│   ├── pdb.yaml          # PodDisruptionBudget: minAvailable=1
│   └── configmap.yaml    # App config + Secret stub
├── bran/
│   └── bran-all.yaml     # Deployment + Service + HPA + PDB
├── nginx/
│   └── ingress.yaml      # nginx-ingress routing /hodor/* and /bran/*
└── network-policy.yaml   # Deny hodor→bran at CNI layer
```

**Rolling updates with zero downtime:**

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1        # spin up new pod before killing old
    maxUnavailable: 0  # never reduce capacity during deploy
```

**High availability guarantees:**

```yaml
# topologySpreadConstraints ensures pods spread across nodes
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule

# PodDisruptionBudget prevents draining all pods at once
spec:
  minAvailable: 1
```

---

## 6. Secrets & Config Management

### Separation of concerns

| Type | Mechanism | Examples |
|---|---|---|
| Config (non-secret) | ConfigMap (K8s) / env vars (Compose) | `APP_ENV`, `APP_VERSION`, `HODOR_INTERNAL_URL` |
| Secrets | K8s Secret → injected as env var or file | `DJANGO_SECRET_KEY`, `HODOR_SECRET_KEY` |
| Prod secrets | External Secrets Operator (ESO) syncing from AWS Secrets Manager / Vault | All of the above in prod |

### How secrets reach pods

```
AWS Secrets Manager / HashiCorp Vault
         │
         │  (External Secrets Operator polls every 1h)
         ▼
   Kubernetes Secret
         │
         │  (volumeMount or envFrom)
         ▼
     Pod environment
```

### Updating secrets across a fleet

When a secret rotates:

1. Update value in Vault / AWS Secrets Manager.
2. ESO detects the change and updates the K8s Secret object.
3. Pods pick it up **without restart** if mounted as a volume (kubelet refreshes projected volumes every `sync-frequency`).
4. If injected as an env var, a rolling restart is needed:

```bash
kubectl rollout restart deployment/hodor
kubectl rollout restart deployment/bran
```

This triggers RollingUpdate: new pods get new env, old pods terminate after readiness passes — **zero downtime**.

For large fleets (100+ pods), use:

```bash
# Phased restart with 30s between batches
kubectl patch deployment hodor -p \
  '{"spec":{"template":{"metadata":{"annotations":{"kubectl.kubernetes.io/restartedAt":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}}}}}'
```

Kubernetes schedules replacements respecting `maxUnavailable` and `maxSurge` — the fleet never drops below minimum capacity.

---

## 7. Network Topology & One-directional Connectivity

### Docker Compose

```yaml
hodor:
  networks:
    - public      # ← only public, NOT internal

bran:
  networks:
    - public      # reachable by nginx
    - internal    # can reach hodor
```

Hodor has no route to the `internal` network → it cannot initiate connections to bran. Docker enforces this at the kernel routing table level.

### Kubernetes NetworkPolicy

```yaml
# Bran accepts ingress ONLY from nginx (not from hodor)
kind: NetworkPolicy
spec:
  podSelector: {matchLabels: {app: bran}}
  ingress:
    - from:
        - podSelector: {matchLabels: {app: nginx}}
      ports:
        - port: 8000
```

No egress restriction on bran → it can still dial hodor's service IP.

Verify connectivity:

```bash
# Should succeed (bran → hodor)
curl http://localhost:8080/bran/reach-hodor/

# hodor has no endpoint to reach bran — enforced by network topology
```

---

## 8. Horizontal Autoscaling

### Docker Compose (manual + watch loop)

```bash
# Manual scale
REPLICAS=5 make scale-hodor

# Or watch CPU and scale automatically with a shell loop
watch -n 10 'docker stats --no-stream --format "{{.CPUPerc}}" \
  $(docker compose ps -q hodor) | awk "{sum+=\$1} END {print sum}"'
```

### Kubernetes HPA

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
spec:
  scaleTargetRef:
    name: hodor
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 60          # scale up when avg CPU > 60%
    - type: Pods
      pods:
        metric:
          name: hodor_requests_per_second  # custom Prometheus metric
        target:
          type: AverageValue
          averageValue: "100"             # scale up when >100 RPS/pod
```

**Custom metrics pipeline:**

```
hodor /metrics → Prometheus → prometheus-adapter → K8s metrics API → HPA controller
```

Install prometheus-adapter:

```bash
helm install prometheus-adapter prometheus-community/prometheus-adapter \
  --set prometheus.url=http://prometheus:9090
```

**Scale behaviour:**

```yaml
behavior:
  scaleUp:
    stabilizationWindowSeconds: 30    # react fast to spikes
    policies:
      - type: Pods
        value: 2                      # add max 2 pods per 60s
        periodSeconds: 60
  scaleDown:
    stabilizationWindowSeconds: 120   # wait 2 min before shrinking
```

### Node autoscaling (Cluster Autoscaler)

When HPA wants more pods than nodes can fit, Cluster Autoscaler provisions new nodes:

```bash
# EKS
eksctl create nodegroup --cluster fampay \
  --name workers \
  --node-type t3.medium \
  --nodes-min 2 \
  --nodes-max 10 \
  --asg-use-stack-name

# Install Cluster Autoscaler
helm install cluster-autoscaler autoscaler/cluster-autoscaler \
  --set autoDiscovery.clusterName=fampay \
  --set awsRegion=ap-south-1
```

---

## 9. Continuous Delivery

```
Developer pushes to main
         │
         ▼
┌─────────────────────┐
│  GitHub Actions CI  │
│  1. go test ./...   │
│  2. python manage.py│
│     test            │
│  3. golangci-lint   │
└────────┬────────────┘
         │ (all pass)
         ▼
┌─────────────────────┐
│  Build & Push       │
│  docker buildx      │
│  → GHCR             │
│  tagged with SHA    │
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│  Deploy (prod env)  │
│  kubectl set image  │
│  rollout status     │
│  smoke test         │
└─────────────────────┘
```

**Single command to trigger deployment:**

```bash
git push origin main
# or manually:
./scripts/k8s_deploy.sh <sha>
```

**Rollback:**

```bash
kubectl rollout undo deployment/hodor
kubectl rollout undo deployment/bran
```

---

## 10. Observability: Metrics, Logs & Alerting

### Metrics

- **hodor**: exposes `hodor_requests_total` (counter) and `hodor_request_duration_seconds` (histogram) on `/metrics`
- **bran**: `django-prometheus` auto-instruments all views on `/metrics`
- Prometheus scrapes both every 15s

### Logs

Both services log **structured JSON** to stdout:

```json
{"time":"2024-03-01T10:00:00Z","method":"GET","path":"/hodor/","status":200,"duration_ms":3,"remote_addr":"10.0.0.1"}
```

In Kubernetes, `kubectl logs` or a log aggregator (Loki, Datadog, CloudWatch) collects stdout from all pods.

### Alerting

Alerts defined in `monitoring/alert_rules.yml`:

| Alert | Condition | Severity |
|---|---|---|
| ServiceDown | `up == 0` for 1m | critical |
| HighErrorRate | 5xx rate > 5% for 2m | warning |
| HighLatency | p95 > 1s for 5m | warning |
| HighMemoryUsage | mem > 80% limit for 5m | warning |

Connect Alertmanager to PagerDuty/Slack by configuring `alertmanager.yml`.

---

## 11. Load Testing

```bash
# Using oha (install: brew install oha)
make load-test

# Or directly:
oha -z 30s -c 50 http://localhost:8080/hodor/
oha -z 30s -c 50 http://localhost:8080/bran/

# Using apache bench
ab -n 10000 -c 100 http://localhost:8080/hodor/
```

Watch Grafana at http://localhost:3000 for real-time request rate, error rate, and latency graphs.

---

## 12. Personal Notes

### Favourite languages and tools

**Go** is my first choice for any service that needs to be fast, observable, and operationally simple. The static binary, goroutine model, and explicit error handling make it ideal for infrastructure-adjacent work. I use it for CLIs, APIs, and anything that ships as a container.

**Python** (with Django or FastAPI) for anything that needs to move fast in the business logic layer — great ecosystem, readable, and Django's batteries-included approach is hard to beat for CRUD-heavy services.

**Tools I love:** `kubectl`, `helm`, `k9s` (Kubernetes TUI), `direnv` for env management, `mermaid` for diagrams-as-code, and `just` as a modern Makefile replacement.

### Most important for quality code

**Observability first.** Code that can't be debugged in production is code that will cause incidents. I write structured logs, emit metrics, and add traces before I consider a feature "done." Beyond that: tests that describe *behaviour* not implementation, clear error messages that help the operator, and documentation co-located with the code.

### Favourite open-source projects

- **Prometheus + Grafana** — the gold standard for metrics-based observability
- **htmx** — makes the web simple again
- **cobra** (Go) — best CLI framework
- **SQLAlchemy** — elegant ORM with just enough power

### Favourite books on software

- *Site Reliability Engineering* (Google SRE Book) — essential for production thinking
- *The Go Programming Language* (Donovan & Kernighan) — the definitive Go reference
- *Designing Data-Intensive Applications* (Kleppmann) — changed how I think about systems

### Programming role models

Russ Cox (Go toolchain), Kelsey Hightower (Kubernetes advocacy and clarity of explanation), and Mitchell Hashimoto (HashiCorp tooling philosophy: boring technology that works).
