# ADR-002: ArgoCD for GitOps

**Status**: Accepted
**Date**: 2024-01-01

## Context

We need a continuous delivery tool that:
- Watches a Git repository for changes
- Syncs Kubernetes cluster state to Git state
- Handles Helm charts natively
- Provides visibility into deployment status
- Supports multi-app management

Candidates:
1. **ArgoCD** — pull-based GitOps, CNCF project
2. **Flux** — pull-based GitOps, CNCF project
3. **Jenkins X** — opinionated CI/CD for Kubernetes

## Decision

Use **ArgoCD**.

## Rationale

### ArgoCD over Flux
- **UI**: ArgoCD has an excellent web UI showing app topology and sync status. Flux is CLI-only.
- **App-of-Apps**: ArgoCD's ApplicationSet and App-of-Apps pattern map directly to how platform teams manage multiple services.
- **Visualization**: ArgoCD shows the resource tree (Deployment → ReplicaSet → Pod) visually.
- **Learning value**: ArgoCD UI makes GitOps concepts visible and tangible.

### App-of-Apps pattern
The App-of-Apps pattern is the key design:
1. One root ArgoCD Application watches the platform config directory
2. That directory contains Application manifests for every component
3. ArgoCD bootstraps the entire platform from a single `kubectl apply`

This mirrors how large organizations structure platform management.

## Consequences

- ArgoCD must be installed before any other platform component
- ArgoCD ServiceAccount needs cluster-admin for CRD management
- Applications managed by ArgoCD cannot be changed with kubectl (self-heal reverts them)
- ArgoCD runs continuously and consumes ~500MB RAM

## Self-Heal and Prune

We enable both:
```yaml
syncPolicy:
  automated:
    prune: true      # Remove resources deleted from Git
    selfHeal: true   # Revert manual kubectl changes
```

This is intentional: it forces GitOps discipline. If you want to change something, change Git.
