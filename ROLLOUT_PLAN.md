# Rollout Plan

## Goal
Safely migrate payment traffic from `gateway-v1` to `gateway-v2` with **zero hard cutover**, **continuous observability**, and **instant rollback**.

## Pre-flight checklist

1. Generate credentials and start stack:
   ```bash
   ./scripts/bootstrap-secrets.sh
   docker compose up -d --build
   ```
2. Validate all services healthy:
   ```bash
   ./scripts/health-check.sh
   docker compose ps
   ```
3. Confirm dashboard/alerts active:
   - Prometheus: http://localhost:9090
   - Grafana: http://localhost:3000

## Phases

### Phase 1 - Canary (10% v2)

```bash
./scripts/rollout.sh 1 all
```

Observe for 10-15 minutes:
- v2 error rate < 2%
- v2 p95 latency not materially worse than v1
- v2 authorization rate stable

Rollback if needed:

```bash
./scripts/rollback.sh all 1
```

### Phase 2 - Controlled Expansion (50% v2)

```bash
./scripts/rollout.sh 2 all
```

Observe for 15-30 minutes with production-like traffic:

```bash
./scripts/generate-traffic.sh 300 20
```

Rollback to Phase 1:

```bash
./scripts/rollback.sh all 1
```

### Phase 3 - High Confidence (90% v2)

```bash
./scripts/rollout.sh 3 all
```

Observe and confirm stability.

Rollback to Phase 2:

```bash
./scripts/rollback.sh all 2
```

### Phase 4 - Full Cutover (100% v2)

```bash
./scripts/rollout.sh 4 all
```

Maintain elevated monitoring window.

Emergency rollback to v1-heavy phase:

```bash
./scripts/rollback.sh all 1
```

## Regional sequencing (optional strategy)

Migrate by region order: **São Paulo → Rio → Brasília**:

```bash
./scripts/regional-rollout.sh
```

This ensures highest-volume region gains confidence before expanding blast radius.

## Automated rollback hook (optional)

```bash
./scripts/auto-rollback-monitor.sh saopaulo 2 1 0.02
```

If v2 error rate exceeds 2%, script automatically applies rollback phase.

## Decision matrix (proceed vs halt)

Proceed only if all hold true:
- v2 error rate <= 2%
- v2 p95 latency <= 800ms and not significantly above v1
- v2 authorization rate >= 88% and no sustained decline

Halt/rollback if any threshold breaches for configured alert duration.

