"""
BGE-M3 Secure Embedding Service
=================================
Production-ready FastAPI service with enterprise security hardening

Security Features:
- API Key authentication
- Rate limiting (SlowAPI)
- Input validation and sanitization
- Security headers (CORS, CSP, HSTS)
- Request/response logging (no PII)
- Prometheus metrics
- Health checks
"""

import os
import time
import logging
from typing import List, Optional, Dict, Any
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Security, Request, status
from fastapi.security import APIKeyHeader
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from pydantic import BaseModel, Field, validator

from embedding_service import EmbeddingService, EmbeddingConfig
from models import (
    EmbeddingRequest,
    EmbeddingResponse,
    HealthResponse,
    ErrorResponse,
    MetricsResponse
)

# =============================================================================
# Configuration
# =============================================================================

API_KEY = os.getenv("API_KEY", "CHANGE_ME_IN_PRODUCTION")
API_KEY_ENABLED = os.getenv("API_KEY_ENABLED", "true").lower() == "true"
RATE_LIMIT_ENABLED = os.getenv("RATE_LIMIT_ENABLED", "true").lower() == "true"
RATE_LIMIT = os.getenv("RATE_LIMIT_PER_MINUTE", "60")
MAX_INPUT_LENGTH = int(os.getenv("MAX_SEQ_LENGTH", "8192"))
MAX_BATCH_SIZE = int(os.getenv("MAX_BATCH_SIZE", "32"))

# =============================================================================
# Logging Configuration (No PII)
# =============================================================================

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger(__name__)

# Disable sensitive information logging
logging.getLogger("uvicorn.access").setLevel(logging.WARNING)

# =============================================================================
# Prometheus Metrics
# =============================================================================

REQUEST_COUNT = Counter(
    'bge_m3_requests_total',
    'Total number of embedding requests',
    ['endpoint', 'status']
)

REQUEST_LATENCY = Histogram(
    'bge_m3_request_duration_seconds',
    'Request latency in seconds',
    ['endpoint']
)

EMBEDDING_COUNT = Counter(
    'bge_m3_embeddings_total',
    'Total number of embeddings generated'
)

ERROR_COUNT = Counter(
    'bge_m3_errors_total',
    'Total number of errors',
    ['error_type']
)

# =============================================================================
# Security: API Key Authentication
# =============================================================================

api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)

async def verify_api_key(api_key: str = Security(api_key_header)) -> str:
    """Verify API key from request header."""
    if not API_KEY_ENABLED:
        return "disabled"

    if api_key is None:
        ERROR_COUNT.labels(error_type="missing_api_key").inc()
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="API Key required. Provide X-API-Key header."
        )

    if api_key != API_KEY:
        ERROR_COUNT.labels(error_type="invalid_api_key").inc()
        logger.warning("Invalid API key attempt from client")
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid API Key"
        )

    return api_key

# =============================================================================
# Rate Limiting
# =============================================================================

limiter = Limiter(
    key_func=get_remote_address,
    enabled=RATE_LIMIT_ENABLED
)

# =============================================================================
# Application Lifecycle
# =============================================================================

