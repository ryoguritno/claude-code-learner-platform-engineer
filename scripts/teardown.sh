#!/usr/bin/env bash
# teardown.sh — Remove the k3d cluster and all local state
# WARNING: This is destructive. All cluster data will be lost.

set -euo pipefail

CLUSTER_NAME="${K3D_CLUSTER_NAME:-local-platform}"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           LOCAL PLATFORM ENGINEER — TEARDOWN                ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "⚠  WARNING: This will delete:"
echo "   - k3d cluster '${CLUSTER_NAME}' and ALL data"
echo "   - /etc/hosts entries for *.local.dev"
echo "   - Local TLS certificates"
echo ""

# Confirmation prompt
if [[ "${FORCE:-false}" != "true" ]]; then
    read -p "Are you sure? Type 'yes' to confirm: " confirm
    if [[ "${confirm}" != "yes" ]]; then
        echo "Teardown cancelled."
        exit 0
    fi
fi

echo "→ Deleting k3d cluster '${CLUSTER_NAME}'..."
if k3d cluster list | grep -q "^${CLUSTER_NAME}"; then
    k3d cluster delete "${CLUSTER_NAME}"
    echo "✓ Cluster deleted"
else
    echo "  Cluster '${CLUSTER_NAME}' not found — skipping"
fi

echo "→ Removing /etc/hosts entries..."
if grep -q "# BEGIN local-platform-engineer" /etc/hosts 2>/dev/null; then
    sudo sed -i "/# BEGIN local-platform-engineer/,/# END local-platform-engineer/d" /etc/hosts
    echo "✓ /etc/hosts entries removed"
else
    echo "  No /etc/hosts entries found — skipping"
fi

echo "→ Cleaning up local TLS certs..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
rm -f "${REPO_ROOT}"/_wildcard.local.dev*.pem
echo "✓ TLS certs removed"

echo "→ Cleaning up tofu state..."
for env_dir in "${REPO_ROOT}"/tofu/environments/*/; do
    rm -f "${env_dir}/terraform.tfstate" "${env_dir}/terraform.tfstate.backup"
    rm -rf "${env_dir}/.terraform"
done
echo "✓ Tofu state removed"

echo ""
echo "✓ Teardown complete!"
echo ""
echo "Your seed YAML files in seeds/apps/ are preserved."
echo "To rebuild the platform, run: ./scripts/bootstrap.sh"
