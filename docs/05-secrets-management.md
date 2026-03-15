# Secrets Management

## Overview

HashiCorp Vault is the secrets management solution. **No secrets in Git. Ever.**

Vault runs in dev mode locally for simplicity, with the root token `dev-root-token`.

## Architecture

```
Developer → vault kv put secret/my-app/config KEY=value
                                │
                                ▼
                         Vault (KV v2 store)
                                │
                         Vault Agent Injector
                         (mutating webhook)
                                │
                    ┌───────────▼───────────┐
                    │  Pod starts           │
                    │  ┌─────────────────┐  │
                    │  │ Vault Agent     │  │  ← injected sidecar
                    │  │ - authenticates │  │
                    │  │ - writes files  │  │
                    │  └─────────────────┘  │
                    │  ┌─────────────────┐  │
                    │  │ App Container   │  │
                    │  │ reads from      │  │
                    │  │ /vault/secrets/ │  │
                    │  └─────────────────┘  │
                    └───────────────────────┘
```

## Initial Setup

After bootstrap, Vault runs in dev mode:

```bash
# Verify Vault is running
kubectl get pods -n vault
vault status

# Enable KV v2 secret engine
vault secrets enable -path=secret kv-v2

# Enable Kubernetes auth
vault auth enable kubernetes
vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
  token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token
```

The bootstrap script handles this automatically.

## Storing a Secret

```bash
# Store a single key-value pair
vault kv put secret/payment-service/config \
  DATABASE_URL="postgres://user:pass@postgres:5432/payments" \
  STRIPE_KEY="sk_test_abcdef123"

# Read it back
vault kv get secret/payment-service/config

# Update one key (preserves others)
vault kv patch secret/payment-service/config \
  STRIPE_KEY="sk_test_newkey"
```

## Injecting Secrets into Pods

The app-template Helm chart includes the necessary annotations:

```yaml
# helm/templates/deployment.yaml
spec:
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "{{ .Values.vault.role }}"
        vault.hashicorp.com/agent-inject-secret-config: "secret/{{ .Values.appName }}/config"
        vault.hashicorp.com/agent-inject-template-config: |
          {{ "{{" }}- with secret "secret/{{ .Values.appName }}/config" -{{ "}}" }}
          {{ "{{" }}- range $k, $v := .Data.data {{ "}}" }}
          export {{ "{{" }} $k {{ "}}" }}="{{ "{{" }} $v {{ "}}" }}"
          {{ "{{" }}- end {{ "}}" }}
          {{ "{{" }}- end {{ "}}" }}
```

At runtime, secrets appear at `/vault/secrets/config`:
```
export DATABASE_URL="postgres://user:pass@postgres:5432/payments"
export STRIPE_KEY="sk_test_abcdef123"
```

The app sources this file or reads values directly.

## Vault Policies

Each service gets a least-privilege policy:

```hcl
# platform/vault/policies/app-policy.hcl (template)
path "secret/data/{{APP_NAME}}/*" {
  capabilities = ["read"]
}

path "secret/metadata/{{APP_NAME}}/*" {
  capabilities = ["list"]
}
```

The seed processor creates a policy for each service:

```bash
vault policy write payment-service - <<EOF
path "secret/data/payment-service/*" {
  capabilities = ["read"]
}
EOF
```

## Vault Kubernetes Auth Roles

Each service has a Vault role binding it to a Kubernetes Service Account:

```bash
vault write auth/kubernetes/role/payment-service \
  bound_service_account_names=payment-service \
  bound_service_account_namespaces=payment-service-dev,payment-service-staging,payment-service-prod \
  policies=payment-service \
  ttl=1h
```

The Kubernetes Service Account is created by the `k8s-namespace` tofu module.

## Dynamic Secrets (Advanced)

Vault can generate short-lived database credentials:

```bash
# Enable database secrets engine
vault secrets enable database

# Configure PostgreSQL connection
vault write database/config/postgres \
  plugin_name=postgresql-database-plugin \
  connection_url="postgresql://{{username}}:{{password}}@postgres:5432/mydb" \
  allowed_roles="my-app-role" \
  username="vault" \
  password="vault-password"

# Create a role that generates credentials
vault write database/roles/my-app-role \
  db_name=postgres \
  creation_statements="CREATE ROLE \"{{name}}\" LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';" \
  default_ttl="1h" \
  max_ttl="24h"
```

Then inject via annotation:
```yaml
vault.hashicorp.com/agent-inject-secret-postgres: "database/creds/my-app-role"
```

## Rotation

For the local dev setup, secrets are long-lived. In a real platform:
1. Use dynamic secrets where possible (databases, cloud credentials)
2. For static secrets, use Vault lease renewal
3. Certificate rotation is handled by cert-manager automatically

Manual rotation:
```bash
vault kv patch secret/payment-service/config STRIPE_KEY="sk_test_newkey"
# Pods pick up the new value on next restart (or via Vault Agent template watch)
```

## Troubleshooting

### Pod not getting secrets

```bash
# Check Vault agent sidecar logs
kubectl logs <pod-name> -n <namespace> -c vault-agent-init
kubectl logs <pod-name> -n <namespace> -c vault-agent

# Common errors:
# "permission denied" → check policy
# "role not found" → check vault role exists
# "service account not bound" → check SA name in role config
```

### Verify Vault is running and unsealed

```bash
kubectl exec -n vault vault-0 -- vault status
# Should show: Initialized: true, Sealed: false
```

### Vault sealed after cluster restart

In dev mode, Vault auto-unseals. But if using a real config:
```bash
kubectl exec -n vault vault-0 -- vault operator unseal <unseal-key>
```
