# ADR-001: k3d over minikube

**Status**: Accepted
**Date**: 2024-01-01

## Context

We need a local Kubernetes environment that:
- Runs inside Docker (no separate VM required)
- Supports multi-node clusters (to simulate real workloads)
- Works with ingress-nginx without special configuration
- Is fast to create and destroy

Candidates evaluated:
1. **minikube** — most popular, many addons, VM or Docker driver
2. **kind** — Kubernetes IN Docker, single binary
3. **k3d** — k3s in Docker

## Decision

Use **k3d** (k3s running in Docker containers).

## Rationale

### k3d advantages over minikube
- **Faster startup**: k3d cluster creates in ~30 seconds vs 2-3 minutes for minikube
- **Docker-native**: no separate hypervisor, just Docker containers
- **Multi-node**: trivial to add agent nodes (`--agents 2`)
- **Real ingress**: port binding to LoadBalancer works identically to cloud
- **k3s footprint**: k3s is a minimal Kubernetes — less resource usage than full k8s

### k3d advantages over kind
- **Port binding**: k3d has built-in LoadBalancer (via k3s ServiceLB) + simple port mapping
- **Ingress**: `--port "443:443@loadbalancer"` just works
- **k3s base**: same as production k3s deployments (Rancher ecosystem)

### Minikube advantage we give up
- Addons (dashboard, metrics-server, etc.) — we provision these via Helm anyway
- VM isolation — not needed for learning

## Consequences

- Platform requires Docker daemon running
- k3s runs on Alpine base, minor differences from Ubuntu-based EKS AMIs (irrelevant for learning)
- All scripts use k3d CLI; switching to minikube would require script changes
- k3d cluster name is `local-platform` — hardcoded in scripts

## k3d Configuration

```bash
k3d cluster create local-platform \
  --port "80:80@loadbalancer" \
  --port "443:443@loadbalancer" \
  --agents 2 \
  --k3s-arg "--disable=traefik@server:0"
```

We disable Traefik (k3s default ingress) because we use ingress-nginx.
