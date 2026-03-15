# Security

## Security Layers

This platform implements defense-in-depth:

1. **Build-time**: Trivy + Grype scan images before they reach the registry
2. **Admission**: Kyverno policies block non-compliant resources
3. **Runtime**: Non-root containers, resource limits, read-only filesystems
4. **Secrets**: Vault injection (no secrets in env vars or Git)
5. **Network**: Ingress-level TLS, per-namespace NetworkPolicies

## Container Scanning

### Trivy (in CI pipeline)

Trivy scans Docker images for CVEs, misconfigurations, and secrets.

The CI pipeline blocks on CRITICAL severity:

```yaml
# .github/workflows/ci.yml
- name: Scan image
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: harbor.local.dev/${{ env.HARBOR_PROJECT }}/${{ env.APP_NAME }}:${{ env.IMAGE_TAG }}
    format: table
    exit-code: 1                      # Fail CI on findings
    severity: CRITICAL                # Block on CRITICAL only
    ignore-unfixed: true              # Skip CVEs with no fix available
```

Run locally:
```bash
# Scan an image
trivy image harbor.local.dev/payments/payment-service:latest

# Scan your Dockerfile for misconfigurations
trivy config Dockerfile

# Scan IaC files
trivy config tofu/

# Generate SBOM
trivy image --format cyclonedx harbor.local.dev/payments/payment-service:latest
```

### Grype (SBOM scanning)

Grype provides a second opinion and SBOM analysis:

```yaml
# .github/workflows/ci.yml
- name: Generate SBOM
  uses: anchore/sbom-action@v0
  with:
    image: harbor.local.dev/${{ env.HARBOR_PROJECT }}/${{ env.APP_NAME }}:${{ env.IMAGE_TAG }}

- name: Scan SBOM
  uses: anchore/scan-action@v3
  with:
    sbom: sbom.spdx.json
    fail-build: true
    severity-cutoff: critical
```

### Harbor built-in scanning

Harbor runs Trivy on every pushed image automatically:
1. Push image to Harbor
2. Harbor triggers Trivy scan
3. Scan results visible in Harbor UI
4. Can configure Harbor to block pulls of vulnerable images

Configure in `platform/harbor/values.yaml`:
```yaml
trivy:
  enabled: true
  ignoreUnfixed: true
  skipUpdate: false
```

## Kyverno Policies

Kyverno is the admission controller. Policies are in `platform/kyverno/policies/`.

### require-labels.yaml

All pods must have standard labels:
```yaml
required labels:
  - app.kubernetes.io/name
  - app.kubernetes.io/version
  - team
```

Why: enables Prometheus metrics labeling, cost allocation, incident routing.

### require-resource-limits.yaml

All containers must have CPU + memory limits:
```yaml
required:
  - resources.limits.cpu
  - resources.limits.memory
  - resources.requests.cpu
  - resources.requests.memory
```

Why: prevents noisy-neighbor problems. Without limits, one bad deployment can OOM the entire node.

### disallow-latest-tag.yaml

Images using `:latest` tag are blocked in `*-staging` and `*-prod` namespaces:
```yaml
deny:
  conditions:
    - key: "{{ image }}"
      operator: Contains
      value: ":latest"
```

Why: `latest` is not reproducible. You can't roll back to a specific version.

### Testing policies

```bash
# Test a policy against a manifest
kyverno test platform/kyverno/policies/

# Dry-run: would this manifest be admitted?
kyverno apply platform/kyverno/policies/require-labels.yaml \
  --resource helm/templates/deployment.yaml

# Check what was blocked recently
kubectl get events -A --field-selector reason=PolicyViolation
```

## Secure Dockerfile Patterns

Every Dockerfile must follow these patterns:

```dockerfile
# ✓ Multi-stage: build deps don't end up in final image
FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# ✓ Distroless: no shell = smaller attack surface
FROM gcr.io/distroless/python3-debian12
WORKDIR /app

# ✓ Copy only what's needed
COPY --from=builder /root/.local /root/.local
COPY src/ /app/src/

# ✓ Non-root user
USER nonroot:nonroot

# ✓ Document the port
EXPOSE 8080

# ✓ No CMD secrets — pass via Vault injection
CMD ["src/main.py"]
```

Anti-patterns (blocked by Kyverno or Trivy):
- `FROM ubuntu:latest` → use pinned version
- `RUN curl ... | bash` → download and verify
- `ENV SECRET_KEY=abc123` → use Vault injection
- Running as root (UID 0)

## Network Policies

Each service namespace gets default-deny NetworkPolicy, then explicit allow rules:

```yaml
# Default deny all ingress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: payment-service-dev
spec:
  podSelector: {}
  policyTypes:
    - Ingress

# Allow from ingress-nginx only
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-nginx
  namespace: payment-service-dev
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: payment-service
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress-nginx
      ports:
        - protocol: TCP
          port: 8080
```

The `k8s-namespace` tofu module creates these NetworkPolicies automatically.

## RBAC

The platform uses minimal RBAC:
- Platform team: cluster-admin (bootstrap only)
- Developers: namespace-scoped `edit` role in their namespaces
- ArgoCD: cluster-admin in `argocd` namespace (required for CRD management)
- CI/CD: namespace-scoped `edit` role (for image tag updates)

```yaml
# Created by tofu/modules/k8s-namespace
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: developer-edit
  namespace: payment-service-dev
roleRef:
  kind: ClusterRole
  name: edit
subjects:
  - kind: Group
    name: payments-team
    apiGroup: rbac.authorization.k8s.io
```

## Security Checklist for New Services

Before promoting to staging:

- [ ] Trivy scan: no CRITICAL CVEs
- [ ] Grype scan: no CRITICAL CVEs
- [ ] Dockerfile: multi-stage, non-root, distroless final image
- [ ] All secrets in Vault (not in env vars or config files)
- [ ] Resource limits set
- [ ] Liveness + readiness probes defined
- [ ] NetworkPolicy created (handled by tofu)
- [ ] No `latest` tag in Helm values for staging/prod
- [ ] Kyverno policies pass: `kyverno apply policies/ --resource manifest.yaml`
