# Runbook: Onboard a New Application

**When to use**: Adding a new service to the platform.
**Time**: ~5 minutes (automated), ~30 minutes (if setting up manually)
**Risk**: Low (creates new resources, doesn't affect existing ones)

## Automated Path (Recommended)

### Step 1: Create seed YAML

```bash
cp seeds/apps/example-app.yaml seeds/apps/MY-APP.yaml
vim seeds/apps/MY-APP.yaml
```

Required fields to update:
- `metadata.name` → your app name
- `spec.name` → same
- `spec.team` → your team
- `spec.language` → python / go / nodejs / java
- `spec.description` → one-line description
- `spec.repository.organization` → your GitHub org/username
- `spec.infrastructure.namespace` → your app name (becomes namespace prefix)

### Step 2: Validate

```bash
python3 -c "
import json, yaml, jsonschema
schema = json.load(open('seeds/schema/seed.schema.json'))
seed = yaml.safe_load(open('seeds/apps/MY-APP.yaml'))
jsonschema.validate(seed, schema)
print('Valid!')
"
```

### Step 3: Push

```bash
git checkout -b feat/add-MY-APP
git add seeds/apps/MY-APP.yaml
git commit -m "feat: add MY-APP to platform"
git push origin feat/add-MY-APP
gh pr create --title "feat: add MY-APP" --fill
```

Merge the PR. GitHub Actions `seed-processor.yml` runs automatically.

### Step 4: Monitor

```bash
# Watch GH Actions
gh run watch

# After completion, verify:
kubectl get ns MY-APP-dev MY-APP-staging MY-APP-prod
argocd app list | grep MY-APP
```

## Manual Path (If GH Actions Not Configured)

### Create GitHub repo

```bash
gh repo create YOUR-ORG/MY-APP --private --template YOUR-ORG/app-template
git clone https://github.com/YOUR-ORG/MY-APP
```

### Create namespaces via tofu

```bash
cd tofu/environments/dev
tofu apply -var="app_name=MY-APP" -var="team=my-team" -auto-approve
```

### Create ArgoCD Application

```bash
cat > /tmp/MY-APP-argocd.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: MY-APP-dev
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/YOUR-ORG/MY-APP
    path: helm
    targetRevision: main
    helm:
      valueFiles:
        - values.yaml
        - values-dev.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: MY-APP-dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

kubectl apply -f /tmp/MY-APP-argocd.yaml
```

### Create Vault path

```bash
vault kv put secret/MY-APP/config \
  PLACEHOLDER="replace-with-real-secrets"

vault policy write MY-APP - <<EOF
path "secret/data/MY-APP/*" {
  capabilities = ["read"]
}
EOF

vault write auth/kubernetes/role/MY-APP \
  bound_service_account_names=MY-APP \
  bound_service_account_namespaces=MY-APP-dev,MY-APP-staging,MY-APP-prod \
  policies=MY-APP \
  ttl=1h
```

## Post-Onboarding

### Add secrets

```bash
vault kv put secret/MY-APP/config \
  DATABASE_URL="postgres://..." \
  API_KEY="..."
```

### Configure Harbor project

```bash
# Create Harbor project via API
curl -sk -u admin:Harbor12345 \
  -X POST https://harbor.local.dev/api/v2.0/projects \
  -H "Content-Type: application/json" \
  -d '{"project_name": "MY-TEAM", "public": false}'
```

### Set up developer access

```bash
# Add team members to the namespace
kubectl create rolebinding MY-APP-developers \
  --clusterrole=edit \
  --group=MY-TEAM \
  --namespace=MY-APP-dev
```

## Verification Checklist

- [ ] `kubectl get ns MY-APP-dev` exists
- [ ] `argocd app get MY-APP-dev` shows Synced + Healthy
- [ ] `vault kv get secret/MY-APP/config` returns values
- [ ] `kubectl get pods -n MY-APP-dev` shows running pods
- [ ] `curl https://MY-APP.local.dev/health` returns 200
- [ ] Logs appear in Grafana → Explore → Loki
- [ ] Metrics appear in Grafana → Explore → Prometheus
