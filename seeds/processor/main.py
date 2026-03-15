#!/usr/bin/env python3
"""
Seed Processor — reads seed YAML files and creates:
  1. GitHub repository (from app-template)
  2. ArgoCD Applications (one per environment)
  3. Infrastructure (namespace, bucket, stream, vault path) via tofu
"""

import json
import logging
import os
import subprocess
import sys
from pathlib import Path
from typing import Optional

import jsonschema
import yaml
from github import Github

from argocd import create_argocd_applications
from templates import create_github_repo

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%SZ",
)
logger = logging.getLogger(__name__)

REPO_ROOT = Path(__file__).parent.parent.parent
SCHEMA_PATH = REPO_ROOT / "seeds" / "schema" / "seed.schema.json"


def load_schema() -> dict:
    with open(SCHEMA_PATH) as f:
        return json.load(f)


def load_seed(seed_path: Path) -> dict:
    with open(seed_path) as f:
        return yaml.safe_load(f)


def validate_seed(seed: dict, schema: dict) -> None:
    """Validate seed YAML against JSON Schema. Raises on failure."""
    jsonschema.validate(instance=seed, schema=schema)
    logger.info("Seed validation passed")


def _tofu_binary() -> str:
    """Return 'tofu' if available, fall back to 'terraform'."""
    import shutil
    return "tofu" if shutil.which("tofu") else "terraform"


def run_tofu(seed: dict, env: str) -> None:
    """Run tofu apply for the given seed and environment."""
    app_name = seed["spec"]["name"]
    team = seed["spec"]["team"]
    tofu_env_dir = REPO_ROOT / "tofu" / "environments" / env

    if not tofu_env_dir.exists():
        logger.warning("Tofu environment directory not found: %s", tofu_env_dir)
        return

    binary = _tofu_binary()

    # Init first (idempotent — safe to re-run)
    init_result = subprocess.run(
        [binary, "init", "-input=false"],
        cwd=tofu_env_dir, capture_output=True, text=True
    )
    if init_result.returncode != 0:
        logger.error("%s init failed:\n%s", binary, init_result.stderr)
        raise RuntimeError(f"{binary} init failed for {app_name} in {env}")

    cmd = [
        binary, "apply",
        "-auto-approve",
        f"-var=app_name={app_name}",
        f"-var=team={team}",
        f"-var=environment={env}",
    ]

    # Add optional vars based on seed spec
    if seed["spec"].get("storage", {}).get("enabled"):
        bucket = seed["spec"]["storage"]["bucket_name"]
        cmd += [f"-var=storage_bucket_name={bucket}"]

    if seed["spec"].get("messaging", {}).get("enabled"):
        stream = seed["spec"]["messaging"]["stream_name"]
        subjects = ",".join(seed["spec"]["messaging"]["subjects"])
        cmd += [f"-var=nats_stream_name={stream}", f"-var=nats_subjects={subjects}"]

    logger.info("Running %s for environment %s: %s", binary, env, " ".join(cmd))
    result = subprocess.run(cmd, cwd=tofu_env_dir, capture_output=True, text=True)

    if result.returncode != 0:
        logger.error("Tofu failed:\n%s", result.stderr)
        raise RuntimeError(f"tofu apply failed for {app_name} in {env}")

    logger.info("Tofu apply succeeded for %s/%s", app_name, env)


