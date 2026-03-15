#!/usr/bin/env bash
# 06-process-seed.sh — Run the seed processor locally (no GitHub Actions needed)
#
# Usage:
#   ./scripts/06-process-seed.sh seeds/apps/my-app.yaml
#
# Prerequisites:
#   - kubectl context pointing at local-platform
#   - GITHUB_TOKEN env var set (PAT with repo + workflow permissions)
#   - Platform running (bootstrap.sh completed)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SEED_FILE="${1:-}"
if [[ -z "${SEED_FILE}" ]]; then
    echo "Usage: $0 <seed-file>"
    echo "Example: $0 seeds/apps/my-app.yaml"
    exit 1
fi

# Resolve to absolute path
SEED_FILE="$(cd "$(dirname "${SEED_FILE}")" && pwd)/$(basename "${SEED_FILE}")"

if [[ ! -f "${SEED_FILE}" ]]; then
    echo "✗ Seed file not found: ${SEED_FILE}"
    exit 1
fi

# Check GITHUB_TOKEN
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "✗ GITHUB_TOKEN is not set"
    echo "  Create a PAT at https://github.com/settings/tokens"
    echo "  Scopes needed: repo, workflow"
    echo "  Then: export GITHUB_TOKEN=ghp_..."
    exit 1
fi

# Defaults for local platform
export VAULT_ADDR="${VAULT_ADDR:-https://vault.local.dev}"
export VAULT_TOKEN="${VAULT_TOKEN:-dev-root-token}"

# Port-forward NATS so terraform JetStream provider can reach it
NATS_PF_PID=""
if kubectl get svc nats -n nats &>/dev/null; then
    echo "→ Port-forwarding NATS to localhost:4222..."
    kubectl port-forward svc/nats 4222:4222 -n nats &>/dev/null &
    NATS_PF_PID=$!
    sleep 2  # Give port-forward time to establish
fi

cleanup() {
    if [[ -n "${NATS_PF_PID}" ]]; then
        kill "${NATS_PF_PID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

echo "→ Processing seed: ${SEED_FILE}"
echo "  Vault:  ${VAULT_ADDR}"
echo "  GitHub: using GITHUB_TOKEN"
echo ""

cd "${REPO_ROOT}/seeds/processor"

# Use a venv to avoid system-package conflicts (PEP 668)
VENV_DIR="${REPO_ROOT}/.venv-seed-processor"
if [[ ! -d "${VENV_DIR}" ]]; then
    echo "→ Creating Python virtual environment..."
    python3 -m venv "${VENV_DIR}"
fi

# Install deps if needed
if ! "${VENV_DIR}/bin/python3" -c "import yaml, jsonschema, github" 2>/dev/null; then
    echo "→ Installing Python dependencies..."
    "${VENV_DIR}/bin/pip" install --quiet pyyaml jsonschema PyGithub
fi

"${VENV_DIR}/bin/python3" main.py "${SEED_FILE}"

echo ""
echo "✓ Seed processed. Check ArgoCD: https://argocd.local.dev"
echo "  kubectl get applications -n argocd"
