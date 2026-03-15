# ADR-003: Harbor as Container Registry

**Status**: Accepted
**Date**: 2024-01-01

## Context

We need a local container registry that:
- Is a drop-in replacement for AWS ECR
- Supports push/pull via Docker CLI
- Has vulnerability scanning built-in
- Supports multi-project isolation (like ECR repositories per team)
- Has a web UI

Candidates:
1. **Harbor** — CNCF graduated, full-featured enterprise registry
2. **Distribution (docker/distribution)** — basic, no UI or scanning
3. **Nexus Repository** — broader artifact management, complex
4. **Gitea Container Registry** — built into Gitea, limited features

## Decision

Use **Harbor**.

## Rationale

- **ECR equivalent**: Harbor projects ≈ ECR repositories, robot accounts ≈ ECR access policies
- **Scanning**: Built-in Trivy integration mirrors AWS ECR's scanning feature
- **RBAC**: Per-project access control mirrors ECR's resource policies
- **Replication**: Harbor can replicate to/from other registries (useful for pull-through cache)
- **OCI support**: Stores Helm charts alongside container images

### Harbor concepts mapping to AWS

| Harbor | AWS ECR |
|--------|---------|
| Project | Repository prefix / namespace |
| Robot Account | IAM User + access key |
| Webhook | ECR pull-through cache / scan notifications |
| Tag retention | ECR lifecycle policies |
| Trivy scan | ECR enhanced scanning |

## Consequences

- Harbor requires more resources than a basic registry (~1GB RAM)
- Default admin password `Harbor12345` is hardcoded in `platform/harbor/values.yaml` — change for any non-local deployment
- Harbor uses its own TLS cert — we use the mkcert wildcard cert
- Docker daemon must be configured to trust Harbor's self-signed cert OR use the mkcert CA

## Docker configuration for Harbor

```bash
# Option 1: Trust mkcert CA system-wide (preferred)
mkcert -install

# Option 2: Configure Docker insecure registry (not recommended)
# Add to /etc/docker/daemon.json:
# { "insecure-registries": ["harbor.local.dev"] }
```
