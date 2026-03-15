# /new-app — Scaffold a New Seed YAML

Use this command to create a new seed spec for onboarding an application to the platform.

## What it does

Guides you through creating a `seeds/apps/<app-name>.yaml` file with all required fields populated.

## Usage

```
/new-app
```

## Steps

### 1. Gather information

Ask the user for:
- **App name** (lowercase, hyphens only, e.g., `payment-service`)
- **Team name** (e.g., `payments`)
- **Language/runtime** (python, go, nodejs, java)
- **Needs object storage?** (MinIO bucket) y/n
- **Needs messaging?** (NATS stream) y/n
- **Needs secrets?** (Vault path) y/n
- **Expected traffic pattern** (low/medium/high — affects HPA settings)

### 2. Create the seed file

Create `seeds/apps/<app-name>.yaml`:

```yaml
apiVersion: platform.local.dev/v1
kind: SeedApplication
metadata:
  name: <app-name>
  labels:
    team: <team-name>
    environment: dev
spec:
  name: <app-name>
  team: <team-name>
  language: <language>
  description: "<one-line description>"

  repository:
    organization: YOUR_GITHUB_ORG
    visibility: private
    branch_protection: true

  infrastructure:
    namespace: <app-name>
    environments:
      - dev
      - staging
      - prod

  resources:
    requests:
      cpu: "100m"
      memory: "128Mi"
    limits:
      cpu: "500m"
      memory: "256Mi"

  scaling:
    min_replicas: 1
    max_replicas: 5
    target_cpu_utilization: 70

  # Optional: only if requested
  storage:
    enabled: <true/false>
    bucket_name: <app-name>-data

  messaging:
    enabled: <true/false>
    stream_name: <APP_NAME>_EVENTS
    subjects:
      - <app-name>.created
      - <app-name>.updated

  secrets:
    enabled: true
    vault_path: secret/<app-name>/config
```

### 3. Validate the seed

```bash
python -c "
import json, yaml, jsonschema
with open('seeds/schema/seed.schema.json') as f:
    schema = json.load(f)
with open('seeds/apps/<app-name>.yaml') as f:
    seed = yaml.safe_load(f)
jsonschema.validate(seed, schema)
print('Seed is valid!')
"
```

### 4. Push it

```bash
git add seeds/apps/<app-name>.yaml
git commit -m "feat: add <app-name> seed"
git push origin main
```

GitHub Actions will pick it up within seconds.

### 5. Verify

```bash
# Check GH Actions is running
gh run list --limit 5

# After completion, check ArgoCD
argocd app list | grep <app-name>

# Check namespace was created
kubectl get ns <app-name>-dev
```
