variable "function_name" {
  description = "OpenFaaS function name"
  type        = string
}

variable "image" {
  description = "Container image for the function (from Harbor)"
  type        = string
}

variable "team" {
  description = "Owning team"
  type        = string
}

variable "environment_vars" {
  description = "Environment variables for the function"
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Kubernetes secret names to mount"
  type        = list(string)
  default     = []
}

variable "cpu_request" {
  type    = string
  default = "50m"
}

variable "cpu_limit" {
  type    = string
  default = "200m"
}

variable "memory_request" {
  type    = string
  default = "64Mi"
}

variable "memory_limit" {
  type    = string
  default = "128Mi"
}
