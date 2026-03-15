# CLAUDE.md — Local Platform Engineer

## 1. Project Overview

This repository is a **local Internal Developer Platform (IDP)** that mirrors how large organizations deploy to AWS EKS, using entirely open-source tooling running on Docker. The purpose is **personal learning: mid → senior engineer growth**.

The core pattern is the **Seeds Repository**: developers submit a YAML file describing their service → automated pipelines create GitHub repos, Helm charts, ArgoCD apps, and infrastructure. Developers never touch Kubernetes directly.

**This is a learning project.** Every design decision has a documented reason. Read the ADRs before making changes.

---

## 2. Architecture Map

```
┌─────────────────────────────────────────────────────────────────┐
│                    LOCAL PLATFORM ENGINEER                      │
│                                                                 │
│  Developer                                                      │
│  ─────────                                                      │
│  1. git push → GitHub                                           │
│  2. Seed YAML → seed-processor (GH Actions)                     │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  k3d Cluster (k3s in Docker)                             │   │
│  │                                                          │   │
│  │  ┌─────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐ │   │
│  │  │  ArgoCD │  │  Harbor  │  │  Vault   │  │  MinIO   │ │   │
│  │  │ (GitOps)│  │(Registry)│  │(Secrets) │  │  (S3)    │ │   │
│  │  └────┬────┘  └──────────┘  └──────────┘  └──────────┘ │   │
│  │       │                                                  │   │
│  │  ┌────▼──────────────────────────────────────────────┐  │   │
│  │  │              App Namespaces                       │  │   │
│  │  │  ┌──────────┐  ┌──────────┐  ┌──────────┐       │  │   │
│  │  │  │  app-dev │  │ app-stg  │  │ app-prod │       │  │   │
│  │  │  └──────────┘  └──────────┘  └──────────┘       │  │   │
│  │  └───────────────────────────────────────────────────┘  │   │
│  │                                                          │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐│   │
│  │  │Prometheus│  │ Grafana  │  │   Loki   │  │  NATS    ││   │
│  │  │(Metrics) │  │(Dashbrd) │  │  (Logs)  │  │(Messaging│|   │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────┘│   │
│  │                                                          │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐               │   │
│  │  │  Kyverno │  │cert-mgr  │  │ ingress  │               │   │
│  │  │(Policies)│  │  (TLS)   │  │  nginx   │               │   │
│  │  └──────────┘  └──────────┘  └──────────┘               │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

**Data flows:**
- Developer → seeds/apps/\*.yaml → GH Actions seed-processor → creates GitHub repo + ArgoCD Application
- Developer pushes code → CI: build → test → Trivy scan → push Harbor → update Helm values
- ArgoCD detects Helm values change → syncs deployment to k3d
- ingress-nginx → routes https://\*.local.dev to pods
- cert-manager → mkcert → locally-trusted TLS for \*.local.dev
- Vault → injects secrets into pods via annotations

---

## 3. Tech Stack

| Component | Tool | Role | AWS Equivalent |
|-----------|------|------|---------------|
| Cluster | k3d (k3s in Docker) | Kubernetes runtime | EKS |
| GitOps | ArgoCD | Continuous delivery | GitLab CI deploy |
| Registry | Harbor | Container image storage | ECR |
| Object store | MinIO | S3-compatible storage | S3 |
| Messaging | NATS JetStream | Pub/sub + queues | SNS/SQS |
| Serverless | OpenFaaS | Function runtime | Lambda |
| Ingress | ingress-nginx | HTTP routing + TLS termination | ALB |
| TLS | cert-manager + mkcert | Local certificate authority | ACM |
| Secrets | HashiCorp Vault | Secret storage + injection | Secrets Manager |
| Metrics | Prometheus | Time-series metrics | CloudWatch metrics |
| Dashboards | Grafana | Visualization | CloudWatch dashboards |
| Logs | Loki + Promtail | Log aggregation | CloudWatch Logs |
| Policy | Kyverno | Admission control + policy | IAM/SCPs |
| IaC | OpenTofu | Infrastructure as code | Terraform + Terragrunt |
| CI | GitHub Actions | Build/test/scan pipelines | GitLab CI |
| Security scan | Trivy + Grype | Container + code scanning | Inspector/ECR scanning |

---

## 4. Critical Paths

### Bootstrap everything from scratch
```bash
./scripts/bootstrap.sh
```
This runs all sub-scripts in order. Takes ~10 minutes on first run.

### Check platform health
```bash
kubectl get pods -A
# All pods should be Running or Completed
kubectl get ingress -A
# All ingresses should have an ADDRESS
```

### Onboard a new application
```bash
cp seeds/apps/example-app.yaml seeds/apps/my-app.yaml
# Edit my-app.yaml with your app's details
git add seeds/apps/my-app.yaml
git commit -m "feat: add my-app seed"
git push origin main
# GH Actions picks up → creates service repo → ArgoCD app appears
```

### Access platform UIs
```
https://argocd.local.dev    admin / (from secret argocd-initial-admin-secret)
https://harbor.local.dev    admin / Harbor12345
https://grafana.local.dev   admin / prom-operator
https://vault.local.dev     token = dev-root-token
https://minio.local.dev     admin / minio-secret-key
```

### Tear down everything
```bash
./scripts/teardown.sh
```

### Update a platform component (e.g., Grafana)
```bash
# Edit platform/monitoring/grafana/values.yaml
git commit -m "chore: update grafana values"
git push
# ArgoCD auto-syncs within 3 minutes (or force sync in UI)
```

---

## 5. Directory Conventions

```
CLAUDE.md           ← You are here. AI context file.
README.md           ← Human-readable overview for GitHub
.claude/commands/   ← Slash commands for Claude Code
docs/               ← Architecture, guides, ADRs, runbooks
docs/adr/           ← Architecture Decision Records (numbered)
docs/runbooks/      ← Step-by-step operational procedures
seeds/              ← THE CORE: Seeds pattern implementation
seeds/apps/         ← Seed YAML files (one per service)
seeds/schema/       ← JSON Schema for seed validation
seeds/processor/    ← Python: reads seeds → creates repos/apps
platform/           ← Kubernetes manifests + Helm values
platform/bootstrap/ ← Applied first: namespaces, RBAC
platform/argocd/    ← ArgoCD itself + App-of-Apps
tofu/               ← OpenTofu (Terraform-compatible) IaC
tofu/modules/       ← Reusable modules (namespace, bucket, etc.)
tofu/environments/  ← Per-environment instantiation
app-template/       ← Cookiecutter template for new services
scripts/            ← Bash scripts for cluster lifecycle
```

**Rules:**
- All Kubernetes manifests go in `platform/` — not scattered elsewhere
- All seed specs go in `seeds/apps/` — one file per service
- All IaC in `tofu/` — never inline kubectl apply in scripts when tofu can do it
- All docs in `docs/` — not in root directory

---

## 6. Coding Standards

### Dockerfile
```dockerfile
# Always multi-stage
FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Always distroless or slim final image
FROM gcr.io/distroless/python3-debian12
WORKDIR /app
COPY --from=builder /app .
# Always non-root
USER nonroot:nonroot
EXPOSE 8080
CMD ["main.py"]
```

Rules:
- Multi-stage builds: always
- Non-root user: always (USER nonroot or numeric UID > 1000)
- No secrets in Dockerfile: never (use Vault injection)
- Pinned base images: use SHA or exact version, not `latest`
- EXPOSE the actual port, not 80

### Helm Charts
```yaml
# values.yaml must always have:
image:
  repository: harbor.local.dev/myproject/myapp
  tag: "latest"     # CI overrides this
  pullPolicy: IfNotPresent

resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "256Mi"

# Always include health probes
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
```

Rules:
- Resource limits: always set (Kyverno will reject if missing)
- Health probes: always define liveness + readiness
- Labels: always include `app.kubernetes.io/name`, `app.kubernetes.io/version`
- No hardcoded secrets: use `valueFrom.secretKeyRef` pointing to Vault-injected secrets
- HPA: include for any service that will handle HTTP traffic

### Python (seeds processor)
- Use type hints on all function signatures
- Validate inputs with Pydantic models
- Use `pathlib.Path` not `os.path`
- Errors: raise specific exceptions, log with structlog
- No print statements: use `logging.getLogger(__name__)`

### YAML (seed specs)
- Use 2-space indentation
- Quote strings that look like other types (e.g., `"true"`, `"1.0"`)
- Include all required fields explicitly — no relying on defaults
- Comments explaining non-obvious values

### Shell scripts
- Always `set -euo pipefail` at the top
- Functions for reusable logic
- `echo "→ Doing X..."` style progress messages
- Check prerequisites before doing anything
- Idempotent: running twice should be safe

---

## 7. Testing Strategy

| Layer | What to test | How |
|-------|-------------|-----|
| Seed YAML | Schema validation | `python -m jsonschema` or Pydantic |
| Seed processor | Unit tests for template generation | pytest + mocks for GitHub API |
| Helm charts | Template rendering | `helm template` + kubeconform |
| Kyverno policies | Policy evaluation | `kyverno test` |
| OpenTofu modules | Plan output | `tofu plan` against local providers |
| Platform configs | Dry-run apply | ArgoCD sync preview |
| End-to-end | Full seed → running app | Manual verification checklist |

Run unit tests:
```bash
cd seeds/processor && python -m pytest tests/
cd platform/kyverno && kyverno test policies/
helm template app-template/helm | kubeconform -
```

---

## 8. Git Workflow

### Branch naming
```
feat/add-vault-integration
fix/argocd-sync-failing
chore/update-prometheus-values
docs/add-runbook-cert-rotation
```

### Commit message format (Conventional Commits)
```
feat: add NATS JetStream support to seed processor
fix: correct Harbor project creation when name has hyphens
chore: bump ArgoCD to 2.10.0
docs: add runbook for certificate rotation
test: add unit tests for argocd.py template generation
```

### PR checklist
- [ ] `helm template` renders without errors
- [ ] `tofu validate` passes
- [ ] Kyverno policies pass for any new manifests
- [ ] Seed schema updated if seed spec changed
- [ ] Relevant docs updated

---

## 9. Common Tasks

### Restart a stuck ArgoCD app sync
```bash
argocd app sync <app-name> --force
# Or via UI: App → Sync → Force
```

### Rotate Vault root token
```bash
kubectl exec -n vault vault-0 -- vault token create -policy=root -ttl=24h
```

### Re-generate TLS certs
```bash
mkcert -install
mkcert "*.local.dev" local.dev
kubectl -n cert-manager create secret tls local-dev-tls \
  --cert=_wildcard.local.dev+1.pem \
  --key=_wildcard.local.dev+1-key.pem \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Force rebuild and push an image
