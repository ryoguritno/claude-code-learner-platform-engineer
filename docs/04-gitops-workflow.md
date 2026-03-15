# GitOps Workflow

## Principles

1. **Git is the source of truth** — if it's not in Git, it doesn't exist
2. **No manual kubectl apply** for managed resources — change Git, let ArgoCD reconcile
3. **Drift detection** — ArgoCD continuously reconciles; manual changes get reverted
4. **Declarative** — describe desired state, not steps to get there

## ArgoCD Concepts

### Application

An ArgoCD Application links a Git path to a cluster namespace:

```yaml
source:
  repoURL: https://github.com/org/platform
  path: platform/monitoring/grafana    # Helm chart or manifests
  targetRevision: main                  # Git branch/tag/SHA
destination:
  namespace: monitoring                  # Where to deploy
syncPolicy:
  automated:
    prune: true      # Delete resources removed from Git
    selfHeal: true   # Revert manual changes
```

### App-of-Apps

The root Application (`platform-apps`) watches `platform/argocd/apps/platform-apps.yaml`, which contains Application resources for every component.

```
platform-apps (root)
 └── watches: platform/argocd/apps/platform-apps.yaml
      ├── Application: harbor → platform/harbor/values.yaml
      ├── Application: vault → platform/vault/values.yaml
      ├── Application: prometheus → platform/monitoring/prometheus/values.yaml
      └── ... (10 more)
```

Adding a new platform component = adding one Application to `platform-apps.yaml` + commit.

### Sync policies

| Policy | Dev apps | Platform components |
|--------|---------|-------------------|
| Auto-sync | Yes | Yes |
| Self-heal | Yes | Yes |
| Prune | Yes | Yes |
| Manual gate | No | No |

For production service apps, consider manual sync:
```yaml
syncPolicy:
  # No 'automated' block = manual sync required
```

## Workflow: Updating a Platform Component

Example: updating Grafana from 10.0.0 to 10.2.0.

```bash
# 1. Edit the Helm values
vim platform/monitoring/grafana/values.yaml
# Change: grafana.image.tag: "10.2.0"

# 2. Commit and push
git add platform/monitoring/grafana/values.yaml
git commit -m "chore: bump grafana to 10.2.0"
git push origin main

# 3. ArgoCD detects the change (within 3 minutes)
# or force sync:
argocd app sync grafana

# 4. Watch the rollout
kubectl rollout status deployment/grafana -n monitoring
```

## Workflow: Deploying an App Update

```bash
# 1. Developer pushes code to service repo
git push origin main

# 2. CI builds and pushes image
# harbor.local.dev/payments/payment-service:sha-abc123

# 3. CD updates Helm values
# helm/values.yaml: image.tag: sha-abc123

# 4. ArgoCD detects change
argocd app sync payment-service-dev

# 5. Verify
kubectl rollout status deployment/payment-service -n payment-service-dev
```

## Workflow: Rolling Back

```bash
# Option 1: Revert the Git commit
git revert HEAD
git push origin main
# ArgoCD auto-syncs to previous state

# Option 2: ArgoCD UI rollback
# Applications → payment-service-dev → History → select previous version → Rollback

# Option 3: ArgoCD CLI rollback
argocd app history payment-service-dev
argocd app rollback payment-service-dev <revision-id>
```

## Helm in ArgoCD

ArgoCD supports Helm natively. The service Helm chart lives in the service repo:

```
payment-service/
└── helm/
    ├── Chart.yaml
    ├── values.yaml         # Base defaults
    ├── values-dev.yaml     # Dev overrides
    ├── values-staging.yaml # Staging overrides
    └── values-prod.yaml    # Prod overrides
```

ArgoCD applies both `values.yaml` and `values-{env}.yaml`:

```yaml
source:
  helm:
    valueFiles:
      - values.yaml
      - values-dev.yaml
```

Environment-specific overrides (replicas, resource limits, feature flags) go in `values-{env}.yaml`.

## Observing Sync Status

```bash
# List all apps
argocd app list

# Detailed status
argocd app get payment-service-dev

# Watch real-time
watch argocd app list

# Diff: what would change if synced?
argocd app diff payment-service-dev
```

Status meanings:
- `Synced` + `Healthy` = all good
- `OutOfSync` = Git has changes not yet applied
- `Progressing` = deployment in progress
- `Degraded` = pods not healthy
- `Missing` = resource doesn't exist in cluster

## Application Projects

ArgoCD Projects provide multi-tenancy and RBAC. Platform convention:
- `default` project — platform components (admin only)
- `apps` project — developer applications (team-scoped)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: apps
  namespace: argocd
spec:
  sourceRepos:
    - 'https://github.com/my-org/*'
  destinations:
    - namespace: '*-dev'
      server: https://kubernetes.default.svc
    - namespace: '*-staging'
      server: https://kubernetes.default.svc
  # prod requires separate approval
```

## Preventing Drift

ArgoCD self-heal mode means any `kubectl apply` or `kubectl edit` on a managed resource gets reverted within seconds.

To make a manual change that sticks:
1. Edit the value in Git
2. Push
3. ArgoCD syncs
4. Change is permanent

There is no step 0 involving `kubectl`.
