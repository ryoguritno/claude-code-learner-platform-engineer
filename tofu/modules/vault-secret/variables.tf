variable "app_name" {
  description = "Application name (used for Vault path, policy, and role)"
  type        = string
}

variable "environments" {
  description = "List of environments (determines which namespaces can access the secret)"
  type        = list(string)
  default     = ["dev", "staging", "prod"]
}

variable "enable_k8s_auth" {
  description = "Create Vault Kubernetes auth role (requires auth/kubernetes to be enabled in Vault)"
  type        = bool
  default     = false
}
