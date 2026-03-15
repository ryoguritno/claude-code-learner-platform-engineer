# Architecture — Local Platform Engineer

## Overview

This platform implements the **Seeds Repository** pattern for internal developer platforms. The goal: developers describe *what* they want, the platform handles *how* to create and manage it.

## System Components

### Control Plane

| Component | Namespace | Role |
|-----------|-----------|------|
| ArgoCD | argocd | GitOps controller — syncs Git → cluster |
| cert-manager | cert-manager | TLS certificate issuance and renewal |
| ingress-nginx | ingress-nginx | HTTP/HTTPS reverse proxy + routing |
| Kyverno | kyverno | Policy admission controller |

### Platform Services

| Component | Namespace | Role |
|-----------|-----------|------|
| Harbor | harbor | Container image registry |
| HashiCorp Vault | vault | Secret storage + injection |
| MinIO | minio | S3-compatible object storage |
| NATS JetStream | nats | Messaging (pub/sub + queues) |
| OpenFaaS | openfaas | Serverless function runtime |

### Observability

| Component | Namespace | Role |
|-----------|-----------|------|
| Prometheus | monitoring | Metrics collection and alerting |
| Grafana | monitoring | Dashboard visualization |
| Loki | monitoring | Log aggregation |
| Promtail | monitoring | Log collection (DaemonSet) |

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        LOCAL PLATFORM ENGINEER                          │
│                                                                         │
│  ┌─────────────┐                                                        │
│  │  Developer  │                                                        │
│  └──────┬──────┘                                                        │
│         │                                                               │
│         │ 1. git push seeds/apps/my-app.yaml                           │
│         ▼                                                               │
│  ┌─────────────────────────────────────────────────────────────┐       │
│  │  GitHub Repository (seeds repo)                             │       │
│  │                                                             │       │
│  │  GH Actions: seed-processor.yml                             │       │
│  │  ┌──────────────────────────────────────────────────────┐   │       │
│  │  │ 1. Validate YAML against schema                      │   │       │
│  │  │ 2. Create service GitHub repo from app-template      │   │       │
│  │  │ 3. Apply ArgoCD Application manifest                 │   │       │
│  │  │ 4. Run tofu for infra (namespace, bucket, stream)    │   │       │
│  │  └──────────────────────────────────────────────────────┘   │       │
│  └─────────────────────────────────────────────────────────────┘       │
│         │                                                               │
│         │ 2. Service repo created, ArgoCD app registered               │
│         ▼                                                               │
│  ┌─────────────────────────────────────────────────────────────┐       │
│  │  k3d Cluster (k3s in Docker)                                │       │
│  │                                                             │       │
│  │  ┌─────────────────────────────────────────────────────┐   │       │
│  │  │  Control Plane (kube-system + system namespaces)    │   │       │
│  │  │  ┌──────────┐ ┌───────────┐ ┌─────────┐           │   │       │
│  │  │  │  ArgoCD  │ │cert-mgr   │ │ Kyverno │           │   │       │
│  │  │  │(GitOps)  │ │(TLS)      │ │(Policy) │           │   │       │
│  │  │  └────┬─────┘ └───────────┘ └─────────┘           │   │       │
│  │  │       │ App-of-Apps                                │   │       │
│  │  └───────┼─────────────────────────────────────────────┘   │       │
│  │          │                                                  │       │
│  │  ┌───────▼──────────────────────────────────────────────┐  │       │
│  │  │  Platform Services                                   │  │       │
│  │  │  ┌────────┐ ┌───────┐ ┌───────┐ ┌───────────────┐  │  │       │
│  │  │  │ Harbor │ │ Vault │ │ MinIO │ │ NATS JetStream│  │  │       │
│  │  │  └────────┘ └───────┘ └───────┘ └───────────────┘  │  │       │
│  │  │  ┌────────┐                                         │  │       │
│  │  │  │OpenFaaS│                                         │  │       │
│  │  │  └────────┘                                         │  │       │
│  │  └──────────────────────────────────────────────────────┘  │       │
│  │                                                             │       │
│  │  ┌──────────────────────────────────────────────────────┐  │       │
│  │  │  App Namespaces (per service, per environment)       │  │       │
│  │  │  ┌────────────┐  ┌────────────┐  ┌────────────┐    │  │       │
│  │  │  │  my-app-dev│  │ my-app-stg │  │my-app-prod │    │  │       │
│  │  │  │  ┌────────┐│  │  ┌────────┐│  │ ┌────────┐ │    │  │       │
│  │  │  │  │  Pod   ││  │  │  Pod   ││  │ │  Pod   │ │    │  │       │
│  │  │  │  └────────┘│  │  └────────┘│  │ └────────┘ │    │  │       │
│  │  │  └────────────┘  └────────────┘  └────────────┘    │  │       │
│  │  └──────────────────────────────────────────────────────┘  │       │
│  │                                                             │       │
│  │  ┌──────────────────────────────────────────────────────┐  │       │
│  │  │  Observability                                       │  │       │
│  │  │  ┌──────────┐  ┌────────┐  ┌──────┐  ┌──────────┐  │  │       │
│  │  │  │Prometheus│  │Grafana │  │ Loki │  │ Promtail │  │  │       │
│  │  │  └──────────┘  └────────┘  └──────┘  └──────────┘  │  │       │
│  │  └──────────────────────────────────────────────────────┘  │       │
│  │                                                             │       │
│  │  ┌──────────────────────────────────────────────────────┐  │       │
│  │  │  ingress-nginx (reverse proxy)                       │  │       │
│  │  │  *.local.dev → services via Ingress resources        │  │       │
│  │  └──────────────────────────────────────────────────────┘  │       │
│  └─────────────────────────────────────────────────────────────┘       │
│         │                                                               │
│         │ 3. https://my-app.local.dev                                  │
│         ▼                                                               │
│  ┌─────────────┐                                                        │
│  │  Developer  │                                                        │
│  │  (browser)  │                                                        │
│  └─────────────┘                                                        │
└─────────────────────────────────────────────────────────────────────────┘
```

## Key Design Decisions

### 1. App-of-Apps Pattern (ArgoCD)

ArgoCD manages platform components using the App-of-Apps pattern:

```
platform-apps (root Application)
├── argocd-app → harbor
├── argocd-app → vault
├── argocd-app → minio
├── argocd-app → nats
├── argocd-app → prometheus-stack
├── argocd-app → loki
├── argocd-app → ingress-nginx
├── argocd-app → cert-manager
├── argocd-app → kyverno
└── argocd-app → openfaas
```

One `git push` to update a Helm values file → ArgoCD picks it up → component updated. No manual `helm upgrade` needed.

### 2. Seeds Pattern

The Seeds pattern is the developer-facing API:

```
seeds/apps/my-app.yaml
    ↓
