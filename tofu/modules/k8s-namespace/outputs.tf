output "namespace_name" {
  description = "The created namespace name"
  value       = kubernetes_namespace.this.metadata[0].name
}

output "service_account_name" {
  description = "The application service account name"
  value       = kubernetes_service_account.app.metadata[0].name
}
