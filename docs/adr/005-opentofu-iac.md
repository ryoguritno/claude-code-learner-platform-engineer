# ADR-005: OpenTofu for Infrastructure as Code

**Status**: Accepted
**Date**: 2024-01-01

## Context

We need an IaC tool to provision:
- Kubernetes namespaces with RBAC + ResourceQuota
- MinIO buckets
- NATS streams
- Vault roles + policies
- Harbor projects + robot accounts

Candidates:
1. **OpenTofu** — open-source Terraform fork, HCL syntax
2. **Terraform** — HashiCorp, BSL license since 1.6.0
3. **Pulumi** — multi-language (Python/Go/TypeScript), real programming language
4. **Crossplane** — Kubernetes-native IaC via CRDs
5. **Ansible** — procedural, not declarative

## Decision

Use **OpenTofu** (with `terraform` binary as fallback since HCL is identical).

## Rationale

### OpenTofu over Terraform
- OpenTofu is the CNCF-backed open-source fork of Terraform
- Identical HCL syntax — all Terraform knowledge transfers
- No license concerns for learning or commercial use
- Active development, community-driven

### OpenTofu over Pulumi
- HCL is simpler for infrastructure-specific tasks
- Better learning value: HCL is ubiquitous in platform engineering roles
- The learning goal is platform engineering patterns, not programming language mastery

### OpenTofu over Crossplane
- Crossplane is powerful but complex to bootstrap (needs its own providers installed)
- For local development, tofu is simpler and faster to iterate
- Crossplane is the right choice for platform teams managing large multi-cloud environments

## Module Architecture

Each module provisions one logical resource with a clean interface:

```
tofu/modules/k8s-namespace/
  ├── main.tf       # Resources
  ├── variables.tf  # Input parameters
  └── outputs.tf    # Return values

# Usage in tofu/environments/dev/main.tf:
module "payment_service_ns" {
  source      = "../../modules/k8s-namespace"
  name        = "payment-service-dev"
  team        = "payments"
  cpu_limit   = "4"
  memory_limit = "8Gi"
}
```

## Consequences

- State is stored locally in `tofu/environments/*/terraform.tfstate`
- State is gitignored (contains sensitive outputs)
- For this learning project, local state is fine
- For production: use remote state (S3/MinIO + DynamoDB/MinIO lock)

## Using Terraform Binary

If `tofu` is not installed, the identical `terraform` binary works:
```bash
alias tofu=terraform
```

Both interpret the same HCL files.
