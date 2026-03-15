"""
templates.py — Creates GitHub repositories from the app-template.

Uses PyGithub to:
1. Create the repository
2. Copy app-template files with variable substitution
3. Set up branch protection rules
"""

import logging
from pathlib import Path
from typing import Optional

from github import Github, GithubException

logger = logging.getLogger(__name__)

REPO_ROOT = Path(__file__).parent.parent.parent
APP_TEMPLATE_DIR = REPO_ROOT / "app-template"

# Files/directories to skip when copying template
TEMPLATE_EXCLUDES = {".git", "__pycache__", "*.pyc", ".DS_Store"}

# Variables substituted in template files
TEMPLATE_VARS = [
    "APP_NAME",
    "APP_DESCRIPTION",
    "TEAM",
    "LANGUAGE",
    "HARBOR_PROJECT",
    "GITHUB_ORG",
    "VAULT_PATH",
]


def _substitute_vars(content: str, substitutions: dict[str, str]) -> str:
    """Replace {{VAR_NAME}} placeholders in template content."""
    for key, value in substitutions.items():
        content = content.replace(f"{{{{{key}}}}}", value)
    return content


def _should_skip(path: Path) -> bool:
    """Return True if this path should be excluded from the template."""
    for exclude in TEMPLATE_EXCLUDES:
        if exclude.startswith("*"):
            if path.name.endswith(exclude[1:]):
                return True
        elif path.name == exclude:
            return True
    return False


def _collect_template_files(template_dir: Path) -> list[tuple[Path, str]]:
    """
    Collect all template files and their contents.
    Returns list of (relative_path, content) tuples.
    """
    files = []
    for file_path in template_dir.rglob("*"):
        if file_path.is_dir():
            continue
        if _should_skip(file_path):
            continue

        relative_path = file_path.relative_to(template_dir)

        try:
            content = file_path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            # Binary file, read as bytes
            content = None

        files.append((relative_path, content))

    return files


def create_github_repo(seed: dict, github_token: str) -> Optional[str]:
    """
    Create a GitHub repository from the app-template.

    Args:
        seed: Parsed seed YAML as dict
        github_token: GitHub PAT with repo + workflow permissions

    Returns:
        Repository URL if successful, None otherwise
    """
    spec = seed["spec"]
    app_name = spec["name"]
    team = spec["team"]
    org_name = spec["repository"]["organization"]
    language = spec["language"]
    description = spec["description"]
    visibility = spec["repository"].get("visibility", "private")
    branch_protection = spec["repository"].get("branch_protection", True)

    vault_path = spec.get("secrets", {}).get("vault_path", f"secret/{app_name}/config")

    substitutions = {
        "APP_NAME": app_name,
        "APP_DESCRIPTION": description,
        "TEAM": team,
        "LANGUAGE": language,
        "HARBOR_PROJECT": team,
        "GITHUB_ORG": org_name,
        "VAULT_PATH": vault_path,
    }

    gh = Github(github_token)

    # Get org or user.
    # gh.get_user(name) returns NamedUser which lacks create_repo.
    # gh.get_user() with no argument returns AuthenticatedUser which has it.
    try:
        owner = gh.get_organization(org_name)
    except GithubException:
        owner = gh.get_user()

    # Check if repo already exists
    try:
        existing_repo = owner.get_repo(app_name)
        logger.info("Repository already exists: %s/%s", org_name, app_name)
        return existing_repo.html_url
    except GithubException:
        pass  # Repo doesn't exist, create it

    # Create repository
    logger.info("Creating repository: %s/%s", org_name, app_name)
    repo = owner.create_repo(
        name=app_name,
        description=description,
        private=(visibility == "private"),
        auto_init=False,
    )
    logger.info("Repository created: %s", repo.html_url)

    # Copy template files
    template_files = _collect_template_files(APP_TEMPLATE_DIR)
    for relative_path, content in template_files:
        # Substitute filename variables too
        str_path = str(relative_path)
        for key, value in substitutions.items():
            str_path = str_path.replace(f"{{{{{key}}}}}", value)

        if content is not None:
            substituted_content = _substitute_vars(content, substitutions)
            try:
                repo.create_file(
                    path=str_path,
                    message=f"chore: initialize from app-template",
                    content=substituted_content,
                    branch="main",
                )
                logger.debug("Created file: %s", str_path)
            except GithubException as e:
                logger.warning("Could not create file %s: %s", str_path, e)

    # Set branch protection
    if branch_protection:
        try:
            branch = repo.get_branch("main")
            branch.edit_protection(
                required_approving_review_count=1,
                dismiss_stale_reviews=True,
                require_code_owner_reviews=False,
                contexts=["ci / build-and-scan"],
                enforce_admins=False,
            )
            logger.info("Branch protection enabled for main")
        except GithubException as e:
            logger.warning("Could not set branch protection: %s", e)

    # Add topics
    topics = spec["repository"].get("topics", [])
    topics += [team, language, "platform-managed"]
    try:
        repo.replace_topics(topics)
    except GithubException as e:
        logger.warning("Could not set topics: %s", e)

    logger.info("Repository setup complete: %s", repo.html_url)
    return repo.html_url
