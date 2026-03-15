# Development environment infrastructure

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.23"
    }
    minio = {
      source  = "aminueza/minio"
      version = "~> 2.0"
    }
    harbor = {
      source  = "goharbor/harbor"
      version = "~> 3.10"
    }
    jetstream = {
      source  = "nats-io/jetstream"
      version = "~> 0.0.35"
    }
  }
}

# Provider configurations
provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "vault" {
  address         = "https://vault.local.dev"
  token           = var.vault_token
  skip_tls_verify = true
}

provider "minio" {
  minio_server   = "minio.local.dev"
  minio_user     = "admin"
  minio_password = var.minio_password
  minio_ssl      = true
  minio_insecure = true
}

provider "harbor" {
  url      = "https://harbor.local.dev"
  username = "admin"
  password = var.harbor_password
  insecure = true
}

provider "jetstream" {
  servers = var.nats_server
}

# Variables passed from seed processor
variable "app_name" {
  description = "Application name"
  type        = string
}

variable "team" {
  description = "Team name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "vault_token" {
  description = "Vault root token"
  type        = string
  default     = "dev-root-token"
  sensitive   = true
}

variable "minio_password" {
  description = "MinIO admin password"
  type        = string
  default     = "minio-secret-key"
  sensitive   = true
}

variable "harbor_password" {
  description = "Harbor admin password"
  type        = string
  default     = "Harbor12345"
  sensitive   = true
}

variable "storage_bucket_name" {
  description = "MinIO bucket name (empty = no bucket)"
  type        = string
  default     = ""
}

variable "nats_stream_name" {
  description = "NATS stream name (empty = no stream)"
  type        = string
  default     = ""
}

variable "nats_subjects" {
  description = "Comma-separated NATS subjects"
  type        = string
  default     = ""
}

variable "nats_server" {
  description = "NATS server URL (use localhost:4222 with kubectl port-forward for local dev)"
  type        = string
  default     = "nats://localhost:4222"
}

# Create Kubernetes namespace
module "namespace" {
  source = "../../modules/k8s-namespace"

  name        = "${var.app_name}-dev"
  app_name    = var.app_name
  team        = var.team
  environment = "dev"
}

# Create Vault secret path + policy + role
module "vault" {
  source = "../../modules/vault-secret"

  app_name     = var.app_name
  environments = ["dev"]
}

# Create Harbor project for the team (idempotent)
module "harbor" {
  source = "../../modules/harbor-project"

  project_name = var.team
}

# Conditionally create MinIO bucket
module "storage" {
  count  = var.storage_bucket_name != "" ? 1 : 0
  source = "../../modules/minio-bucket"

  bucket_name = var.storage_bucket_name
  app_name    = var.app_name
}

# Conditionally create NATS stream
module "messaging" {
  count  = var.nats_stream_name != "" ? 1 : 0
  source = "../../modules/nats-subject"

  stream_name = var.nats_stream_name
  app_name    = var.app_name
  subjects    = var.nats_subjects != "" ? split(",", var.nats_subjects) : []
}
