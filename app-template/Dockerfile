# Multi-stage Dockerfile for {{APP_NAME}}
# Stage 1: Builder — installs dependencies
# Stage 2: Final — distroless, non-root, minimal attack surface

# ===== Stage 1: Builder =====
FROM python:3.12-slim AS builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies to user dir (not system)
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# ===== Stage 2: Final =====
# gcr.io/distroless/python3-debian12:
# - No shell (/bin/sh, /bin/bash)
# - No package manager (apt, pip)
# - Minimal system libraries
# - Runs as nonroot (UID 65532) by default
FROM gcr.io/distroless/python3-debian12:nonroot

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /root/.local/lib /root/.local/lib
COPY --from=builder /root/.local/bin /root/.local/bin

# Copy application source
COPY src/ /app/

# nonroot user (UID 65532) — set by the distroless image
# USER nonroot  ← already set by the base image tag :nonroot

# Document the port
EXPOSE 8080

# Set environment defaults (override via Helm values / Vault injection)
ENV PORT=8080 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/root/.local/bin:${PATH}"

# Health check for Docker (Kubernetes uses probes, not this)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/healthz')"

CMD ["main.py"]
