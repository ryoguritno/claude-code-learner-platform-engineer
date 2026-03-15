# Local Platform Engineer

A local Internal Developer Platform (IDP) that mirrors how large organizations deploy to AWS EKS — using entirely open-source tooling running on Docker. Built for **personal learning: mid → senior platform engineer growth**.

## The Concept

Developers submit a single YAML file. The platform handles everything else:

```
seeds/apps/my-app.yaml  →  GitHub repo + ArgoCD app + Vault secrets + MinIO bucket
                                          ↓
                           Developer writes code, pushes
                                          ↓
                           CI: build → test → Trivy scan → push Harbor
                                          ↓
                           ArgoCD syncs → app live at https://my-app.local.dev
```

## Tech Stack

| AWS Service | Open Source Alternative |
|-------------|------------------------|
| EKS | k3d (k3s in Docker) |
| GitLab CI | GitHub Actions |
| ECR | Harbor |
| S3 | MinIO |
| SNS/SQS | NATS JetStream |
| Lambda | OpenFaaS |
| ALB/Ingress | ingress-nginx |
| ACM (TLS) | cert-manager + mkcert |
| Secrets Manager | HashiCorp Vault |
| CloudWatch | Prometheus + Grafana + Loki |
| IAM/Policy | Kyverno |
| Terraform | OpenTofu |

## Prerequisites

- Docker (running)
- kubectl
- Helm 3
- k3d (`brew install k3d` or `curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash`)
- mkcert (`brew install mkcert` or see <https://github.com/FiloSottile/mkcert>)
- ArgoCD CLI (`brew install argocd`)
- Vault CLI (`brew install vault`)
- Python 3.11+
- GitHub account + personal access token

## Quick Start

```bash
# 1. Clone this repo
git clone https://github.com/ryoguritno/local-platform-engineer
cd local-platform-engineer

# 2. Copy and configure secrets
cp .env.example .env
# Edit .env with your GitHub token and other values

# 3. Bootstrap everything (~10 minutes)
./scripts/bootstrap.sh

# 4. Add /etc/hosts entries (requires sudo)
./scripts/05-setup-local-dns.sh

# 5. Access the platform
open https://argocd.local.dev    # GitOps dashboard
open https://harbor.local.dev    # Container registry
open https://grafana.local.dev   # Metrics & logs
open https://vault.local.dev     # Secrets management
```

## Onboarding Your First App

```bash
# Copy the example seed spec
cp seeds/apps/example-app.yaml seeds/apps/my-first-app.yaml

# Edit to describe your app
vim seeds/apps/my-first-app.yaml

# Push it — GitHub Actions does the rest
git add seeds/apps/my-first-app.yaml
git commit -m "feat: add my-first-app"
git push origin main
```

Within ~2 minutes:

- A new GitHub repository is created for your app
- ArgoCD Application is registered
- Vault secrets path is provisioned
- MinIO bucket is created (if requested)
- NATS stream is created (if requested)

## Platform UIs

After bootstrapping:

| Service | URL | Default Credentials |
|---------|-----|-------------------|
| ArgoCD | <https://argocd.local.dev> | admin / see bootstrap output |
| Harbor | <https://harbor.local.dev> | admin / Harbor12345 |
| Grafana | <https://grafana.local.dev> | admin / prom-operator |
| Vault | <https://vault.local.dev> | token: dev-root-token |
| MinIO | <https://minio.local.dev> | admin / minio-secret-key |

## Repository Structure

```
CLAUDE.md               ← AI context + engineering standards
README.md               ← This file
seeds/                  ← THE CORE: Service onboarding
  apps/                 ← Seed YAML files (one per service)
  schema/               ← JSON Schema validation
  processor/            ← Python automation
platform/               ← Kubernetes configs + Helm values
  argocd/               ← ArgoCD installation + App-of-Apps
  bootstrap/            ← Namespaces, RBAC, priority classes
  [component]/          ← One directory per platform tool
tofu/                   ← OpenTofu (Terraform) IaC
  modules/              ← Reusable modules
  environments/         ← dev / staging / prod
app-template/           ← Template for new service repos
  helm/                 ← Full Helm chart
  src/                  ← Example FastAPI app
scripts/                ← Cluster lifecycle scripts
docs/                   ← Architecture, guides, ADRs, runbooks
```

## Documentation

- [Architecture](docs/00-architecture.md) — System design and component map
- [Getting Started](docs/01-getting-started.md) — Prerequisites and first-time setup
- [Developer Guide](docs/02-developer-guide.md) — Using the Seeds workflow
- [Platform Internals](docs/03-platform-internals.md) — How it all wires together
- [GitOps Workflow](docs/04-gitops-workflow.md) — ArgoCD + Helm patterns
- [Secrets Management](docs/05-secrets-management.md) — Vault integration
- [Observability](docs/06-observability.md) — Metrics, logs, dashboards
- [Security](docs/07-security.md) — Trivy, Grype, Kyverno policies

### Architecture Decision Records

- [ADR-001: k3d over minikube](docs/adr/001-k3d-over-minikube.md)
- [ADR-002: ArgoCD GitOps](docs/adr/002-argocd-gitops.md)
- [ADR-003: Harbor Registry](docs/adr/003-harbor-registry.md)
- [ADR-004: Vault Secrets](docs/adr/004-vault-secrets.md)
- [ADR-005: OpenTofu IaC](docs/adr/005-opentofu-iac.md)

## Teardown

```bash
./scripts/teardown.sh
```

This removes the k3d cluster and all local state. Your seed YAML files remain in Git.

## Learning Goals

By working through this project you will understand:

- How platform teams abstract Kubernetes from application developers
- GitOps with ArgoCD: App-of-Apps pattern, sync policies, health checks
- Secrets management: Vault agent injection, dynamic secrets
- Container security: Trivy scanning, Kyverno admission control
- Observability: Prometheus scraping, Grafana dashboards, Loki log aggregation
- IaC patterns: OpenTofu modules, provider configuration, state management
- CI/CD pipelines: build → scan → push → deploy automation
