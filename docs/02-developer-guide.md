# Developer Guide — Using the Seeds Workflow

## Overview

The Seeds workflow lets you onboard a new service without touching Kubernetes. You write a YAML file, push it, and the platform creates everything.

## The Seed Spec

A seed is a YAML file in `seeds/apps/` that describes your service:

```yaml
apiVersion: platform.local.dev/v1
kind: SeedApplication
metadata:
  name: payment-service
  labels:
    team: payments
    environment: dev
spec:
  name: payment-service
  team: payments
  language: python
  description: "Handles payment processing and webhook callbacks"

  repository:
    organization: my-github-org
    visibility: private
    branch_protection: true

  infrastructure:
    namespace: payment-service
    environments:
      - dev
      - staging
      - prod

  resources:
    requests:
      cpu: "200m"
      memory: "256Mi"
    limits:
      cpu: "1000m"
      memory: "512Mi"

  scaling:
    min_replicas: 2
    max_replicas: 10
    target_cpu_utilization: 70

  storage:
    enabled: true
    bucket_name: payment-service-receipts

  messaging:
    enabled: true
    stream_name: PAYMENT_EVENTS
    subjects:
      - payment.initiated
      - payment.completed
      - payment.failed

  secrets:
    enabled: true
    vault_path: secret/payment-service/config
```

## End-to-End Walkthrough

### Step 1: Create your seed file

```bash
cp seeds/apps/example-app.yaml seeds/apps/payment-service.yaml
vim seeds/apps/payment-service.yaml
```

Validate it before pushing:
```bash
python3 -c "
import json, yaml, jsonschema
schema = json.load(open('seeds/schema/seed.schema.json'))
seed = yaml.safe_load(open('seeds/apps/payment-service.yaml'))
jsonschema.validate(seed, schema)
print('Valid!')
"
```

### Step 2: Push and open PR

```bash
git checkout -b feat/add-payment-service
git add seeds/apps/payment-service.yaml
git commit -m "feat: add payment-service seed"
git push origin feat/add-payment-service
gh pr create --title "feat: add payment-service" --body "Onboarding payment service to the platform"
```

### Step 3: Seed processor runs (on PR merge)

GitHub Actions workflow `seed-processor.yml` runs:

1. **Validate** — checks YAML against `seeds/schema/seed.schema.json`
2. **Create repo** — creates `my-github-org/payment-service` from `app-template`
3. **ArgoCD app** — creates `payment-service-dev`, `payment-service-staging`, `payment-service-prod` Applications
4. **Tofu** — provisions namespace, ResourceQuota, MinIO bucket, NATS stream, Vault path

You'll see this in the GH Actions log:
```
→ Creating GitHub repo: my-github-org/payment-service
✓ Repository created: https://github.com/my-github-org/payment-service
→ Creating ArgoCD applications...
✓ payment-service-dev created
✓ payment-service-staging created
✓ payment-service-prod created
→ Running tofu for infrastructure...
✓ Namespace payment-service-dev created
✓ MinIO bucket payment-service-receipts created
✓ NATS stream PAYMENT_EVENTS created
✓ Vault path secret/payment-service/config initialized
```

### Step 4: Add your secrets

The processor creates the Vault path but puts no values in it. Add them:

```bash
vault login dev-root-token
vault kv put secret/payment-service/config \
  DATABASE_URL="postgres://user:pass@postgres:5432/payments" \
  STRIPE_SECRET_KEY="sk_test_..." \
  WEBHOOK_SECRET="whsec_..."
```

### Step 5: Clone and develop

```bash
git clone https://github.com/my-github-org/payment-service
cd payment-service

# The repo comes with:
# - src/main.py (FastAPI hello world)
# - Dockerfile (multi-stage, non-root)
# - helm/ (full Helm chart with HPA, PDB)
# - .github/workflows/ci.yml (build → test → scan → push)
# - .github/workflows/cd.yml (update image tag)
```

Develop your app. The `src/main.py` is a FastAPI template — replace it with your logic.

### Step 6: Push code

```bash
git add .
git commit -m "feat: implement payment processing endpoint"
git push origin main
```

GitHub Actions CI runs:
1. `docker build` — builds the image
2. `pytest` — runs tests
3. `trivy image scan` — blocks if CRITICAL CVEs found
4. `docker push harbor.local.dev/payments/payment-service:sha-abc123`

Then CD runs:
5. Updates `helm/values.yaml` → `image.tag: sha-abc123`
6. Pushes the values change

### Step 7: ArgoCD deploys

ArgoCD detects the Helm values change and syncs:

```
ArgoCD: payment-service-dev OutOfSync
ArgoCD: Syncing...
ArgoCD: payment-service-dev Healthy ✓
```

Your app is live at `https://payment-service.local.dev` (dev environment).

## Checking Your App

```bash
# Pod status
kubectl get pods -n payment-service-dev

# Logs
kubectl logs -n payment-service-dev -l app.kubernetes.io/name=payment-service -f

# Access
curl https://payment-service.local.dev/health

# Check secrets are injected
kubectl exec -n payment-service-dev deployment/payment-service \
  -- cat /vault/secrets/config
```

## Updating Your App

The typical update cycle:

```bash
# Make code changes
vim src/main.py

# Push
git add . && git commit -m "fix: handle refund edge case" && git push

# CI/CD pipeline runs automatically
# ArgoCD syncs within ~3 minutes
# Or force immediate sync:
argocd app sync payment-service-dev
```

## Promote to Staging

The CD workflow updates Helm values in the service repo. To promote to staging, the ArgoCD Application for staging watches a different values file or branch. By default:
- `dev` → watches `main` branch, auto-sync enabled
- `staging` → watches `main` branch, manual sync required
- `prod` → watches `release/*` branches, manual sync required

```bash
# Promote to staging
argocd app sync payment-service-staging

# Promote to prod (after creating release branch)
git checkout -b release/1.0.0
git push origin release/1.0.0
argocd app sync payment-service-prod
```

## Seed Spec Reference

### Required fields

| Field | Type | Description |
|-------|------|-------------|
| `spec.name` | string | Service name (lowercase, hyphens) |
| `spec.team` | string | Owning team name |
| `spec.language` | string | python / go / nodejs / java |
| `spec.repository.organization` | string | GitHub org or username |
| `spec.infrastructure.namespace` | string | Base namespace name |
| `spec.infrastructure.environments` | list | List of environments |
| `spec.resources` | object | CPU/memory requests and limits |

### Optional fields

| Field | Default | Description |
|-------|---------|-------------|
| `spec.storage.enabled` | false | Create MinIO bucket |
| `spec.messaging.enabled` | false | Create NATS stream |
| `spec.secrets.enabled` | true | Create Vault path |
| `spec.scaling.min_replicas` | 1 | HPA minimum |
| `spec.scaling.max_replicas` | 5 | HPA maximum |
| `spec.scaling.target_cpu_utilization` | 70 | HPA target % |
