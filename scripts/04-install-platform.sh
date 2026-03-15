#!/usr/bin/env bash
# 04-install-platform.sh — Apply bootstrap manifests and App-of-Apps

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "→ Applying bootstrap manifests..."

# Apply bootstrap (namespaces, RBAC, priority classes)
kubectl apply -f "${REPO_ROOT}/platform/bootstrap/00-namespaces.yaml"
kubectl apply -f "${REPO_ROOT}/platform/bootstrap/01-priority-classes.yaml"
kubectl apply -f "${REPO_ROOT}/platform/bootstrap/02-rbac.yaml"

echo "→ Propagating TLS certificate to platform namespaces..."
for ns in harbor vault minio nats monitoring ingress-nginx cert-manager; do
    if kubectl get secret local-dev-wildcard-tls -n argocd &>/dev/null; then
        kubectl get secret local-dev-wildcard-tls -n argocd -o yaml \
            | sed "s/namespace: argocd/namespace: ${ns}/" \
            | kubectl apply -f - 2>/dev/null || true
    fi
done

echo "→ Updating App-of-Apps with GitHub org..."
# If GITHUB_ORG is set, update the app-of-apps.yaml
if [[ -n "${GITHUB_ORG:-}" ]]; then
    sed -i "s/YOUR_GITHUB_ORG/${GITHUB_ORG}/g" \
        "${REPO_ROOT}/platform/argocd/apps/app-of-apps.yaml" \
        "${REPO_ROOT}/platform/argocd/apps/platform-apps.yaml" 2>/dev/null || true
fi

echo "→ Applying App-of-Apps..."
kubectl apply -f "${REPO_ROOT}/platform/argocd/apps/app-of-apps.yaml"

echo "→ Waiting for ArgoCD to process App-of-Apps..."
sleep 10

echo "→ Watching ArgoCD applications deploy (this takes 5-10 minutes)..."
echo "   (Ctrl+C to stop watching — installations continue in background)"
echo ""

# Watch until all apps are healthy or timeout
TIMEOUT=600
START_TIME=$(date +%s)

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))

    if [[ ${ELAPSED} -gt ${TIMEOUT} ]]; then
        echo "⚠ Timeout reached. Some apps may still be installing."
        break
    fi

    # Count apps by status
    TOTAL=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l || echo 0)
    HEALTHY=$(kubectl get applications -n argocd --no-headers 2>/dev/null \
        | grep -c "Synced.*Healthy" || echo 0)

    echo "  Apps: ${HEALTHY}/${TOTAL} Synced+Healthy (${ELAPSED}s elapsed)"

    if [[ "${TOTAL}" -ge 5 ]] && [[ "${HEALTHY}" -ge "${TOTAL}" ]]; then
        echo "✓ All applications healthy!"
        break
    fi

    sleep 15
done

echo ""
echo "✓ Platform installation complete!"
echo ""
echo "ArgoCD applications:"
kubectl get applications -n argocd
