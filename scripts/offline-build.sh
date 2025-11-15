#!/bin/bash
# =============================================================================
# BGE-M3 Offline Build Script for Air-Gapped Environments
# =============================================================================
# Prepares and builds Docker image in environments without internet access
# Steps: Download models, export image, transfer, import, build
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
MODE="${1:-prepare}"  # prepare, build, or all
MODEL_DIR="./models"
EXPORT_DIR="./offline-bundle"
IMAGE_NAME="bge-m3-secure:latest"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# =============================================================================
# PREPARATION PHASE (Run on internet-connected machine)
# =============================================================================

prepare_offline_bundle() {
    log_info "Preparing offline bundle for air-gapped deployment..."

    mkdir -p "$EXPORT_DIR"
    mkdir -p "$MODEL_DIR"

    # Step 1: Download BGE-M3 models
    download_models

    # Step 2: Download Python dependencies
    download_python_deps

    # Step 3: Download base Docker images
    export_base_images

    # Step 4: Package everything
    package_offline_bundle

    log_success "Offline bundle prepared successfully!"
    log_info "Transfer $EXPORT_DIR to air-gapped environment"
}

# Download models from Hugging Face
download_models() {
    log_info "Downloading BGE-M3 models..."

    # Install huggingface-cli if not present
    if ! command -v huggingface-cli &> /dev/null; then
        log_info "Installing huggingface-hub..."
        pip install --user huggingface-hub[cli]
    fi

    # Download main model
    log_info "Downloading BAAI/bge-m3..."
    huggingface-cli download \
        BAAI/bge-m3 \
        --local-dir "$MODEL_DIR/bge-m3" \
        --local-dir-use-symlinks False

    # Download ONNX-optimized version
    log_info "Downloading ONNX-optimized model..."
    huggingface-cli download \
        philipchung/bge-m3-onnx \
        --local-dir "$MODEL_DIR/bge-m3-onnx" \
        --local-dir-use-symlinks False

    # Generate checksums for integrity verification
    log_info "Generating model checksums..."
    find "$MODEL_DIR" -type f -exec sha256sum {} \; > "$MODEL_DIR/checksums.sha256"

    log_success "Models downloaded to $MODEL_DIR"
}

# Download Python dependencies as wheels
download_python_deps() {
    log_info "Downloading Python dependencies..."

    mkdir -p "$EXPORT_DIR/python-packages"

    # Download all packages with dependencies
    pip download \
        -r requirements.txt \
        --dest "$EXPORT_DIR/python-packages" \
        --platform manylinux2014_x86_64 \
        --python-version 311 \
        --only-binary=:all:

    # Also download for any platform (source distributions)
    pip download \
        -r requirements.txt \
        --dest "$EXPORT_DIR/python-packages" \
        --no-binary :all: || true

    log_success "Python packages downloaded to $EXPORT_DIR/python-packages"
}

# Export base Docker images
export_base_images() {
    log_info "Exporting base Docker images..."

    # Pull required base images
    local images=(
        "python:3.11-slim-bookworm"
        "gcr.io/distroless/python3-debian12:nonroot"
    )

    for img in "${images[@]}"; do
        log_info "Pulling $img..."
        docker pull "$img"

        local safe_name
        safe_name=$(echo "$img" | tr '/:' '_')

        log_info "Exporting $img..."
        docker save "$img" | gzip > "$EXPORT_DIR/${safe_name}.tar.gz"
    done

    log_success "Base images exported to $EXPORT_DIR"
}

# Download UV installer
download_uv_installer() {
    log_info "Downloading UV installer..."

    curl -LsSf https://astral.sh/uv/install.sh -o "$EXPORT_DIR/uv-install.sh"
    chmod +x "$EXPORT_DIR/uv-install.sh"

    log_success "UV installer downloaded"
}

# Download security scanning tools
download_security_tools() {
    log_info "Downloading security tools..."

    mkdir -p "$EXPORT_DIR/tools"

    # Trivy
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        curl -sfL https://github.com/aquasecurity/trivy/releases/latest/download/trivy_Linux-64bit.tar.gz \
            -o "$EXPORT_DIR/tools/trivy.tar.gz"
    fi

    # Syft
    curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh \
        -o "$EXPORT_DIR/tools/syft-install.sh"
    chmod +x "$EXPORT_DIR/tools/syft-install.sh"

    log_success "Security tools downloaded"
}

