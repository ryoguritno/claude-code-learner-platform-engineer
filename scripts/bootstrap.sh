#!/usr/bin/env bash
# bootstrap.sh — Bootstrap the entire local platform
# Runs all setup scripts in order.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           LOCAL PLATFORM ENGINEER — BOOTSTRAP               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "→ Repository root: ${REPO_ROOT}"
echo ""

# Load environment if .env exists
if [[ -f "${REPO_ROOT}/.env" ]]; then
    echo "→ Loading .env..."
    set -a
    source "${REPO_ROOT}/.env"
    set +a
fi

# Step 1: Check prerequisites
echo "════════════════════════════════════════════════════════════════"
echo " Step 1/5: Checking prerequisites"
echo "════════════════════════════════════════════════════════════════"
"${SCRIPT_DIR}/01-check-prerequisites.sh"

# Step 2: Create k3d cluster
echo ""
echo "════════════════════════════════════════════════════════════════"
echo " Step 2/5: Setting up k3d cluster"
echo "════════════════════════════════════════════════════════════════"
"${SCRIPT_DIR}/02-setup-k3d.sh"

# Step 3: Install ArgoCD
echo ""
echo "════════════════════════════════════════════════════════════════"
echo " Step 3/5: Installing ArgoCD"
echo "════════════════════════════════════════════════════════════════"
"${SCRIPT_DIR}/03-install-argocd.sh"

# Step 4: Install platform components
echo ""
echo "════════════════════════════════════════════════════════════════"
echo " Step 4/5: Installing platform components (App-of-Apps)"
echo "════════════════════════════════════════════════════════════════"
"${SCRIPT_DIR}/04-install-platform.sh"

# Step 5: Set up local DNS
echo ""
echo "════════════════════════════════════════════════════════════════"
echo " Step 5/5: Setting up local DNS"
echo "════════════════════════════════════════════════════════════════"
if [[ "${SKIP_DNS:-false}" == "true" ]]; then
    echo "→ Skipping DNS setup (SKIP_DNS=true)"
else
    echo "→ This requires sudo for /etc/hosts modification"
    sudo "${SCRIPT_DIR}/05-setup-local-dns.sh"
fi

# Print summary
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    BOOTSTRAP COMPLETE!                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Platform UIs:"
echo "  ArgoCD:  https://argocd.local.dev"
echo "  Harbor:  https://harbor.local.dev"
echo "  Grafana: https://grafana.local.dev"
echo "  Vault:   https://vault.local.dev"
echo "  MinIO:   https://minio.local.dev"
echo ""
echo "ArgoCD admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d; echo
echo ""
echo "Onboard your first app:"
echo "  cp seeds/apps/example-app.yaml seeds/apps/my-app.yaml"
echo "  vim seeds/apps/my-app.yaml"
echo "  git add seeds/apps/my-app.yaml && git push"
