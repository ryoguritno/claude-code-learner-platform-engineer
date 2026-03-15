"""
{{APP_NAME}} — {{APP_DESCRIPTION}}

FastAPI application template. Replace this with your actual application logic.
"""

import logging
import os
import time
from contextlib import asynccontextmanager
from typing import Any

import uvicorn
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from prometheus_fastapi_instrumentator import Instrumentator

# Structured logging
logging.basicConfig(
    level=logging.INFO,
    format='{"time":"%(asctime)s","level":"%(levelname)s","msg":"%(message)s"}',
)
logger = logging.getLogger(__name__)

# Application startup time
START_TIME = time.time()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan handler."""
    logger.info("Starting {{APP_NAME}}")
    # Initialize connections here (database, cache, etc.)
    yield
    # Cleanup here
    logger.info("Shutting down {{APP_NAME}}")


app = FastAPI(
    title="{{APP_NAME}}",
    description="{{APP_DESCRIPTION}}",
    version=os.getenv("APP_VERSION", "0.1.0"),
    lifespan=lifespan,
)

# CORS — restrict in production
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("ALLOWED_ORIGINS", "*").split(","),
    allow_methods=["*"],
    allow_headers=["*"],
)

# Prometheus metrics — exposes /metrics endpoint
Instrumentator().instrument(app).expose(app)


@app.get("/healthz", tags=["health"])
async def liveness() -> dict[str, str]:
    """Liveness probe — returns 200 if process is alive."""
    return {"status": "ok"}


@app.get("/ready", tags=["health"])
async def readiness() -> dict[str, Any]:
    """Readiness probe — returns 200 if ready to serve traffic."""
    return {
        "status": "ready",
        "uptime_seconds": round(time.time() - START_TIME, 2),
        "version": os.getenv("APP_VERSION", "0.1.0"),
    }


@app.get("/", tags=["app"])
async def root() -> dict[str, str]:
    """Root endpoint — replace with your application logic."""
    return {
        "service": "{{APP_NAME}}",
        "team": "{{TEAM}}",
        "message": "Hello from the platform!",
    }


@app.get("/info", tags=["app"])
async def info() -> dict[str, Any]:
    """Service information endpoint."""
    return {
        "name": "{{APP_NAME}}",
        "team": "{{TEAM}}",
        "version": os.getenv("APP_VERSION", "0.1.0"),
        "environment": os.getenv("ENVIRONMENT", "unknown"),
    }


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException) -> JSONResponse:
    logger.warning("HTTP %d: %s %s", exc.status_code, request.method, request.url)
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": exc.detail},
    )


@app.exception_handler(Exception)
async def general_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    logger.error("Unhandled exception: %s %s — %s", request.method, request.url, exc)
    return JSONResponse(
        status_code=500,
        content={"error": "Internal server error"},
    )


if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=int(os.getenv("PORT", "8080")),
        log_level="info",
    )
