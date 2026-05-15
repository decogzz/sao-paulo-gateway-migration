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
