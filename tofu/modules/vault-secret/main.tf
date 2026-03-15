# vault-secret module
# Creates a Vault KV path, policy, and Kubernetes auth role for an app

terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.23"
    }
  }
}

# Create placeholder secret at the configured path
resource "vault_kv_secret_v2" "placeholder" {
  mount = "secret"
  name  = "${var.app_name}/config"

  data_json = jsonencode({
    PLACEHOLDER = "replace-with-real-value-for-${var.app_name}"
  })

  lifecycle {
    # Don't overwrite if someone has already set real values
    ignore_changes = [data_json]
  }
}

# Create a least-privilege policy
resource "vault_policy" "app" {
  name   = var.app_name
  policy = <<-EOT
    path "secret/data/${var.app_name}/*" {
      capabilities = ["read"]
    }
    path "secret/metadata/${var.app_name}/*" {
      capabilities = ["list", "read"]
    }
  EOT
}

# Create Kubernetes auth role
resource "vault_kubernetes_auth_backend_role" "app" {
  backend                          = "kubernetes"
  role_name                        = var.app_name
  bound_service_account_names      = [var.app_name]
  bound_service_account_namespaces = [
    for env in var.environments : "${var.app_name}-${env}"
  ]
  token_policies = [vault_policy.app.name]
  token_ttl      = 3600  # 1 hour
}
