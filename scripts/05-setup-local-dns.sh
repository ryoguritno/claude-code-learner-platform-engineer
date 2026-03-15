#!/usr/bin/env bash
# 05-setup-local-dns.sh — Add /etc/hosts entries for *.local.dev
# Requires: sudo (modifies /etc/hosts)

set -euo pipefail

HOSTS_FILE="/etc/hosts"
MARKER_START="# BEGIN local-platform-engineer"
MARKER_END="# END local-platform-engineer"

HOSTS=(
    "argocd.local.dev"
    "harbor.local.dev"
    "grafana.local.dev"
    "vault.local.dev"
    "minio.local.dev"
    "minio-console.local.dev"
    "nats.local.dev"
    "openfaas.local.dev"
    "prometheus.local.dev"
)

echo "→ Setting up local DNS entries..."
echo "  Hosts to configure:"
for host in "${HOSTS[@]}"; do
    echo "    127.0.0.1 ${host}"
done
echo ""

# Remove existing managed entries
if grep -q "${MARKER_START}" "${HOSTS_FILE}" 2>/dev/null; then
    echo "→ Removing existing entries..."
    # Remove lines between markers (inclusive)
    sed -i "/${MARKER_START}/,/${MARKER_END}/d" "${HOSTS_FILE}"
fi

# Append new entries
echo "" >> "${HOSTS_FILE}"
echo "${MARKER_START}" >> "${HOSTS_FILE}"
for host in "${HOSTS[@]}"; do
    echo "127.0.0.1 ${host}" >> "${HOSTS_FILE}"
done
echo "${MARKER_END}" >> "${HOSTS_FILE}"

echo "✓ /etc/hosts updated"
echo ""

# Verify DNS resolution
echo "→ Verifying DNS resolution..."
for host in "${HOSTS[@]}"; do
    if getent hosts "${host}" &>/dev/null || \
       host "${host}" 2>/dev/null | grep -q "has address"; then
        echo "  ✓ ${host} resolves"
    else
        echo "  ⚠ ${host} — DNS may need cache flush"
    fi
done

echo ""
echo "→ If DNS doesn't resolve immediately, try:"
echo "  macOS:  sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder"
echo "  Linux:  sudo systemd-resolve --flush-caches"
echo "  Or simply wait a few seconds."
echo ""
echo "✓ Local DNS setup complete!"