```bash
docker build -t harbor.local.dev/myproject/myapp:dev .
docker push harbor.local.dev/myproject/myapp:dev
kubectl rollout restart deployment/myapp -n myapp-dev
```

### Check why a pod won't start
```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous
# Common: ImagePullBackOff → check Harbor credentials
# Common: CrashLoopBackOff → check app logs
```

### Access Vault in dev mode
```bash
kubectl exec -it vault-0 -n vault -- vault login dev-root-token
kubectl exec -it vault-0 -n vault -- vault kv get secret/myapp/config
```

### Watch ArgoCD sync status
```bash
watch argocd app list
# Or:
kubectl get applications -n argocd
```

---

## 10. Do's and Don'ts

### Do
- **DO** read the ADR for any component before changing its configuration
- **DO** test Helm template rendering before pushing: `helm template ./helm`
- **DO** use `kubectl diff` before `kubectl apply` for manual changes
- **DO** add resource limits to every container (Kyverno enforces this)
- **DO** label every Kubernetes resource with standard labels
- **DO** store all secrets in Vault — never in Git
- **DO** write a runbook before performing any complex operational procedure
- **DO** validate seed YAMLs against the schema before pushing
- **DO** check ArgoCD sync status after every platform change
- **DO** document why, not just what, in commit messages

