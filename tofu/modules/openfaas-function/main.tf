# openfaas-function module
# Deploys a serverless function to OpenFaaS

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

# OpenFaaS Function CRD
resource "kubernetes_manifest" "function" {
  manifest = {
    apiVersion = "openfaas.com/v1"
    kind       = "Function"
    metadata = {
      name      = var.function_name
      namespace = "openfaas-fn"
      labels = {
        "app.kubernetes.io/name"       = var.function_name
        "app.kubernetes.io/managed-by" = "opentofu"
        team                           = var.team
      }
    }
    spec = {
      name   = var.function_name
      image  = var.image
      labels = {
        "faas_function" = var.function_name
      }
      environment    = var.environment_vars
      secrets        = var.secrets
      limits = {
        cpu    = var.cpu_limit
        memory = var.memory_limit
      }
      requests = {
        cpu    = var.cpu_request
        memory = var.memory_request
      }
      readOnlyRootFilesystem = true
    }
  }
}