embedding_service: Optional[EmbeddingService] = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Application startup and shutdown lifecycle.
    Loads model on startup, cleans up on shutdown.
    """
    global embedding_service

    logger.info("Starting BGE-M3 Embedding Service...")
    logger.info(f"Security: API Key Auth={'enabled' if API_KEY_ENABLED else 'disabled'}")
    logger.info(f"Security: Rate Limiting={'enabled' if RATE_LIMIT_ENABLED else 'disabled'}")

    try:
        # Initialize embedding service
        config = EmbeddingConfig()
        embedding_service = EmbeddingService(config)
        logger.info("Model loaded successfully")
        logger.info(f"Using {'ONNX' if config.use_onnx else 'PyTorch'} backend")

    except Exception as e:
        logger.error(f"Failed to load model: {e}")
        ERROR_COUNT.labels(error_type="model_load_failure").inc()
        raise

    yield  # Server is running

    # Cleanup on shutdown
    logger.info("Shutting down BGE-M3 Embedding Service...")
    embedding_service = None

# =============================================================================
# FastAPI Application
# =============================================================================

app = FastAPI(
    title="BGE-M3 Secure Embedding Service",
    description="Production-ready multi-modal embedding API with enterprise security",
    version="1.0.0",
    docs_url=None if os.getenv("DISABLE_DOCS", "false").lower() == "true" else "/docs",
    redoc_url=None,
    lifespan=lifespan
)

# Add rate limiting
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# =============================================================================
# Security Middleware
# =============================================================================

# CORS Configuration (restrictive by default)
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ORIGINS", "").split(",") if os.getenv("CORS_ORIGINS") else [],
    allow_credentials=False,
    allow_methods=["POST", "GET"],
    allow_headers=["X-API-Key", "Content-Type"],
)

@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    """Add security headers to all responses."""
    response = await call_next(request)

    # Security headers
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    response.headers["Content-Security-Policy"] = "default-src 'none'; frame-ancestors 'none'"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Permissions-Policy"] = "geolocation=(), microphone=(), camera=()"

    # Remove server header
    response.headers.pop("Server", None)

    return response

@app.middleware("http")
async def log_requests(request: Request, call_next):
    """Log requests without PII."""
    start_time = time.time()

    # Log request (no sensitive data)
    logger.info(f"Request: {request.method} {request.url.path}")

    response = await call_next(request)

    # Log response time
    duration = time.time() - start_time
    logger.info(f"Response: {response.status_code} - {duration:.3f}s")

    return response

# =============================================================================
# API Endpoints
# =============================================================================

@app.get(
    "/health",
    response_model=HealthResponse,
    tags=["Health"],
    summary="Health check endpoint"
)
async def health_check():
    """
    Health check endpoint for container orchestration.
    Returns service status and model availability.
    """
    is_healthy = embedding_service is not None

    return HealthResponse(
        status="healthy" if is_healthy else "unhealthy",
        model_loaded=is_healthy,
        version="1.0.0"
    )

@app.get(
    "/metrics",
    tags=["Monitoring"],
    summary="Prometheus metrics endpoint"
)
async def metrics():
    """
    Prometheus metrics endpoint for monitoring.
    Returns metrics in Prometheus format.
    """
    return JSONResponse(
        content=generate_latest().decode("utf-8"),
        media_type=CONTENT_TYPE_LATEST
    )

@app.post(
    "/embed",
    response_model=EmbeddingResponse,
    tags=["Embeddings"],
    summary="Generate embeddings for input texts",
    dependencies=[Security(verify_api_key)] if API_KEY_ENABLED else []
)
@limiter.limit(f"{RATE_LIMIT}/minute")
async def create_embeddings(
    request: Request,
    embedding_request: EmbeddingRequest
):
    """
    Generate embeddings for input texts using BGE-M3 model.

    **Security:**
    - Requires valid API key in X-API-Key header
    - Rate limited to prevent abuse
    - Input validation and sanitization

    **Parameters:**
    - texts: List of text strings to embed (max batch size: 32)
    - return_dense: Return dense embeddings (1024 dimensions)
    - return_sparse: Return sparse embeddings (lexical matching)
    - return_colbert: Return multi-vector embeddings
    - normalize: L2 normalize dense embeddings

    **Returns:**
    - Embedding vectors for each input text
    - Processing time and metadata
    """

    if embedding_service is None:
        ERROR_COUNT.labels(error_type="service_unavailable").inc()
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Model not loaded. Service unavailable."
        )

    start_time = time.time()

    try:
        # Validate batch size
        if len(embedding_request.texts) > MAX_BATCH_SIZE:
            ERROR_COUNT.labels(error_type="batch_size_exceeded").inc()
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Batch size exceeds maximum allowed ({MAX_BATCH_SIZE})"
            )

        # Generate embeddings
        with REQUEST_LATENCY.labels(endpoint="embed").time():
            result = embedding_service.encode(
                texts=embedding_request.texts,
                return_dense=embedding_request.return_dense,
                return_sparse=embedding_request.return_sparse,
                return_colbert=embedding_request.return_colbert,
                normalize=embedding_request.normalize
            )

        # Update metrics
        REQUEST_COUNT.labels(endpoint="embed", status="success").inc()
        EMBEDDING_COUNT.inc(len(embedding_request.texts))

        processing_time = time.time() - start_time

        return EmbeddingResponse(
            embeddings=result,
            model="BAAI/bge-m3",
            processing_time=processing_time,
            count=len(embedding_request.texts)
        )

    except ValueError as e:
        ERROR_COUNT.labels(error_type="validation_error").inc()
        REQUEST_COUNT.labels(endpoint="embed", status="error").inc()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        logger.error(f"Embedding generation failed: {e}", exc_info=True)
        ERROR_COUNT.labels(error_type="internal_error").inc()
        REQUEST_COUNT.labels(endpoint="embed", status="error").inc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error. Please try again later."
        )

@app.get(
    "/",
    tags=["Info"],
    summary="Service information"
)
async def root():
    """Service information endpoint."""
    return {
        "service": "BGE-M3 Secure Embedding Service",
        "version": "1.0.0",
        "status": "operational",
        "model": "BAAI/bge-m3",
        "security": {
            "api_key_enabled": API_KEY_ENABLED,
            "rate_limiting_enabled": RATE_LIMIT_ENABLED
        },
        "endpoints": {
            "embed": "/embed (POST)",
            "health": "/health (GET)",
            "metrics": "/metrics (GET)"
        }
    }

# =============================================================================
# Error Handlers
# =============================================================================

@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    """Custom HTTP exception handler."""
    return JSONResponse(
        status_code=exc.status_code,
        content=ErrorResponse(
            error=exc.detail,
            status_code=exc.status_code
        ).dict()
    )

@app.exception_handler(Exception)
async def general_exception_handler(request: Request, exc: Exception):
    """Catch-all exception handler (no stack traces to client)."""
    logger.error(f"Unhandled exception: {exc}", exc_info=True)
    ERROR_COUNT.labels(error_type="unhandled_exception").inc()

    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content=ErrorResponse(
            error="Internal server error",
            status_code=500
        ).dict()
    )

# =============================================================================
# Application Entry Point
# =============================================================================

if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8000,
        log_level="info",
        access_log=False  # Disable access logs to prevent PII leakage
    )
