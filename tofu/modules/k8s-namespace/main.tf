# k8s-namespace module
# Creates: Namespace + ResourceQuota + LimitRange + NetworkPolicies + RBAC

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

resource "kubernetes_namespace" "this" {
  metadata {
    name = var.name
    labels = {
      "app.kubernetes.io/managed-by" = "opentofu"
      "team"                         = var.team
      "environment"                  = var.environment
    }
  }
}

resource "kubernetes_resource_quota" "this" {
  metadata {
    name      = "resource-quota"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  spec {
    hard = {
      "requests.cpu"    = var.cpu_request_limit
      "requests.memory" = var.memory_request_limit
      "limits.cpu"      = var.cpu_limit
      "limits.memory"   = var.memory_limit
      "pods"            = var.max_pods
    }
  }
}

resource "kubernetes_limit_range" "this" {
  metadata {
    name      = "limit-range"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  spec {
    limit {
      type = "Container"
      default = {
        cpu    = "200m"
        memory = "128Mi"
      }
      default_request = {
        cpu    = "100m"
        memory = "64Mi"
      }
      max = {
        cpu    = var.cpu_limit
        memory = var.memory_limit
      }
    }
  }
}

# Service account for the application
resource "kubernetes_service_account" "app" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace.this.metadata[0].name
    labels = {
      "app.kubernetes.io/name"       = var.app_name
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }
}

# Developer access to their namespace
resource "kubernetes_role_binding" "developer" {
  metadata {
    name      = "developer-edit"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "edit"
  }
  subject {
    kind      = "Group"
    name      = var.team
    api_group = "rbac.authorization.k8s.io"
  }
}

# Default deny all ingress network policy
resource "kubernetes_network_policy" "default_deny_ingress" {
  metadata {
    name      = "default-deny-ingress"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
  }
}

# Allow ingress from ingress-nginx
resource "kubernetes_network_policy" "allow_from_ingress" {
  metadata {
    name      = "allow-from-ingress-nginx"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = var.app_name
      }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "ingress-nginx"
          }
        }
      }
    }
  }
}

# Allow egress to cluster DNS and services
resource "kubernetes_network_policy" "allow_dns_egress" {
  metadata {
    name      = "allow-dns-egress"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Egress"]
    egress {
      ports {
        port     = "53"
        protocol = "UDP"
      }
      ports {
        port     = "53"
        protocol = "TCP"
      }
    }
    # Allow all egress within cluster (simplification for local dev)
    egress {
      to {
        ip_block {
          cidr = "10.0.0.0/8"
        }
      }
    }
  }
}
