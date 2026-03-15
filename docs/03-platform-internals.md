# Platform Internals

## How the Seed Processor Works

The seed processor is the heart of the platform. It's a Python script run by GitHub Actions.

### File: `seeds/processor/main.py`

Entry point. Reads changed seed files from the git diff and processes each one.

```python
# Simplified flow:
for seed_file in changed_files:
    seed = parse_and_validate(seed_file)
    create_github_repo(seed)
    create_argocd_applications(seed)
    run_tofu_for_infra(seed)
```

### File: `seeds/processor/templates.py`

Generates the repository structure by copying `app-template/` and substituting variables:
- `{{APP_NAME}}` → seed.spec.name
- `{{TEAM}}` → seed.spec.team
- `{{LANGUAGE}}` → seed.spec.language

### File: `seeds/processor/argocd.py`

Generates ArgoCD Application manifests and applies them to the cluster:

```yaml
# Generated for each environment
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: payment-service-dev
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/org/payment-service
    path: helm
    targetRevision: main
    helm:
      valueFiles:
        - values.yaml
        - values-dev.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: payment-service-dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## How ArgoCD App-of-Apps Works

The App-of-Apps pattern is the mechanism by which ArgoCD manages platform components.

### Bootstrap sequence

1. `kubectl apply -f platform/argocd/apps/app-of-apps.yaml`

2. This creates a single ArgoCD Application called `platform-apps` that watches `platform/argocd/apps/platform-apps.yaml`

3. `platform-apps.yaml` contains ArgoCD Application manifests for every platform component

4. ArgoCD sees those Application manifests → installs each component

### Why this matters

Without App-of-Apps: you'd run `helm install` for each component manually.
With App-of-Apps: `git push` to update a values file → ArgoCD reconciles.

**The cluster is always in the state described by Git.**

## How Ingress and TLS Work

### ingress-nginx

ingress-nginx runs as a DaemonSet on all nodes. k3d exposes ports 80/443 from the container network to localhost via Docker port bindings.

When you create an Ingress resource:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: payment-service
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  tls:
    - hosts:
        - payment-service.local.dev
      secretName: local-dev-tls
  rules:
    - host: payment-service.local.dev
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: payment-service
                port:
                  number: 8080
```

ingress-nginx reads this → routes `payment-service.local.dev` → Service `payment-service:8080`.

### cert-manager + mkcert

mkcert creates a local Certificate Authority (CA) trusted by your browser:
```bash
mkcert -install          # Installs CA into system trust store
mkcert "*.local.dev"    # Issues wildcard cert
```

The wildcard cert is loaded into a Kubernetes Secret:
```bash
kubectl create secret tls local-dev-wildcard-tls \
  --cert=_wildcard.local.dev.pem \
  --key=_wildcard.local.dev-key.pem \
  -n cert-manager
```

All Ingress resources reference this secret → browsers trust the TLS.

## How Vault Injection Works

Vault uses a sidecar model. When a pod starts:

1. Pod has Vault annotations:
```yaml
annotations:
  vault.hashicorp.com/agent-inject: "true"
  vault.hashicorp.com/role: "payment-service"
  vault.hashicorp.com/agent-inject-secret-config: "secret/payment-service/config"
```

2. Vault's mutating webhook (installed with Vault Agent Injector) intercepts the pod creation

3. A Vault agent sidecar is injected alongside the app container

4. The sidecar authenticates to Vault using Kubernetes Service Account JWT

5. The sidecar writes secrets to `/vault/secrets/` as files

6. The app container reads secrets from `/vault/secrets/config`

**The app never connects to Vault directly.** The sidecar handles auth and renewal.

### Vault auth configuration

The seed processor sets up a Vault role for each service:
```bash
vault write auth/kubernetes/role/payment-service \
  bound_service_account_names=payment-service \
  bound_service_account_namespaces=payment-service-dev,payment-service-staging,payment-service-prod \
  policies=payment-service-policy \
  ttl=1h
```

And a policy:
```hcl
path "secret/data/payment-service/*" {
  capabilities = ["read"]
}
```

## How Kyverno Policies Work

Kyverno is a Kubernetes-native policy engine. It operates as an admission webhook.

### Policy types in this platform

**require-labels.yaml** — Every pod must have standard labels:
```yaml
required: [app.kubernetes.io/name, app.kubernetes.io/version, team]
```

