# São Paulo Gateway Migration - Blue/Green Multi-Region Rollout

This repository implements a **phased, reversible migration** from `gateway-v1` to `gateway-v2` across simulated Brazil regions:

- São Paulo (`localhost:8001`)
- Rio (`localhost:8002`)
- Brasília (`localhost:8003`)

The solution is built with Docker Compose, Nginx traffic routing, Prometheus alerts, and Grafana dashboards.

---

## 1) What this delivers

### Base requirements
- ✅ Both versions run concurrently in isolated containers per region
- ✅ Traffic shifting across versions (10% → 50% → 90% → 100%)
- ✅ Health checks (`/health`, `/ready`, docker healthcheck)
- ✅ Region simulation via dedicated service pairs + router per region
- ✅ Credentials loaded from mounted secret files (not hardcoded in images/config)
- ✅ Reversible rollout scripts (`rollout.sh`, `rollback.sh`, `set-phase.sh`)
- ✅ Observability and alerting config (Prometheus + Grafana + rules)

### Stretch goals
- ✅ Automated rollback trigger script (`auto-rollback-monitor.sh`)
- ✅ Secrets rotation simulation without restart (`rotate-v2-credentials.sh` + file watcher)
- ✅ Regional sequencing script (`regional-rollout.sh`)

---

## 2) Architecture overview

Per region:

- `gateway-v1-<region>` and `gateway-v2-<region>` run in parallel
- `router-<region>` (Nginx) routes requests with weighted split
- `/authorize` traffic is split by active rollout phase config

Global monitoring:

- `prometheus` scrapes gateway metrics
- `grafana` provides migration dashboard
- alert rules detect error-rate spikes, latency degradation, auth-rate drops

---

## 3) Prerequisites

- Docker + Docker Compose v2
- `curl`, `jq`, `openssl`

---

## 4) Quick start

```bash
# 1) Generate local runtime credentials (simulated secrets)
./scripts/bootstrap-secrets.sh

# 2) Start stack
docker compose up -d --build

# 3) Verify health and rollout status
./scripts/health-check.sh
```

Useful URLs:

- São Paulo router: http://localhost:8001/health
- Rio router: http://localhost:8002/health
- Brasília router: http://localhost:8003/health
- Prometheus: http://localhost:9090
- Grafana: http://localhost:3000 (admin/admin)

---

## 5) Rollout phases

- **Phase 1**: 10% v2 / 90% v1
- **Phase 2**: 50% v2 / 50% v1
- **Phase 3**: 90% v2 / 10% v1
- **Phase 4**: 100% v2 / 0% v1

Each region has independent phase configs under:

- `nginx/regions/saopaulo/phases/`
- `nginx/regions/rio/phases/`
- `nginx/regions/brasilia/phases/`

### Execute rollout

```bash
# all regions to phase 2
./scripts/rollout.sh 2 all

# only São Paulo to phase 3
./scripts/rollout.sh 3 saopaulo
```

### Rollback

```bash
# rollback São Paulo to phase 1 instantly
./scripts/rollback.sh saopaulo 1

# rollback all regions to full v1 profile (phase 1)
./scripts/rollback.sh all 1
```

---

## 6) Observability and rollback decision signals

Tracked metrics:

1. **Traffic volume by version**
   - `sum(rate(gateway_requests_total{endpoint="/authorize"}[1m])) by (version)`
2. **Error rate by version**
   - `rate(gateway_requests_total{status="5xx",endpoint="/authorize"}[2m]) / rate(gateway_requests_total{endpoint="/authorize"}[2m])`
3. **Latency (p95)**
   - `histogram_quantile(0.95, rate(gateway_request_duration_seconds_bucket[5m]))`
4. **Authorization rate by version**
   - `rate(gateway_authorizations_total{outcome="approved"}[5m]) / rate(gateway_authorizations_total[5m])`

Alerts (Prometheus rules):

- `GatewayV2ErrorRateHigh` (critical): v2 error rate > 2% for 2m
- `GatewayV2P95LatencyHigh` (warning): p95 latency > 800ms for 5m
- `AuthorizationRateDropV2` (critical): auth rate < 88% for 5m

---

## 7) Automated rollback (stretch)

```bash
# Watch São Paulo phase-2 and rollback to phase-1 if v2 error rate > 2%
./scripts/auto-rollback-monitor.sh saopaulo 2 1 0.02
```

---

## 8) Secrets rotation simulation (stretch)

Rotate only v2 credentials in-place, no restart:

```bash
./scripts/rotate-v2-credentials.sh
```

Gateway services watch credential file updates and reload automatically.

---

## 9) Region-by-region sequencing (stretch)

```bash
./scripts/regional-rollout.sh
```

This script migrates São Paulo first, then Rio, then Brasília, with operator confirmation between phases.

---

## 10) Files of interest

- `docker-compose.yml`
- `nginx/regions/*/phases/phase*.conf`
- `monitoring/prometheus/prometheus.yml`
- `monitoring/prometheus/alert-rules.yml`
- `monitoring/grafana/dashboards/rollout-dashboard.json`
- `scripts/rollout.sh`, `scripts/rollback.sh`, `scripts/auto-rollback-monitor.sh`
- `DESIGN_DECISIONS.md`
- `ROLLOUT_PLAN.md`



---

## 11) AWS Terraform starter layer (`infra/`)

This repository now includes a cloud IaC starter under `infra/` for AWS (VPC, ALB weighted routing, ECS services, ECR, IAM/logging placeholders).

### Validate locally (no AWS apply)

```bash
cd infra
terraform init -backend=false
terraform fmt -recursive
terraform validate
```

### Plan/apply locally (requires AWS credentials configured)

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
# edit image URIs and values
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### Also run the local Docker simulation

```bash
./scripts/bootstrap-secrets.sh
docker compose up -d --build
./scripts/health-check.sh
```

> If Docker is not available in your environment (e.g., WSL without Docker Desktop integration), run from a host with Docker enabled.


---

## 12) Blue-Green drill automation

Run a full switch-to-green (phase 4), traffic test, and rollback drill automatically:

```bash
# all regions: switch to v2, test 60s, rollback to original phase automatically
./scripts/blue-green-drill.sh all 60 10 auto 40

# single region example
./scripts/blue-green-drill.sh saopaulo 45 12 auto 30

# force rollback to phase 1 after drill
./scripts/blue-green-drill.sh all 60 10 1 40
```

Arguments:

1. target: `all|saopaulo|rio|brasilia`
2. test duration seconds (default `60`)
3. concurrency passed to traffic generator (default `10`)
4. rollback phase: `auto|1|2|3|4` (default `auto`)
5. samples per region to estimate version distribution (default `40`)