def setup_vault(seed: dict) -> None:
    """Initialize Vault path and policy for the service."""
    spec = seed["spec"]
    app_name = spec["name"]
    secrets_config = spec.get("secrets", {})

    if not secrets_config.get("enabled", True):
        logger.info("Secrets disabled for %s, skipping Vault setup", app_name)
        return

    vault_path = secrets_config.get("vault_path", f"secret/{app_name}/config")
    vault_addr = os.environ.get("VAULT_ADDR", "https://vault.local.dev")
    vault_token = os.environ.get("VAULT_TOKEN", "dev-root-token")

    env = {**os.environ, "VAULT_ADDR": vault_addr, "VAULT_TOKEN": vault_token}

    # Create placeholder secret
    result = subprocess.run(
        ["vault", "kv", "put", vault_path, f"PLACEHOLDER=replace-for-{app_name}"],
        capture_output=True, text=True, env=env
    )
    if result.returncode != 0:
        logger.warning("Could not create Vault placeholder: %s", result.stderr)
    else:
        logger.info("Vault path created: %s", vault_path)

    # Create policy
    environments = spec["infrastructure"]["environments"]
    namespaces = ",".join([f"{app_name}-{e}" for e in environments])

    policy_hcl = f"""
path "secret/data/{app_name}/*" {{
  capabilities = ["read"]
}}
path "secret/metadata/{app_name}/*" {{
  capabilities = ["list"]
}}
"""
    result = subprocess.run(
        ["vault", "policy", "write", app_name, "-"],
        input=policy_hcl, capture_output=True, text=True, env=env
    )
    if result.returncode != 0:
        logger.warning("Could not create Vault policy: %s", result.stderr)
    else:
        logger.info("Vault policy created for %s", app_name)

    # Create Kubernetes auth role
    result = subprocess.run([
        "vault", "write", f"auth/kubernetes/role/{app_name}",
        f"bound_service_account_names={app_name}",
        f"bound_service_account_namespaces={namespaces}",
        f"policies={app_name}",
        "ttl=1h",
    ], capture_output=True, text=True, env=env)

    if result.returncode != 0:
        logger.warning("Could not create Vault role: %s", result.stderr)
    else:
        logger.info("Vault Kubernetes auth role created for %s", app_name)


def process_seed(seed_path: Path, schema: dict) -> None:
    """Process a single seed file end-to-end."""
    logger.info("Processing seed: %s", seed_path)

    seed = load_seed(seed_path)
    validate_seed(seed, schema)

    app_name = seed["spec"]["name"]
    environments = seed["spec"]["infrastructure"]["environments"]

    # 1. Create GitHub repo
    github_token = os.environ.get("GITHUB_TOKEN")
    if github_token:
        create_github_repo(seed, github_token)
    else:
        logger.warning("GITHUB_TOKEN not set, skipping repo creation")

    # 2. Create ArgoCD Applications
    create_argocd_applications(seed)

    # 3. Run tofu for each environment
    for env in environments:
        try:
            run_tofu(seed, env)
        except RuntimeError as e:
            logger.error("Tofu failed for %s/%s: %s", app_name, env, e)

    # 4. Set up Vault
    setup_vault(seed)

    logger.info("Seed processing complete for %s", app_name)


def get_changed_seeds() -> list[Path]:
    """Get list of seed files changed in the current git commit."""
    result = subprocess.run(
        ["git", "diff", "--name-only", "HEAD~1", "HEAD", "--", "seeds/apps/*.yaml"],
        capture_output=True, text=True, cwd=REPO_ROOT
    )

    if result.returncode != 0:
        # Fallback: process all seeds if git diff fails
        logger.warning("git diff failed, processing all seeds")
        return list((REPO_ROOT / "seeds" / "apps").glob("*.yaml"))

    changed = [
        REPO_ROOT / p.strip()
        for p in result.stdout.splitlines()
        if p.strip() and not p.strip().endswith("example-app.yaml")
    ]
    return changed


def main() -> None:
    schema = load_schema()

    # Allow specifying a specific seed file via arg
    if len(sys.argv) > 1:
        seed_files = [Path(sys.argv[1])]
    else:
        seed_files = get_changed_seeds()

    if not seed_files:
        logger.info("No seed files to process")
        return

    errors = []
    for seed_path in seed_files:
        if not seed_path.exists():
            logger.warning("Seed file not found: %s", seed_path)
            continue
        try:
            process_seed(seed_path, schema)
        except Exception as e:
            logger.error("Failed to process %s: %s", seed_path, e)
            errors.append((seed_path, e))

    if errors:
        logger.error("%d seed(s) failed to process", len(errors))
        sys.exit(1)

    logger.info("All seeds processed successfully")


if __name__ == "__main__":
    main()
