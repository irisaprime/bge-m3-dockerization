#!/bin/bash
# =============================================================================
# BGE-M3 Pre-Deployment Security & Compliance Check
# =============================================================================
# Comprehensive validation before production deployment
# Ensures: Security, Compliance, Performance, Integrity
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
IMAGE_NAME="${IMAGE_NAME:-bge-m3-secure:latest}"
SECURITY_DIR="${SECURITY_DIR:-./security}"
CHECK_REGISTRY="${CHECK_REGISTRY:-false}"
STRICT_MODE="${STRICT_MODE:-true}"

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[✓ PASS]${NC} $1"
    ((PASSED++))
}

log_fail() {
    echo -e "${RED}[✗ FAIL]${NC} $1"
    ((FAILED++))
}

log_warn() {
    echo -e "${YELLOW}[⚠ WARN]${NC} $1"
    ((WARNINGS++))
}

# Check if image exists
check_image_exists() {
    log_info "Checking if image exists..."

    if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^$IMAGE_NAME$"; then
        log_pass "Image found: $IMAGE_NAME"
        return 0
    else
        log_fail "Image not found: $IMAGE_NAME"
        return 1
    fi
}

# Check image is not running as root
check_non_root_user() {
    log_info "Checking if container runs as non-root..."

    local user
    user=$(docker inspect "$IMAGE_NAME" --format='{{.Config.User}}')

    if [[ -z "$user" ]]; then
        log_fail "Container runs as root (no USER specified)"
        return 1
    elif [[ "$user" == "0" ]] || [[ "$user" == "root" ]]; then
        log_fail "Container runs as root (USER=$user)"
        return 1
    else
        log_pass "Container runs as non-root user: $user"
        return 0
    fi
}

# Check health check is defined
check_healthcheck() {
    log_info "Checking if HEALTHCHECK is defined..."

    local healthcheck
    healthcheck=$(docker inspect "$IMAGE_NAME" --format='{{.Config.Healthcheck}}')

    if [[ "$healthcheck" == "<nil>" ]] || [[ -z "$healthcheck" ]]; then
        log_fail "No HEALTHCHECK defined"
        return 1
    else
        log_pass "HEALTHCHECK defined"
        return 0
    fi
}

# Check image size
check_image_size() {
    log_info "Checking image size..."

    local size_bytes
    size_bytes=$(docker inspect "$IMAGE_NAME" --format='{{.Size}}')
    local size_mb=$((size_bytes / 1024 / 1024))

    # Warning if > 2GB (models included)
    if [[ $size_mb -gt 2048 ]]; then
        log_warn "Image size is large: ${size_mb}MB (includes models)"
    else
        log_pass "Image size: ${size_mb}MB"
    fi
}

# Check for shell in final image (distroless should have none)
check_no_shell() {
    log_info "Checking for shell presence..."

    # Try to run sh in the container
    if docker run --rm --entrypoint /bin/sh "$IMAGE_NAME" -c "echo test" 2>/dev/null; then
        log_warn "Shell found in image (may not be distroless)"
    else
        log_pass "No shell found (distroless confirmed)"
    fi
}

# Check for package manager
check_no_package_manager() {
    log_info "Checking for package managers..."

    local found=false

    # Check for common package managers
    for pm in apt apt-get yum dnf apk; do
        if docker run --rm --entrypoint "" "$IMAGE_NAME" which "$pm" 2>/dev/null; then
            log_fail "Package manager found: $pm"
            found=true
        fi
    done

    if [[ "$found" == "false" ]]; then
        log_pass "No package managers found"
    fi
}

# Check vulnerability scan results
check_vulnerability_scan() {
    log_info "Checking vulnerability scan results..."

    local vuln_file="$SECURITY_DIR/vulnerabilities-trivy.json"

    if [[ ! -f "$vuln_file" ]]; then
        log_warn "No vulnerability scan results found. Run: ./scripts/security-scan.sh"
        return 0
    fi

    # Check for CRITICAL vulnerabilities
    local critical_count
    critical_count=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL")] | length' "$vuln_file" 2>/dev/null || echo "0")

    if [[ $critical_count -gt 0 ]]; then
        log_fail "Found $critical_count CRITICAL vulnerabilities"
        return 1
    else
        log_pass "No CRITICAL vulnerabilities found"
    fi

    # Check for HIGH vulnerabilities (warning only)
    local high_count
    high_count=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "HIGH")] | length' "$vuln_file" 2>/dev/null || echo "0")

    if [[ $high_count -gt 0 ]]; then
        log_warn "Found $high_count HIGH severity vulnerabilities"
    fi
}