**require-resource-limits.yaml** — Every container must have resource limits:
```yaml
required: resources.limits.cpu, resources.limits.memory
```

**disallow-latest-tag.yaml** — `image:latest` is blocked in non-dev namespaces.

### What happens when a policy fails

```
kubectl apply -f deployment.yaml
Error from server: admission webhook "validate.kyverno.svc" denied the request:
  resource Deployment/payment-service-prod/payment-service was blocked due to the
  following policies: disallow-latest-tag: autogen-validate-image-tag
```

Policies are the platform team's way of enforcing standards without relying on developer discipline.

## How Prometheus Scraping Works

Prometheus uses `ServiceMonitor` and `PodMonitor` resources (from kube-prometheus-stack):

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: payment-service
  namespace: payment-service-dev
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: payment-service
  endpoints:
    - port: http
      path: /metrics
      interval: 30s
```

Prometheus discovers this → scrapes `/metrics` from payment-service pods every 30 seconds.

The app-template includes a `/metrics` endpoint powered by `prometheus-fastapi-instrumentator`.

## How NATS JetStream Works

NATS JetStream provides durable messaging. For the platform:

- **Stream** = named collection of subjects (like an SQS queue or Kafka topic)
- **Subject** = specific message channel (like `payment.completed`)
- **Consumer** = subscriber that reads from a stream (durable, with ack semantics)

The seed processor creates a stream via the NATS management API:
```python
js = nc.jetstream()
await js.add_stream(name="PAYMENT_EVENTS", subjects=["payment.*"])
```

Apps publish:
```python
await js.publish("payment.completed", b'{"payment_id": "123"}')
```

Apps subscribe:
```python
sub = await js.subscribe("payment.completed", durable="payment-processor")
async for msg in sub.messages:
    # process
    await msg.ack()
```

## How MinIO (S3) Works

MinIO implements the S3 API 100% compatibly. Apps use any S3 SDK:

```python
import boto3
s3 = boto3.client(
    "s3",
    endpoint_url="http://minio.minio.svc.cluster.local:9000",
    aws_access_key_id="admin",
    aws_secret_access_key="minio-secret-key",  # from Vault
)
s3.put_object(Bucket="payment-service-receipts", Key="receipt-123.pdf", Body=pdf_bytes)
```

The seed processor creates buckets via MinIO's admin API or the `minio-bucket` tofu module.

## OpenTofu Module Architecture

Each tofu module provisions one logical resource:

```
tofu/modules/k8s-namespace/
  ├── main.tf       # Creates Namespace + ResourceQuota + LimitRange
  ├── variables.tf  # Inputs: name, cpu_limit, memory_limit, team
  └── outputs.tf    # Outputs: namespace_name

tofu/modules/minio-bucket/
  ├── main.tf       # Creates MinIO bucket via minio provider
  ├── variables.tf  # Inputs: bucket_name, versioning, lifecycle_days
  └── outputs.tf    # Outputs: bucket_name, bucket_arn (compatible)
```

The seed processor calls tofu programmatically:
```python
import subprocess
subprocess.run([
    "tofu", "apply", "-auto-approve",
    f"-var=app_name={seed.name}",
    f"-var=team={seed.team}",
    "tofu/environments/dev"
], check=True)
```

## Component Interaction Map

```
GitHub (seed YAML)
    │
    ▼
GH Actions (seed-processor.yml)
    │
    ├──► GitHub API → create service repo
    │
    ├──► kubectl apply → ArgoCD Application manifests
    │         │
    │         ▼
    │     ArgoCD → sync service helm chart
    │              → deploys pods
    │              → creates Ingress
    │
    └──► tofu apply
              │
              ├──► k8s-namespace → Namespace + RBAC
              ├──► minio-bucket → MinIO bucket
              ├──► nats-subject → NATS stream
              └──► vault-secret → Vault role + policy

Service repo (CI)
    │
    ▼
GH Actions (ci.yml)
    │
    ├──► docker build
    ├──► pytest
    ├──► trivy scan (block if CRITICAL)
    └──► docker push → Harbor

GH Actions (cd.yml)
    │
    └──► yq update image.tag → git push

ArgoCD (polling every 3 min)
    │
    └──► detect helm/values.yaml change → sync → new pod running
```
