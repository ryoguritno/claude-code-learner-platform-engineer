#!/usr/bin/env bash
# 02-setup-k3d.sh — Create k3d cluster with port mappings

set -euo pipefail

CLUSTER_NAME="${K3D_CLUSTER_NAME:-local-platform}"

echo "→ Setting up k3d cluster: ${CLUSTER_NAME}"

# Check if cluster already exists
if k3d cluster list | grep -q "^${CLUSTER_NAME}"; then
    echo "→ Cluster '${CLUSTER_NAME}' already exists"

    # Check if it's running
    if k3d cluster list | grep "${CLUSTER_NAME}" | grep -q "running"; then
        echo "✓ Cluster is running"
        kubectl config use-context "k3d-${CLUSTER_NAME}"
        kubectl cluster-info
        exit 0
    else
        echo "→ Cluster exists but is stopped, starting it..."
        k3d cluster start "${CLUSTER_NAME}"
        kubectl config use-context "k3d-${CLUSTER_NAME}"
        exit 0
    fi
fi

# Check ports 80 and 443 are available
for port in 80 443; do
    if lsof -i ":${port}" -sTCP:LISTEN &>/dev/null; then
        echo "✗ Port ${port} is in use. Stop the process using it first."
        echo "  Find it with: lsof -i :${port}"
        exit 1
    fi
done

echo "→ Creating k3d cluster (this takes ~30 seconds)..."

k3d cluster create "${CLUSTER_NAME}" \
    --port "80:80@loadbalancer" \
    --port "443:443@loadbalancer" \
    --agents 2 \
    --k3s-arg "--disable=traefik@server:0" \
    --k3s-arg "--disable=servicelb@server:0" \
    --wait

echo "→ Setting kubectl context..."
kubectl config use-context "k3d-${CLUSTER_NAME}"

echo "→ Waiting for cluster nodes to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

echo ""
echo "✓ k3d cluster created successfully!"
echo ""
kubectl get nodes
echo ""
echo "Cluster: k3d-${CLUSTER_NAME}"
echo "Contexts: $(kubectl config current-context)"
