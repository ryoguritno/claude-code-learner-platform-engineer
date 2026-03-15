# harbor-project module
# Creates a Harbor project and robot account for CI/CD

terraform {
  required_providers {
    harbor = {
      source  = "goharbor/harbor"
      version = "~> 3.10"
    }
  }
}

resource "harbor_project" "this" {
  name                   = var.project_name
  public                 = false
  vulnerability_scanning = true
  enable_content_trust   = false

  # Prevent pulling images with CRITICAL vulnerabilities
  # (commented out for local dev — uncomment for stricter security)
  # prevent_vul = "true"
  # severity    = "critical"
}

# Robot account for CI/CD pipelines
resource "harbor_robot_account" "ci" {
  name        = "${var.project_name}-ci"
  description = "CI/CD robot account for ${var.project_name} — managed by OpenTofu"
  level       = "project"

  permissions {
    kind      = "project"
    namespace = harbor_project.this.name

    access {
      action   = "push"
      resource = "repository"
    }
    access {
      action   = "pull"
      resource = "repository"
    }
    access {
      action   = "create"
      resource = "tag"
    }
    access {
      action   = "delete"
      resource = "tag"
    }
    access {
      action   = "create"
      resource = "artifact"
    }
    access {
      action   = "read"
      resource = "artifact"
    }
    access {
      action   = "read"
      resource = "scan"
    }
    access {
      action   = "create"
      resource = "scan"
    }
  }
}

# Tag retention policy — keep last 10 images per repository
resource "harbor_retention_policy" "this" {
  scope    = harbor_project.this.id
  schedule = "Daily"

  rule {
    n_days_since_last_pull = null
    most_recently_pulled   = null
    most_recently_pushed   = 10
    repo_matching          = "**"
    tag_matching           = "**"
    untagged_artifacts     = true
  }
}