### Don't
- **DON'T** use `kubectl apply` directly on platform components — use ArgoCD
- **DON'T** commit secrets, tokens, or passwords to Git
- **DON'T** use `latest` tag for images in production namespaces (Kyverno blocks this)
- **DON'T** skip resource limits — Kyverno will reject the pod
- **DON'T** modify ArgoCD apps directly in the cluster — change the Git manifest
- **DON'T** run `kubectl delete` on platform namespaces — use the teardown script
- **DON'T** add platform-specific logic to app-template — it must stay generic
- **DON'T** hardcode the cluster name — use the k3d cluster name variable

---

## 11. Terminology Glossary

| Term | Definition |
|------|-----------|
| **Seed** | A YAML file describing a service's desired state (name, language, infra needs) |
| **Seed Processor** | Python script + GH Actions that reads a Seed → creates everything |
| **App-of-Apps** | ArgoCD pattern: one root Application that manages all other Applications |
| **GitOps** | All cluster state lives in Git; ArgoCD reconciles cluster to Git state |
| **k3d** | Tool that runs k3s (lightweight Kubernetes) inside Docker containers |
| **Helm release** | An instance of a Helm chart deployed to Kubernetes |
| **Kyverno** | Kubernetes-native policy engine — replaces OPA/Gatekeeper |
| **NATS JetStream** | NATS messaging with persistence; stream = topic, consumer = subscription |
| **OpenTofu** | Open-source fork of Terraform, 100% HCL-compatible |
| **Distroless** | Container images with no shell, package manager, or OS utilities |
| **mkcert** | Tool to create locally-trusted TLS certificates without a real CA |
| **Harbor** | Enterprise container registry with scanning, RBAC, and replication |
| **Promtail** | Log collector (like Fluentd) that ships logs to Loki |
| **PDB** | PodDisruptionBudget — ensures N pods always available during node drain |
| **HPA** | HorizontalPodAutoscaler — scales pods based on CPU/memory/custom metrics |

---

## 12. Ports and Local DNS

After running `scripts/05-setup-local-dns.sh`, these hostnames resolve locally:

| URL | Service | Port |
|-----|---------|------|
| https://argocd.local.dev | ArgoCD UI | 443 → 80 in k3d |
| https://harbor.local.dev | Harbor registry | 443 |
| https://grafana.local.dev | Grafana dashboards | 443 |
| https://vault.local.dev | Vault UI | 443 |
| https://minio.local.dev | MinIO console | 443 |
| https://nats.local.dev | NATS monitoring | 443 |

k3d exposes ports: 80 → NodePort 80, 443 → NodePort 443 on localhost.

---

## 13. Environment Variables (CI/CD)

Required GitHub Actions secrets for seed-processor:
```
GITHUB_TOKEN          # PAT with repo + workflow permissions
ARGOCD_SERVER         # argocd.local.dev (or local cluster IP)
ARGOCD_TOKEN          # ArgoCD API token
HARBOR_URL            # harbor.local.dev
HARBOR_USERNAME       # robot account username
HARBOR_PASSWORD       # robot account secret
VAULT_ADDR            # https://vault.local.dev
VAULT_TOKEN           # Vault token with write permissions
```

---

## 14. Troubleshooting Quick Reference

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| ArgoCD app stuck in Progressing | Resource not ready | Check pod events |
| ImagePullBackOff | Harbor auth or image not found | `docker login harbor.local.dev` |
| CrashLoopBackOff | App startup failure | Check pod logs |
| Ingress not routing | cert-manager not ready | Check cert-manager pods |
| Vault sealed after restart | k3d node restart | `kubectl exec vault-0 -n vault -- vault operator unseal` |
| Kyverno block in logs | Missing labels or limits | Add required labels/limits |
| ArgoCD OutOfSync always | Manual kubectl changes | Don't use kubectl on managed resources |
| NATS connection refused | NATS pod not ready | Wait for NATS cluster to form |
