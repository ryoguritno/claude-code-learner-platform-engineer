# Getting Started

## Prerequisites

Install these tools before bootstrapping the platform.

### Required

```bash
# Docker (must be running)
docker version

# kubectl
kubectl version --client

# Helm 3
helm version

# k3d (k3s in Docker)
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
# or: brew install k3d

# mkcert (local TLS certificates)
# Linux:
curl -L "https://dl.filippo.io/mkcert/latest?for=linux/amd64" -o /usr/local/bin/mkcert
chmod +x /usr/local/bin/mkcert
# macOS:
# brew install mkcert

# ArgoCD CLI
curl -sSL -o /usr/local/bin/argocd \
  https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

# Vault CLI
# Download from: https://developer.hashicorp.com/vault/downloads
# or: brew install vault

# Python 3.11+
python3 --version

# GitHub CLI (for seed workflow)
# https://cli.github.com/
gh --version
```

### Verify all prerequisites

```bash
./scripts/01-check-prerequisites.sh
```

Expected output:
```
→ Checking prerequisites...
✓ docker: 24.0.0
✓ kubectl: v1.28.0
✓ helm: v3.13.0
✓ k3d: v5.6.0
✓ mkcert: v1.4.4
✓ argocd: v2.9.0
✓ vault: 1.15.0
✓ python3: 3.11.0
✓ gh: 2.40.0
→ All prerequisites satisfied!
```

## System Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 4 cores | 8 cores |
| RAM | 8 GB | 16 GB |
| Disk | 20 GB free | 40 GB free |
| Docker memory limit | 6 GB | 12 GB |

The platform runs ~30 pods. Ensure Docker has enough memory allocated (Docker Desktop → Settings → Resources).

## GitHub Setup

The seed processor uses GitHub API to create repositories. You need:

1. **GitHub account** with ability to create repositories
2. **Personal Access Token (PAT)** with scopes:
   - `repo` (full control of private repositories)
   - `workflow` (update GitHub Action workflows)
   - `admin:org` (if creating repos in an organization)

```bash
# Create PAT at: https://github.com/settings/tokens/new
# Or use GitHub CLI:
gh auth login
gh auth token
```

3. Set up the environment file:
```bash
cp .env.example .env
# Edit .env with your values
```

`.env` contents:
```bash
GITHUB_TOKEN=ghp_your_token_here
GITHUB_ORG=your-username-or-org
ARGOCD_SERVER=argocd.local.dev
HARBOR_URL=harbor.local.dev
VAULT_ADDR=https://vault.local.dev
VAULT_TOKEN=dev-root-token
```

## Bootstrap the Platform

Once prerequisites are installed and `.env` is configured:

```bash
# Full bootstrap (10-15 minutes)
./scripts/bootstrap.sh
```

This runs in order:
1. `01-check-prerequisites.sh` — verifies tools
2. `02-setup-k3d.sh` — creates cluster
3. `03-install-argocd.sh` — installs ArgoCD
4. `04-install-platform.sh` — deploys all components
5. `05-setup-local-dns.sh` — adds /etc/hosts entries

### What happens during bootstrap

**Step 2: k3d cluster creation**
```bash
k3d cluster create local-platform \
  --port "80:80@loadbalancer" \
  --port "443:443@loadbalancer" \
  --agents 2 \
  --k3s-arg "--disable=traefik@server:0"
```
- Creates a 3-node cluster (1 server + 2 agents)
- Maps ports 80/443 from localhost to the k3d LoadBalancer
- Disables k3s's built-in Traefik (we use ingress-nginx)

**Step 3: ArgoCD installation**
```bash
helm install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  -f platform/argocd/install/values.yaml
```
- Installs ArgoCD in the `argocd` namespace
- Waits for all pods to be Running

**Step 4: Platform components**
```bash
kubectl apply -f platform/argocd/apps/app-of-apps.yaml
```
- Applies a single ArgoCD Application
- That Application watches `platform/argocd/apps/platform-apps.yaml`
- ArgoCD then installs: Harbor, Vault, MinIO, NATS, Prometheus, Grafana, Loki, ingress-nginx, cert-manager, Kyverno, OpenFaaS

**Step 5: Local DNS**
```bash
echo "127.0.0.1 argocd.local.dev" >> /etc/hosts
echo "127.0.0.1 harbor.local.dev" >> /etc/hosts
# ... etc
```

## Verify Bootstrap

```bash
# All pods running
kubectl get pods -A

# Platform UIs accessible
curl -sk https://argocd.local.dev | grep -c "Argo CD"
curl -sk https://harbor.local.dev/api/v2.0/health

# ArgoCD apps all healthy
argocd app list
```

## First Login

### ArgoCD
```bash
# Get initial password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo

# Login via CLI
argocd login argocd.local.dev \
  --username admin \
  --password <password-from-above> \
  --insecure

# Or open browser: https://argocd.local.dev
```

### Harbor
```
URL: https://harbor.local.dev
Username: admin
Password: Harbor12345
```

Configure Docker to use Harbor:
```bash
# Add to Docker daemon: insecure registries or trust mkcert CA
docker login harbor.local.dev
```

### Grafana
```
URL: https://grafana.local.dev
Username: admin
Password: prom-operator
```

### Vault
```bash
# Via browser: https://vault.local.dev
# Token: dev-root-token

# Via CLI:
vault login dev-root-token
vault status
```

## Next Steps

Once the platform is running:
1. Read [Developer Guide](02-developer-guide.md) to onboard your first app
2. Explore [Platform Internals](03-platform-internals.md) to understand how it works
3. Browse the ArgoCD UI to see all managed applications
