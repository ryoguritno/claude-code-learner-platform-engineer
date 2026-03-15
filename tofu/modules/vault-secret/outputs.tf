output "vault_path" {
  description = "Vault KV path for this application's secrets"
  value       = "secret/${var.app_name}/config"
}

output "policy_name" {
  description = "Vault policy name"
  value       = vault_policy.app.name
}

output "role_name" {
  description = "Vault Kubernetes auth role name"
  value       = vault_kubernetes_auth_backend_role.app.role_name
}
