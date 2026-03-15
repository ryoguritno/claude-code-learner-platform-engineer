# ADR-004: HashiCorp Vault for Secrets Management

**Status**: Accepted
**Date**: 2024-01-01

## Context

We need a secrets management solution that:
- Keeps secrets out of Git and environment variables
- Injects secrets into pods at runtime
- Supports dynamic credentials (database passwords, etc.)
- Has Kubernetes-native integration
- Maps to AWS Secrets Manager behavior

Candidates:
1. **HashiCorp Vault** — industry standard, rich features
2. **Kubernetes Secrets** — native, but base64 encoded (not encrypted by default)
3. **Sealed Secrets** — Kubernetes Secrets encrypted with asymmetric key
4. **External Secrets Operator** — syncs from external stores (Vault, AWS SM, etc.)

## Decision

Use **HashiCorp Vault** with the Vault Agent Injector.

## Rationale

### Vault over Kubernetes Secrets
- Kubernetes Secrets are stored in etcd, base64 encoded — not encrypted at rest by default
- Vault provides encryption, audit logging, dynamic credentials, and fine-grained policies

### Vault over Sealed Secrets
- Sealed Secrets are still static — you can't generate dynamic database credentials
- Vault's Kubernetes auth is more flexible than sealed secrets' trust model

### Vault Agent Injector pattern
The agent injection pattern is the right balance of:
- Transparency: app code doesn't need Vault SDK
- Security: secrets never touch environment variables
- Simplicity: just add annotations to your pod spec

## Consequences

- Vault must be unsealed after every cluster restart (in production mode)
- For this local platform, we run Vault in **dev mode** (`-dev-root-token-id=dev-root-token`)
- Dev mode: no persistence, auto-unsealed, root token is `dev-root-token`
- **Do not use dev mode in any real environment**

## Dev Mode vs Production Mode

| Feature | Dev Mode (this platform) | Production Mode |
|---------|--------------------------|-----------------|
| Auto-unseal | Yes | No |
| Persistence | No (in-memory) | Yes (PV) |
| TLS | Self-signed | Proper cert |
| Root token | `dev-root-token` | Generated on init |
| Audit logs | No | Required |

## Migration Path to Production

If this platform were moved to production:
1. Remove `-dev` flag from Vault Helm values
2. Configure persistent storage
3. Use auto-unseal (AWS KMS, Azure Key Vault, etc.)
4. Rotate all secrets
5. Enable audit logging
