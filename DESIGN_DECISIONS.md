# Design Decisions

## 1) Why this approach

I chose a **blue-green + canary hybrid** with Docker Compose and Nginx:

- Blue-green principle: v1 and v2 run simultaneously at all times
- Canary behavior: phased traffic weights (10/50/90/100)

This gives low operational complexity while still supporting smooth, reversible rollout.

## 2) Tooling choices

- **Docker Compose**: fast to review and run locally in an assessment context
- **Nginx**: deterministic weighted routing with simple config files
- **Prometheus + Grafana**: open-source, config-as-code observability
- **Shell scripts**: explicit operator actions for rollout/rollback

## 3) Trade-offs considered

### Docker Compose vs Kubernetes
- Compose chosen for speed and clarity
- K8s would provide richer readiness gates, service mesh, and policy controls but adds setup overhead

### Manual vs fully automated rollout
- Manual progression by phase is explicit and auditable
- Added optional automation script (`auto-rollback-monitor.sh`) for safety

### Simulated secrets vs external secrets manager
- Local file-mounted secrets used for simulation
- Production should use Vault / AWS Secrets Manager + workload identity

## 4) Failure handling

### Instance crash during rollout
- Docker health checks detect unhealthy gateway containers
- Nginx passive failover (`proxy_next_upstream`) retries alternate upstream
- Rollback scripts can instantly move traffic weight back

### Credential access failure
- `/health` and `/ready` fail when credentials unavailable
- Container health becomes unhealthy
- Operator can halt rollout and rotate/reapply credentials

### Network partition / processor instability
- Error-rate and latency alerts trigger halt/rollback criteria
- Phase-based routing makes rollback deterministic and fast

## 5) Production-grade differences beyond 2-hour exercise

- Real multi-region (e.g., AWS São Paulo / Rio / Brasília topology)
- Managed L7 load balancer or service mesh (Envoy/Istio)
- Centralized secrets manager + automatic rotation workflows
- CI/CD promotion gates with SLO checks before phase advancement
- Distributed tracing and processor-specific circuit breakers
- Chaos testing and game days before migration windows

## 6) Ambiguity resolution decisions

- **"Region simulation"**: implemented as isolated service pairs + router per region
- **"Traffic control"**: Nginx weighted split via phase config files and scripts
- **"Health checks"**: app-level endpoints + compose health checks + Nginx failover config
- **"Secrets management"**: mounted secret files generated at runtime, watched by services


## 7) Cloud IaC alignment update (EKS)

- The local runnable stack remains Docker Compose + Nginx for fast assessment execution.
- The Terraform starter layer was updated from ECS to **EKS** to align with the Kubernetes trade-off discussion.
- EKS allows future extension with ingress canary annotations/service mesh and stronger parity with production Kubernetes patterns.
- `infra/k8s/` includes starter manifests and a `set-phase.sh` helper for phase-based canary weight switching.

## 8) Why NGINX ingress canary annotations (vs service mesh)

- For this exercise, NGINX Ingress canary annotations (`nginx.ingress.kubernetes.io/canary-weight`) provide a direct and understandable weight control mechanism with low setup cost.
- Compared to Istio/Linkerd, NGINX has fewer moving parts for a reviewer to run quickly while still demonstrating weighted progressive delivery.
- Trade-off accepted: service mesh would provide richer traffic policies (header-based routing, per-route retries/timeouts, mTLS policy uniformity), but introduces significantly more operational surface area for a short assessment.

## 9) Secrets design and least-privilege model

- Runtime plaintext credentials are treated as local simulation only and are generated on-demand (`bootstrap-secrets.sh`) with restrictive file permissions (`umask 077`).
- Cloud path uses AWS Secrets Manager as source of truth plus External Secrets Operator for synchronized K8s Secret materialization.
- IRSA is used so workload pods assume a dedicated IAM role bound to a specific service account identity per namespace.
- IAM policy scope is restricted to:
  - `secretsmanager:DescribeSecret`
  - `secretsmanager:GetSecretValue`
  - and only the three regional processor credential secret ARNs created by Terraform.

## 10) In-flight transaction behavior during rollback

- Rollback changes only **routing weights**, not pod identities or active connections.
- Requests already proxied to v2 continue to completion; new traffic follows the updated lower v2 weight immediately.
- This avoids forced connection termination and reduces operator-induced error spikes during rollback events.
- In production, this should be paired with:
  - idempotency keys for payment authorization requests
  - bounded retry budgets
  - explicit timeout and circuit-breaker policy per processor dependency.

## 11) Capacity planning and scaling assumptions

- Current manifests define explicit CPU/memory requests and limits to avoid noisy-neighbor behavior and make scheduling intent visible.
- Node sizing defaults (3 x `t3.medium`) are sufficient for exercise load; production should derive required node count from p95 latency targets and expected QPS by region.
- Recommended production controls not fully implemented here:
  - HPA on request rate/CPU + custom latency/error signals
  - cluster autoscaler with controlled scale-up/down windows
  - separate node groups or taints for critical gateway workloads.

## 12) Data consistency and migration safety

- Gateway services are intentionally stateless request processors; rollout does not require state migration between v1 and v2.
- Consistency risk shifts to downstream payment processor interactions. To protect correctness:
  - keep request schema backward-compatible through full migration window
  - record version label on all auth outcomes and errors for post-incident correlation
  - preserve deterministic rollback path (phase rollback to 1/2) so behavior can be restored quickly.

## 13) Additional failure modes considered

- **Phase transition misconfiguration** (wrong canary weight or namespace): mitigated by explicit phase script mapping and namespace scoping.
- **Secret sync lag** (Secrets Manager update not yet reflected): mitigated by periodic refresh interval and readiness probes that fail fast when credentials are unavailable.
- **Regional partial degradation**: operators can halt one region while continuing stable regions due to per-region isolation and independent phase control.

## 14) Regional sequencing rationale

- Preferred sequence: **São Paulo → Rio → Brasília**.
- São Paulo typically represents the largest traffic share, so validating there first provides highest confidence signal before expanding blast radius.
- If São Paulo is unstable, rollback occurs before broadening impact to lower-volume regions.
