# Runbook: Bootstrap Cluster

**When to use**: First-time setup or after full teardown.
**Time**: ~15 minutes
**Risk**: Low (creates new resources, doesn't delete anything)

## Prerequisites Check

```bash
./scripts/01-check-prerequisites.sh
```

All tools must show ✓. If any fail, install them before proceeding.

## Step 1: Create k3d Cluster

```bash
./scripts/02-setup-k3d.sh

# Manual equivalent:
k3d cluster create local-platform \
  --port "80:80@loadbalancer" \
  --port "443:443@loadbalancer" \
  --agents 2 \
  --k3s-arg "--disable=traefik@server:0"

# Verify:
kubectl get nodes
# Expected: 1 server node + 2 agent nodes, all Ready
```

**Troubleshooting:**
- `Error: port already in use`: something is using port 80 or 443
  - `lsof -i :80` to find what
  - Stop it, then retry
- `Error: container runtime not found`: Docker daemon not running
  - `sudo systemctl start docker` or start Docker Desktop

## Step 2: Install ArgoCD

```bash
./scripts/03-install-argocd.sh

# Manual equivalent:
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
kubectl create namespace argocd
helm install argocd argo/argo-cd \
  --namespace argocd \
  --version 5.51.0 \
  -f platform/argocd/install/values.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=300s
```

**Troubleshooting:**
- Pods stuck in `Pending`: insufficient cluster resources
  - `kubectl describe pod <pod> -n argocd` to see reason
  - Increase Docker memory limit (Docker Desktop → Resources)
- `ImagePullBackOff`: network issue pulling images
  - Check Docker can reach the internet: `docker pull nginx`

## Step 3: Get ArgoCD Password

```bash
# Print the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo

# Login via CLI
argocd login argocd.local.dev \
  --username admin \
  --password <PASSWORD> \
  --insecure

# Change the password (optional)
argocd account update-password
```

## Step 4: Install Platform Components (App-of-Apps)

```bash
./scripts/04-install-platform.sh

# Manual equivalent:
kubectl apply -f platform/bootstrap/00-namespaces.yaml
kubectl apply -f platform/bootstrap/01-priority-classes.yaml
kubectl apply -f platform/bootstrap/02-rbac.yaml
kubectl apply -f platform/argocd/apps/app-of-apps.yaml

# Watch ArgoCD install everything
watch argocd app list
```

Expected ArgoCD apps (all should reach Synced + Healthy):
- harbor
- vault
- minio
- nats
- kube-prometheus-stack
- loki
- ingress-nginx
- cert-manager
- kyverno
- openfaas

This takes 5-10 minutes as images are pulled.

**Troubleshooting:**
- App stuck in `Progressing` > 10 minutes:
  - `kubectl describe pod -n <namespace>` for the stuck pod
  - Common: insufficient memory → increase Docker memory limit
- `OutOfSync` and not self-healing:
  - `argocd app sync <app-name> --force`

## Step 5: Set Up TLS

```bash
# Install mkcert CA (trust it in browser)
mkcert -install

# Generate wildcard cert
mkcert "*.local.dev" local.dev

# Load into cluster
kubectl create namespace cert-manager 2>/dev/null || true
kubectl create secret tls local-dev-wildcard-tls \
  --cert=_wildcard.local.dev+1.pem \
  --key=_wildcard.local.dev+1-key.pem \
  --namespace=cert-manager \
  --dry-run=client -o yaml | kubectl apply -f -
```

## Step 6: Set Up Local DNS

```bash
sudo ./scripts/05-setup-local-dns.sh

# What it adds to /etc/hosts:
127.0.0.1 argocd.local.dev
127.0.0.1 harbor.local.dev
127.0.0.1 grafana.local.dev
127.0.0.1 vault.local.dev
127.0.0.1 minio.local.dev
127.0.0.1 nats.local.dev
```

## Step 7: Verify Everything

```bash
# All pods running
kubectl get pods -A | grep -v Running | grep -v Completed
# Should be empty (no non-Running pods)

# All ArgoCD apps healthy
argocd app list
# All: Synced + Healthy

# Test UIs
curl -sk https://argocd.local.dev | grep -c "Argo"
curl -sk https://harbor.local.dev/api/v2.0/health
curl -sk https://grafana.local.dev/api/health
```

## Final Checklist

- [ ] `kubectl get nodes` shows 3 nodes Ready
- [ ] `argocd app list` shows all apps Synced + Healthy
- [ ] `https://argocd.local.dev` loads in browser
- [ ] `https://harbor.local.dev` loads in browser
- [ ] `docker login harbor.local.dev` succeeds
- [ ] `vault status` shows Sealed: false