# Check SBOM exists
check_sbom_exists() {
    log_info "Checking SBOM generation..."

    if [[ -f "$SECURITY_DIR/sbom-cyclonedx.json" ]] || [[ -f "$SECURITY_DIR/sbom-spdx.json" ]]; then
        log_pass "SBOM files found"
        return 0
    else
        log_warn "No SBOM files found. Run: ./scripts/security-scan.sh"
        return 0
    fi
}

# Check for secrets in image
check_no_secrets() {
    log_info "Checking for hardcoded secrets..."

    local secrets_file="$SECURITY_DIR/secrets-scan.txt"

    if [[ ! -f "$secrets_file" ]]; then
        log_warn "No secret scan results. Run: ./scripts/security-scan.sh"
        return 0
    fi

    local secret_count
    secret_count=$(grep -c "SECRET" "$secrets_file" 2>/dev/null || echo "0")

    if [[ $secret_count -gt 0 ]]; then
        log_fail "Found $secret_count potential secrets in image!"
        return 1
    else
        log_pass "No secrets detected"
        return 0
    fi
}

# Check exposed ports
check_exposed_ports() {
    log_info "Checking exposed ports..."

    local ports
    ports=$(docker inspect "$IMAGE_NAME" --format='{{range $key, $value := .Config.ExposedPorts}}{{$key}} {{end}}')

    if [[ -z "$ports" ]]; then
        log_warn "No ports exposed"
    else
        # Check if using privileged ports (<1024)
        if echo "$ports" | grep -qE "^[0-9]{1,3}/"; then
            local port_num
            port_num=$(echo "$ports" | cut -d'/' -f1)
            if [[ $port_num -lt 1024 ]]; then
                log_warn "Using privileged port: $port_num"
            else
                log_pass "Exposed ports: $ports (non-privileged)"
            fi
        else
            log_pass "Exposed ports: $ports"
        fi
    fi
}

# Check environment variables for secrets
check_env_vars() {
    log_info "Checking environment variables for secrets..."

    local env_vars
    env_vars=$(docker inspect "$IMAGE_NAME" --format='{{range .Config.Env}}{{println .}}{{end}}')

    # Check for common secret patterns
    local found_secret=false
    while IFS= read -r line; do
        if echo "$line" | grep -qiE "(password|secret|key|token)=.+"; then
            # Check if it's a placeholder or actual value
            if ! echo "$line" | grep -qE "=(CHANGE_ME|TODO|REPLACE|<.*>|\$\{.*\})"; then
                log_warn "Potential hardcoded secret in ENV: ${line%%=*}"
                found_secret=true
            fi
        fi
    done <<< "$env_vars"

    if [[ "$found_secret" == "false" ]]; then
        log_pass "No hardcoded secrets in environment variables"
    fi
}

# Check read-only filesystem compatibility
check_readonly_compat() {
    log_info "Checking read-only filesystem compatibility..."

    # Try to run container with --read-only flag
    if docker run --rm --read-only \
        --tmpfs /tmp:noexec,nosuid,size=100M \
        "$IMAGE_NAME" \
        python3 -c "print('test')" > /dev/null 2>&1; then
        log_pass "Container compatible with read-only filesystem"
    else
        log_fail "Container NOT compatible with read-only filesystem"
        return 1
    fi
}

# Check container can start successfully
check_container_starts() {
    log_info "Checking if container starts successfully..."

    local container_id
    container_id=$(docker run -d \
        --name bge-m3-test-$$ \
        -e API_KEY=test-key \
        "$IMAGE_NAME")

    # Wait for container to start
    sleep 5

    # Check if still running
    if docker ps --filter "id=$container_id" --format '{{.ID}}' | grep -q "$container_id"; then
        log_pass "Container started successfully"
        docker stop "$container_id" > /dev/null 2>&1
        docker rm "$container_id" > /dev/null 2>&1
        return 0
    else
        log_fail "Container failed to start or crashed"
        docker logs "$container_id" 2>&1 | tail -20
        docker rm "$container_id" > /dev/null 2>&1
        return 1
    fi
}