seed-processor (Python)
    ├── Creates GitHub repo (PyGithub API)
    ├── Copies app-template → new repo
    ├── Creates ArgoCD Application manifest
    └── Runs tofu for namespace + infra
```

This is the core innovation: **infrastructure as data** (YAML) not infrastructure as scripts.

### 3. GitOps for Everything

All cluster state is in Git:
- Platform component config → `platform/*/values.yaml`
- App deployments → ArgoCD Application manifests
- Policies → `platform/kyverno/policies/`
- Secrets paths → Vault (actual values never in Git)

If someone manually changes something in the cluster, ArgoCD reverts it.

### 4. TLS with mkcert

For local development, we use mkcert to create a local CA:
```
mkcert -install           # Install local CA in system trust store
mkcert "*.local.dev"     # Generate wildcard cert
```
cert-manager manages cert lifecycle inside the cluster.

## Network Architecture

```
Developer Browser
        │
        │ HTTPS *.local.dev
        ▼
localhost:443 (Docker port binding)
        │
        ▼
k3d LoadBalancer Service
        │
        ▼
ingress-nginx DaemonSet
        │
        ├── /  → argocd.local.dev → ArgoCD service
        ├── /  → harbor.local.dev → Harbor service
        ├── /  → grafana.local.dev → Grafana service
        ├── /  → vault.local.dev → Vault service
        ├── /  → my-app.local.dev → my-app service
        └── ...
```

## Secret Flow

```
Developer creates seed YAML with secrets.enabled: true
        ↓
seed-processor creates Vault path: secret/my-app/config
        ↓
Developer puts actual values in Vault:
  vault kv put secret/my-app/config DATABASE_URL=postgres://...
        ↓
Pod annotation:
  vault.hashicorp.com/agent-inject: "true"
  vault.hashicorp.com/role: "my-app"
        ↓
Vault agent sidecar injects secrets as files at runtime
        ↓
App reads secrets from /vault/secrets/config
```

Secrets **never** touch Git.

## CI/CD Flow

```
Developer pushes code to service repo
        ↓
GitHub Actions: ci.yml
  1. docker build
  2. docker run tests
  3. trivy image scan (fail if CRITICAL CVEs)
  4. grype sbom scan
  5. docker push harbor.local.dev/team/app:sha-abc123
        ↓
GitHub Actions: cd.yml
  6. git checkout (helm values in service repo)
  7. yq .image.tag = "sha-abc123" helm/values.yaml
  8. git push
        ↓
ArgoCD detects Helm values change (polling every 3 min)
  9. helm template → diff
  10. kubectl apply
        ↓
New pod running at https://my-app.local.dev
```
