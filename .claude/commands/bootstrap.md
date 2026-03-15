# /bootstrap — Bootstrap the Full Platform

Run this command to set up the complete local platform from scratch.

## What it does

1. Verifies prerequisites (Docker, kubectl, Helm, k3d, mkcert)
2. Creates a k3d cluster with ingress port mappings
3. Installs ArgoCD and waits for it to be ready
4. Applies the App-of-Apps manifest (all platform components)
5. Waits for all platform components to become healthy
6. Sets up local DNS (/etc/hosts entries)
7. Prints access URLs and credentials

## Usage

```
/bootstrap
```

## Steps to execute

Run the following in order:

```bash
# Step 1: Check all prerequisites
./scripts/01-check-prerequisites.sh

# Step 2: Create k3d cluster
./scripts/02-setup-k3d.sh

# Step 3: Install ArgoCD
./scripts/03-install-argocd.sh

# Step 4: Install all platform components via App-of-Apps
./scripts/04-install-platform.sh

# Step 5: Set up local DNS (requires sudo)
sudo ./scripts/05-setup-local-dns.sh

# Or run everything at once:
./scripts/bootstrap.sh
```

## Verify success

```bash
# All pods should be Running
kubectl get pods -A

# All ingresses should have an ADDRESS
kubectl get ingress -A

# Test ArgoCD
curl -sk https://argocd.local.dev | grep -i argocd

# Check ArgoCD apps
argocd app list
```

## Troubleshooting

If bootstrap fails partway through, most scripts are idempotent — re-run the failed step.

Common issues:
- `k3d cluster create` fails: Docker daemon not running
- ArgoCD pods not ready: wait longer, cluster may be slow
- Ingress has no ADDRESS: ingress-nginx pod may be pending
- TLS errors: mkcert not installed or CA not trusted

See `docs/runbooks/bootstrap-cluster.md` for detailed troubleshooting.