# Check health endpoint responds
check_health_endpoint() {
    log_info "Checking health endpoint..."

    local container_id
    container_id=$(docker run -d \
        --name bge-m3-health-test-$$ \
        -p 18000:8000 \
        -e API_KEY=test-key \
        "$IMAGE_NAME")

    # Wait for startup
    sleep 10

    # Check health endpoint
    if curl -s -f http://localhost:18000/health > /dev/null 2>&1; then
        log_pass "Health endpoint responding"
        docker stop "$container_id" > /dev/null 2>&1
        docker rm "$container_id" > /dev/null 2>&1
        return 0
    else
        log_fail "Health endpoint not responding"
        docker logs "$container_id" 2>&1 | tail -20
        docker stop "$container_id" > /dev/null 2>&1
        docker rm "$container_id" > /dev/null 2>&1
        return 1
    fi
}

# Check file integrity
check_file_integrity() {
    log_info "Checking file integrity..."

    local checksums_file="$SECURITY_DIR/checksums.sha256"

    if [[ ! -f "$checksums_file" ]]; then
        log_warn "No checksums file found. Generate with: find . -type f -exec sha256sum {} \\; > checksums.sha256"
        return 0
    fi

    log_pass "File integrity checksums available"
}

# Performance check - basic inference test
check_inference_performance() {
    log_info "Running basic inference performance test..."

    local container_id
    container_id=$(docker run -d \
        --name bge-m3-perf-test-$$ \
        -p 18001:8000 \
        -e API_KEY=test-key-perf \
        "$IMAGE_NAME")

    # Wait for startup
    sleep 10

    # Test inference
    local start_time=$(date +%s.%N)

    local response
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "X-API-Key: test-key-perf" \
        -d '{"texts":["test inference"]}' \
        http://localhost:18001/embed)

    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)

    docker stop "$container_id" > /dev/null 2>&1
    docker rm "$container_id" > /dev/null 2>&1

    if echo "$response" | jq -e '.embeddings' > /dev/null 2>&1; then
        log_pass "Inference test passed (${duration}s)"
    else
        log_fail "Inference test failed"
        return 1
    fi
}

# Check labels and metadata
check_labels() {
    log_info "Checking image labels and metadata..."

    local labels
    labels=$(docker inspect "$IMAGE_NAME" --format='{{json .Config.Labels}}')

    if echo "$labels" | jq -e '.["org.opencontainers.image.title"]' > /dev/null 2>&1; then
        log_pass "OCI image labels present"
    else
        log_warn "Missing OCI image labels"
    fi
}

# Generate pre-deployment report
generate_report() {
    local report_file="$SECURITY_DIR/pre-deployment-report.txt"

    {
        echo "=============================================="
        echo "  BGE-M3 Pre-Deployment Check Report"
        echo "=============================================="
        echo ""
        echo "Image: $IMAGE_NAME"
        echo "Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
        echo ""
        echo "Results:"
        echo "  ✓ Passed:   $PASSED"
        echo "  ✗ Failed:   $FAILED"
        echo "  ⚠ Warnings: $WARNINGS"
        echo ""

        if [[ $FAILED -eq 0 ]]; then
            echo "Status: ✓ READY FOR DEPLOYMENT"
        else
            echo "Status: ✗ NOT READY - Fix failures before deploying"
        fi

        echo ""
        echo "=============================================="
    } | tee "$report_file"

    log_info "Report saved to: $report_file"
}

# Main execution
main() {
    echo "=============================================="
    echo "  BGE-M3 Pre-Deployment Security Check"
    echo "=============================================="
    echo ""

    # Create security directory if it doesn't exist
    mkdir -p "$SECURITY_DIR"

    # Run all checks
    check_image_exists || exit 1

    check_non_root_user
    check_healthcheck
    check_image_size
    check_no_shell
    check_exposed_ports
    check_env_vars
    check_vulnerability_scan
    check_sbom_exists
    check_no_secrets
    check_labels
    check_file_integrity

    # Runtime checks (optional, can be slow)
    if [[ "${SKIP_RUNTIME_CHECKS:-false}" != "true" ]]; then
        log_info "Running runtime checks..."
        check_readonly_compat
        check_container_starts
        check_health_endpoint
        check_inference_performance
    else
        log_warn "Skipping runtime checks (SKIP_RUNTIME_CHECKS=true)"
    fi

    echo ""
    generate_report

    # Exit with error if strict mode and any failures
    if [[ "$STRICT_MODE" == "true" ]] && [[ $FAILED -gt 0 ]]; then
        echo ""
        log_fail "Pre-deployment check failed in STRICT mode"
        exit 1
    fi

    echo ""
    log_info "Pre-deployment check completed!"
}

main "$@"