# Package offline bundle
package_offline_bundle() {
    log_info "Packaging offline bundle..."

    # Copy project files
    cp -r docker "$EXPORT_DIR/"
    cp -r app "$EXPORT_DIR/"
    cp -r scripts "$EXPORT_DIR/"
    cp -r config "$EXPORT_DIR/" 2>/dev/null || true
    cp requirements.txt "$EXPORT_DIR/"
    cp README.md "$EXPORT_DIR/" 2>/dev/null || true

    # Copy models
    cp -r "$MODEL_DIR" "$EXPORT_DIR/"

    # Create manifest
    cat > "$EXPORT_DIR/MANIFEST.txt" << EOF
BGE-M3 Offline Deployment Bundle
=================================

Created: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Version: 1.0.0

Contents:
---------
1. Models:
   - models/bge-m3/          : Main BGE-M3 model
   - models/bge-m3-onnx/     : ONNX-optimized model
   - models/checksums.sha256 : Model integrity checksums

2. Docker Base Images:
   $(ls -1 "$EXPORT_DIR"/*.tar.gz 2>/dev/null | xargs -n1 basename)

3. Python Packages:
   - python-packages/        : All dependencies as wheels

4. Application:
   - app/                    : FastAPI application
   - docker/                 : Dockerfiles and configs
   - scripts/                : Build and deployment scripts
   - config/                 : Security profiles

5. Security Tools:
   - tools/                  : Trivy, Syft installers

Installation Instructions:
--------------------------
1. Transfer this directory to air-gapped environment
2. Run: ./scripts/offline-build.sh build
3. Verify: ./scripts/pre-deployment-check.sh

File Integrity:
---------------
Verify checksums with:
  sha256sum -c models/checksums.sha256

Total Size: $(du -sh "$EXPORT_DIR" | cut -f1)
EOF

    # Create transfer archive
    log_info "Creating transfer archive..."
    tar -czf "bge-m3-offline-bundle-$(date +%Y%m%d).tar.gz" "$EXPORT_DIR"

    log_success "Offline bundle packaged: bge-m3-offline-bundle-$(date +%Y%m%d).tar.gz"
}

# =============================================================================
# BUILD PHASE (Run in air-gapped environment)
# =============================================================================

build_offline() {
    log_info "Building Docker image in offline mode..."

    # Verify bundle integrity
    verify_bundle_integrity

    # Load base images
    load_base_images

    # Build Docker image
    build_docker_image_offline

    log_success "Offline build completed successfully!"
}

# Verify bundle integrity
verify_bundle_integrity() {
    log_info "Verifying bundle integrity..."

    if [[ ! -f "$MODEL_DIR/checksums.sha256" ]]; then
        log_warn "No checksums file found, skipping integrity check"
        return
    fi

    if (cd "$MODEL_DIR" && sha256sum -c checksums.sha256 --quiet); then
        log_success "Model integrity verified"
    else
        log_error "Model integrity check FAILED!"
        exit 1
    fi
}

# Load base images into Docker
load_base_images() {
    log_info "Loading base Docker images..."

    for img_file in "$EXPORT_DIR"/*.tar.gz; do
        if [[ -f "$img_file" ]]; then
            log_info "Loading $(basename "$img_file")..."
            gunzip -c "$img_file" | docker load
        fi
    done

    log_success "Base images loaded"
}

# Build Docker image (offline)
build_docker_image_offline() {
    log_info "Building Docker image..."

    # Modify Dockerfile to use local models
    local dockerfile="$EXPORT_DIR/docker/Dockerfile.secure.offline"

    # Create offline version of Dockerfile
    cat > "$dockerfile" << 'EOF'
# Offline build version - uses local models and packages
FROM python:3.11-slim-bookworm AS builder

# Copy UV installer and install
COPY offline-bundle/uv-install.sh /tmp/
RUN sh /tmp/uv-install.sh && cp /root/.cargo/bin/uv /usr/local/bin/

ENV UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=1 \
    UV_PYTHON_DOWNLOADS=never

WORKDIR /build

# Copy and install Python packages from local directory
COPY offline-bundle/python-packages /tmp/packages
COPY requirements.txt .

RUN uv pip install --system --no-index --find-links /tmp/packages -r requirements.txt

# Compile bytecode
RUN python -m compileall -b /usr/local/lib/python3.11/site-packages && \
    find /usr/local/lib/python3.11/site-packages -name "*.py" -delete

# Application stage
FROM builder AS app-builder
WORKDIR /app
COPY app/ /app/
RUN chmod -R 644 /app/*.py && chmod 755 /app

# Runtime stage
FROM gcr.io/distroless/python3-debian12:nonroot AS runtime

LABEL org.opencontainers.image.title="BGE-M3 Embedding Service (Security Hardened)" \
      org.opencontainers.image.description="Production-ready BGE-M3 with enterprise security" \
      security.hardened="true"

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH=/app \
    MODEL_PATH=/models/bge-m3 \
    USE_ONNX=true

COPY --from=builder --chown=nonroot:nonroot /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=app-builder --chown=nonroot:nonroot /app /app

# Copy models from local directory
COPY --chown=nonroot:nonroot models /models

EXPOSE 8000
WORKDIR /app
USER nonroot:nonroot

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD ["/usr/bin/python3", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health').read()"]

ENTRYPOINT ["/usr/bin/python3", "-m", "uvicorn"]
CMD ["main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
EOF

    # Build the image
    docker build \
        -f "$dockerfile" \
        -t "$IMAGE_NAME" \
        --no-cache \
        .

    log_success "Docker image built: $IMAGE_NAME"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

show_usage() {
    cat << EOF
BGE-M3 Offline Build Script
===========================

Usage: $0 <mode>

Modes:
  prepare  - Download models, packages, images (internet-connected machine)
  build    - Build Docker image from offline bundle (air-gapped machine)
  all      - Run both prepare and build (for testing)

Examples:
  # On internet-connected machine:
  $0 prepare

  # Transfer generated bundle to air-gapped environment, then:
  $0 build

Environment Variables:
  MODEL_DIR    - Directory for models (default: ./models)
  EXPORT_DIR   - Directory for offline bundle (default: ./offline-bundle)
  IMAGE_NAME   - Docker image name (default: bge-m3-secure:latest)

EOF
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    echo "=============================================="
    echo "  BGE-M3 Offline Build"
    echo "=============================================="
    echo ""

    case "${MODE}" in
        prepare)
            prepare_offline_bundle
            ;;
        build)
            build_offline
            ;;
        all)
            prepare_offline_bundle
            build_offline
            ;;
        help|--help|-h)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown mode: $MODE"
            show_usage
            exit 1
            ;;
    esac

    echo ""
    echo "=============================================="
    log_success "Operation completed!"
    echo "=============================================="
}

main "$@"
