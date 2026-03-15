# /status — Check Platform Component Status

Run this command to get a comprehensive health check of all platform components.

## Usage

```
/status
```

## Steps to execute

### 1. Cluster health

```bash
echo "=== Cluster Nodes ==="
kubectl get nodes

echo "=== All Pods (non-Running) ==="
kubectl get pods -A | grep -v Running | grep -v Completed

echo "=== Resource Usage ==="
kubectl top nodes 2>/dev/null || echo "metrics-server not available"
```

### 2. Platform components

```bash
echo "=== ArgoCD Applications ==="
argocd app list 2>/dev/null || kubectl get applications -n argocd

echo "=== Ingresses ==="
kubectl get ingress -A

echo "=== Certificates ==="
kubectl get certificates -A

echo "=== Harbor (registry) ==="
curl -sk https://harbor.local.dev/api/v2.0/health | python3 -m json.tool

echo "=== Vault ==="
kubectl exec -n vault vault-0 -- vault status 2>/dev/null

echo "=== MinIO ==="
kubectl get pods -n minio

echo "=== NATS ==="
kubectl get pods -n nats

echo "=== Prometheus ==="
kubectl get pods -n monitoring | grep prometheus

echo "=== Grafana ==="
kubectl get pods -n monitoring | grep grafana

echo "=== Loki ==="
kubectl get pods -n monitoring | grep loki
```

### 3. Application namespaces

```bash
echo "=== App Namespaces ==="
kubectl get ns | grep -v kube | grep -v default | grep -v argocd

echo "=== Running Apps ==="
kubectl get pods -A | grep -v "argocd\|harbor\|vault\|minio\|nats\|monitoring\|cert-manager\|ingress\|kyverno\|openfaas\|kube"
```

### 4. Recent events (errors only)

```bash
echo "=== Warning Events ==="
kubectl get events -A --field-selector type=Warning --sort-by='.lastTimestamp' | tail -20
```

## Expected healthy state

All platform components should be:
- ArgoCD: `Synced` + `Healthy`
- All pods: `Running` or `Completed`
- All certificates: `True` (READY column)
- Vault: `Initialized: true`, `Sealed: false`
- Harbor: `{"status":"healthy"}`

## Quick fixes

```bash
# Force ArgoCD to re-sync everything
argocd app sync platform-apps --force

# Unseal Vault after cluster restart
kubectl exec vault-0 -n vault -- vault operator unseal

# Restart a stuck pod
kubectl rollout restart deployment/<name> -n <namespace>
```
