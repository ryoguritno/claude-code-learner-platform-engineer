#!/usr/bin/env bash
# 01-check-prerequisites.sh — Verify all required tools are installed

set -euo pipefail

PASS=0
FAIL=0

check() {
    local name="$1"
    local cmd="$2"
    local min_version="${3:-}"

    if command -v "${cmd}" &>/dev/null; then
        version=$(${cmd} version 2>/dev/null || ${cmd} --version 2>/dev/null || echo "unknown" | head -1)
        echo "✓ ${name}: $(echo "${version}" | head -1 | tr -d '\n')"
        PASS=$((PASS + 1))
    else
        echo "✗ ${name}: NOT FOUND"
        FAIL=$((FAIL + 1))
    fi
}

check_docker() {
    if command -v docker &>/dev/null; then
        if docker info &>/dev/null; then
            version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
            echo "✓ docker: ${version} (daemon running)"
            PASS=$((PASS + 1))
        else
            echo "✗ docker: installed but daemon NOT running — start Docker first"
            FAIL=$((FAIL + 1))
        fi
    else
        echo "✗ docker: NOT FOUND"
        FAIL=$((FAIL + 1))
    fi
}

check_memory() {
    local available_gb
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS: check Docker Desktop memory limit
        available_gb=$(docker info --format '{{.MemTotal}}' 2>/dev/null | awk '{print int($1/1024/1024/1024)}')
    else
        available_gb=$(free -g 2>/dev/null | awk '/^Mem:/{print $7}' || echo "unknown")
    fi

    if [[ "${available_gb}" != "unknown" ]] && [[ "${available_gb}" -ge 6 ]]; then
        echo "✓ memory: ${available_gb}GB available (minimum 6GB)"
        PASS=$((PASS + 1))
    elif [[ "${available_gb}" != "unknown" ]]; then
        echo "⚠ memory: ${available_gb}GB available — recommend 8GB, platform may be slow"
        PASS=$((PASS + 1))
    fi
}

echo "→ Checking prerequisites..."
echo ""

check_docker
check "kubectl"  "kubectl"
check "helm"     "helm"
check "k3d"      "k3d"
check "mkcert"   "mkcert"
check "argocd"   "argocd"
check "vault"    "vault"
check "python3"  "python3"
check "gh"       "gh"
check_memory

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
echo ""

if [[ "${FAIL}" -gt 0 ]]; then
    echo "✗ Prerequisites check FAILED. Install missing tools before bootstrapping."
    echo ""
    echo "Install guides:"
    echo "  k3d:    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash"
    echo "  mkcert: https://github.com/FiloSottile/mkcert (brew install mkcert)"
    echo "  argocd: https://argo-cd.readthedocs.io/en/stable/cli_installation/"
    echo "  vault:  https://developer.hashicorp.com/vault/downloads"
    echo "  gh:     https://cli.github.com/"
    exit 1
fi

echo "✓ All prerequisites satisfied!"
