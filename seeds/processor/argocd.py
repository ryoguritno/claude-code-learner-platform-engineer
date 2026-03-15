"""
argocd.py — Generates and applies ArgoCD Application manifests.

Creates one Application per environment defined in the seed spec.
"""

import logging
import os
import subprocess
import tempfile
from pathlib import Path

import yaml

logger = logging.getLogger(__name__)

REPO_ROOT = Path(__file__).parent.parent.parent


def _generate_application_manifest(
    seed: dict,
    environment: str,
) -> dict:
    """
    Generate an ArgoCD Application manifest for the given seed and environment.
    """
    spec = seed["spec"]
    app_name = spec["name"]
    org = spec["repository"]["organization"]
    namespace = f"{spec['infrastructure']['namespace']}-{environment}"

    # Auto-sync only for dev; staging/prod require manual sync
    auto_sync = environment == "dev"

    manifest = {
        "apiVersion": "argoproj.io/v1alpha1",
        "kind": "Application",
        "metadata": {
            "name": f"{app_name}-{environment}",
            "namespace": "argocd",
            "labels": {
                "app.kubernetes.io/name": app_name,
                "team": spec["team"],
                "environment": environment,
                "managed-by": "seed-processor",
            },
            "annotations": {
                "platform.local.dev/seed-name": app_name,
                "platform.local.dev/team": spec["team"],
            },
            "finalizers": ["resources-finalizer.argocd.argoproj.io"],
        },
        "spec": {
            "project": "apps",
            "source": {
                "repoURL": f"https://github.com/{org}/{app_name}",
                "path": "helm",
                "targetRevision": "main" if environment in ("dev", "staging") else "HEAD",
                "helm": {
                    "valueFiles": [
                        "values.yaml",
                        f"values-{environment}.yaml",
                    ],
                    "parameters": [
                        {
                            "name": "appName",
                            "value": app_name,
                        },
                        {
                            "name": "environment",
                            "value": environment,
                        },
                        {
                            "name": "vault.role",
                            "value": app_name,
                        },
                    ],
                },
            },
            "destination": {
                "server": "https://kubernetes.default.svc",
                "namespace": namespace,
            },
            "syncPolicy": {
                "automated": {
                    "prune": True,
                    "selfHeal": True,
                } if auto_sync else None,
                "syncOptions": [
                    "CreateNamespace=true",
                    "PruneLast=true",
                    "RespectIgnoreDifferences=true",
                ],
                "retry": {
                    "limit": 3,
                    "backoff": {
                        "duration": "5s",
                        "factor": 2,
                        "maxDuration": "3m",
                    },
                },
            },
            "revisionHistoryLimit": 10,
        },
    }

    # Remove automated sync for non-dev environments
    if not auto_sync:
        del manifest["spec"]["syncPolicy"]["automated"]

    return manifest


def apply_manifest(manifest: dict) -> None:
    """Apply a manifest to the cluster using kubectl."""
    manifest_yaml = yaml.dump(manifest, default_flow_style=False)

    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".yaml", delete=False
    ) as f:
        f.write(manifest_yaml)
        tmpfile = f.name

    try:
        result = subprocess.run(
            ["kubectl", "apply", "-f", tmpfile],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            logger.error("kubectl apply failed:\n%s", result.stderr)
            raise RuntimeError(f"kubectl apply failed: {result.stderr}")
        logger.info("Applied: %s", result.stdout.strip())
    finally:
        Path(tmpfile).unlink(missing_ok=True)


def create_argocd_applications(seed: dict) -> None:
    """
    Create ArgoCD Applications for all environments in the seed spec.
    """
    spec = seed["spec"]
    app_name = spec["name"]
    environments = spec["infrastructure"]["environments"]

    # Ensure apps project exists
    _ensure_apps_project()

    for env in environments:
        manifest = _generate_application_manifest(seed, env)
        logger.info(
            "Creating ArgoCD Application: %s-%s",
            app_name,
            env,
        )
        apply_manifest(manifest)
        logger.info("ArgoCD Application created: %s-%s", app_name, env)


def _ensure_apps_project() -> None:
    """Create the 'apps' ArgoCD project if it doesn't exist."""
    project_manifest = {
        "apiVersion": "argoproj.io/v1alpha1",
        "kind": "AppProject",
        "metadata": {
            "name": "apps",
            "namespace": "argocd",
        },
        "spec": {
            "description": "Tenant applications managed by seed-processor",
            "sourceRepos": ["https://github.com/*"],
            "destinations": [
                {
                    "namespace": "*-dev",
                    "server": "https://kubernetes.default.svc",
                },
                {
                    "namespace": "*-staging",
                    "server": "https://kubernetes.default.svc",
                },
                {
                    "namespace": "*-prod",
                    "server": "https://kubernetes.default.svc",
                },
            ],
            "clusterResourceWhitelist": [
                {"group": "", "kind": "Namespace"},
            ],
            "namespaceResourceWhitelist": [
                {"group": "*", "kind": "*"},
            ],
        },
    }

    try:
        apply_manifest(project_manifest)
    except RuntimeError as e:
        logger.warning("Could not ensure apps project: %s", e)
