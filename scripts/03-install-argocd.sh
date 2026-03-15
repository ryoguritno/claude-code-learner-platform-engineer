#!/usr/bin/env bash
# 03-install-argocd.sh — Install ArgoCD via Helm

set -euo pipefail

ARGOCD_VERSION="${ARGOCD_CHART_VERSION:-5.51.0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "→ Installing ArgoCD ${ARGOCD_VERSION}..."

# Add Helm repo
helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm repo update argo

# Create namespace
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Install / upgrade ArgoCD
helm upgrade --install argocd argo/argo-cd \
    --namespace argocd \
    --version "${ARGOCD_VERSION}" \
    -f "${REPO_ROOT}/platform/argocd/install/values.yaml" \
    --wait \
    --timeout 10m

echo "→ Waiting for ArgoCD server to be ready..."
kubectl wait --for=condition=available deployment/argocd-server \
    --namespace argocd \
    --timeout=300s

# Set up TLS cert for ArgoCD ingress
echo "→ Setting up mkcert TLS certificate..."
if ! command -v mkcert &>/dev/null; then
    echo "⚠ mkcert not found — skipping TLS setup"
else
    mkcert -install 2>/dev/null || true

    # Generate wildcard cert if not already present
    if [[ ! -f "${REPO_ROOT}/_wildcard.local.dev+1.pem" ]]; then
        cd "${REPO_ROOT}"
        mkcert "*.local.dev" local.dev
    fi

    # Load into cluster
    kubectl create secret tls local-dev-wildcard-tls \
        --cert="${REPO_ROOT}/_wildcard.local.dev+1.pem" \
        --key="${REPO_ROOT}/_wildcard.local.dev+1-key.pem" \
        --namespace=argocd \
        --dry-run=client -o yaml | kubectl apply -f -

    echo "✓ TLS certificate loaded"
fi

# Get initial admin password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d 2>/dev/null || echo "")

echo ""
echo "✓ ArgoCD installed successfully!"
echo ""
echo "  URL:      https://argocd.local.dev  (after DNS setup)"
echo "  Username: admin"
echo "  Password: ${ARGOCD_PASSWORD}"
echo ""
echo "  Or port-forward: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Then: https://localhost:8080"
