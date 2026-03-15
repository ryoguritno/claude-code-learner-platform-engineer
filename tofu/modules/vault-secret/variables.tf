variable "app_name" {
  description = "Application name (used for Vault path, policy, and role)"
  type        = string
}

variable "environments" {
  description = "List of environments (determines which namespaces can access the secret)"
  type        = list(string)
  default     = ["dev", "staging", "prod"]
}
