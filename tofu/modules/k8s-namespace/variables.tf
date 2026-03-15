variable "name" {
  description = "Namespace name (e.g., payment-service-dev)"
  type        = string
}

variable "app_name" {
  description = "Application name (used for service account and NetworkPolicy)"
  type        = string
}

variable "team" {
  description = "Team name (used for RBAC group binding)"
  type        = string
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "cpu_request_limit" {
  description = "Total CPU requests allowed in namespace"
  type        = string
  default     = "2"
}

variable "memory_request_limit" {
  description = "Total memory requests allowed in namespace"
  type        = string
  default     = "2Gi"
}

variable "cpu_limit" {
  description = "Total CPU limits allowed in namespace"
  type        = string
  default     = "4"
}

variable "memory_limit" {
  description = "Total memory limits allowed in namespace"
  type        = string
  default     = "4Gi"
}

variable "max_pods" {
  description = "Maximum number of pods in namespace"
  type        = string
  default     = "20"
}
