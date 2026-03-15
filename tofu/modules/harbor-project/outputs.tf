output "project_name" {
  description = "Harbor project name"
  value       = harbor_project.this.name
}

output "robot_account_name" {
  description = "CI robot account name"
  value       = harbor_robot_account.ci.name
}

output "robot_account_secret" {
  description = "CI robot account secret"
  value       = harbor_robot_account.ci.secret
  sensitive   = true
}

output "registry_url" {
  description = "Registry URL for this project"
  value       = "harbor.local.dev/${var.project_name}"
}
