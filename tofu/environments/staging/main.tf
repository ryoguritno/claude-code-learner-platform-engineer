# Staging environment infrastructure
# Same as dev but with stricter resource limits

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

variable "app_name" {
  type = string
}

variable "team" {
  type = string
}

variable "environment" {
  type    = string
  default = "staging"
}

variable "vault_token" {
  type      = string
  default   = "dev-root-token"
  sensitive = true
}

variable "minio_password" {
  type      = string
  default   = "minio-secret-key"
  sensitive = true
}

variable "harbor_password" {
  type      = string
  default   = "Harbor12345"
  sensitive = true
}

variable "storage_bucket_name" {
  type    = string
  default = ""
}

variable "nats_stream_name" {
  type    = string
  default = ""
}

variable "nats_subjects" {
  type    = string
  default = ""
}

variable "nats_server" {
  type    = string
  default = "nats://localhost:4222"
}

module "namespace" {
  source = "../../modules/k8s-namespace"

  name                 = "${var.app_name}-staging"
  app_name             = var.app_name
  team                 = var.team
  environment          = "staging"
  cpu_request_limit    = "4"
  memory_request_limit = "4Gi"
  cpu_limit            = "8"
  memory_limit         = "8Gi"
  max_pods             = "30"
}

module "vault" {
  source = "../../modules/vault-secret"

  app_name     = var.app_name
  environments = ["dev", "staging"]
}

# Harbor project is team-scoped — created once by the dev environment, not repeated here

module "storage" {
  count  = var.storage_bucket_name != "" ? 1 : 0
  source = "../../modules/minio-bucket"

  bucket_name = "${var.storage_bucket_name}-staging"
  app_name    = "${var.app_name}-staging"
  versioning  = true  # Enable versioning in staging
}

module "messaging" {
  count  = var.nats_stream_name != "" ? 1 : 0
  source = "../../modules/nats-subject"

  stream_name = "${var.nats_stream_name}_STAGING"
  app_name    = var.app_name
  subjects    = var.nats_subjects != "" ? split(",", var.nats_subjects) : []
}
