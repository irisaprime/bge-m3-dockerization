# BGE-M3 Embedding Service - Security Documentation

**Version:** 1.0.0
**Last Updated:** 2025-11-15
**Classification:** Internal - Security Hardened

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Security Architecture](#security-architecture)
3. [Security Controls](#security-controls)
4. [Deployment Security](#deployment-security)
5. [Runtime Security](#runtime-security)
6. [Monitoring & Incident Response](#monitoring--incident-response)
7. [Compliance & Certifications](#compliance--certifications)
8. [Security Checklist](#security-checklist)

---

## Executive Summary

The BGE-M3 Embedding Service implements defense-in-depth security for enterprise deployment in air-gapped, DMZ environments requiring Isolation FLT department approval.

### Security Highlights

- ✅ **Minimal Attack Surface**: Distroless base image with ~95% reduction vs. standard Python images
- ✅ **Zero Trust**: No shell, no package manager, non-root execution
- ✅ **Supply Chain Security**: Pinned dependencies, SBOM generation, vulnerability scanning
- ✅ **Runtime Hardening**: Read-only filesystem, seccomp, AppArmor, capability dropping
- ✅ **Air-Gap Ready**: Complete offline deployment capability
- ✅ **Compliance**: ISO 27001, NIST CSF, CIS Docker Benchmark aligned

---

## Security Architecture

### Layered Security Model

```
┌─────────────────────────────────────────────────────────────┐
│                     Application Layer                        │
│  - API Key Authentication                                    │
│  - Rate Limiting (SlowAPI)                                   │
│  - Input Validation & Sanitization                           │
│  - Security Headers (CORS, CSP, HSTS)                        │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│                    Container Layer                           │
│  - Distroless Runtime (no shell/package manager)             │
│  - Non-root User (UID 65532)                                 │
│  - Read-only Filesystem                                      │
│  - Minimal Dependencies (CPU-only inference)                 │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│                    Runtime Security                          │
│  - Seccomp Profile (syscall filtering)                       │
│  - AppArmor Profile (mandatory access control)               │
│  - Capability Dropping (CAP_DROP ALL)                        │
│  - No New Privileges                                         │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│                    Network Layer                             │
│  - Network Policies (K8s)                                    │
│  - Isolated Bridge Network (Docker)                          │
│  - No Inter-Container Communication                          │
│  - Egress Restrictions (Air-gapped)                          │
└─────────────────────────────────────────────────────────────┘
```

### Threat Model

See [THREAT-MODEL.md](./THREAT-MODEL.md) for comprehensive STRIDE analysis.

---

## Security Controls

### 1. Base Image Security

**Control:** Use Google's Distroless Python image
- **Base Image:** `gcr.io/distroless/python3-debian12:nonroot`
- **Attack Surface:** Minimal - contains only Python runtime
- **CVE Count:** Near-zero critical/high vulnerabilities
- **No Shell:** Prevents command injection and reverse shells
- **No Package Manager:** Prevents unauthorized software installation

**Verification:**
```bash
docker run --rm bge-m3-secure:latest /bin/sh
# Should fail: "executable file not found"
```

### 2. Non-Root Execution

**Control:** Run container as unprivileged user (UID 65532)

```dockerfile
USER nonroot:nonroot  # UID/GID: 65532
```

**Verification:**
```bash
docker inspect bge-m3-secure:latest --format='{{.Config.User}}'
# Output: nonroot:nonroot
```

### 3. Read-Only Filesystem

**Control:** Container runs with read-only root filesystem

```yaml
read_only: true
tmpfs:
  - /tmp:noexec,nosuid,size=2G
```

**Benefits:**
- Prevents runtime malware persistence
- Blocks unauthorized file modifications
- Protects against container escape exploits

### 4. Capability Dropping

**Control:** Drop all Linux capabilities

```yaml
cap_drop:
  - ALL
```

**Impact:** Prevents:
- Raw socket access
- System time changes
- Kernel module loading
- Process debugging (ptrace)
- Network configuration changes

### 5. Seccomp Filtering

**Control:** Custom seccomp profile restricts syscalls

**Profile Location:** `config/seccomp-profile.json`

**Blocked Syscalls (examples):**
- `reboot`, `swapon`, `swapoff` - System control
- `create_module`, `delete_module` - Kernel modules
- `mount`, `umount` - Filesystem mounting
- `ptrace` - Process debugging

**Allowed:** Only essential syscalls for Python + network I/O

### 6. AppArmor Mandatory Access Control

**Control:** AppArmor profile restricts file/network access

**Profile Location:** `config/apparmor-profile`

**Restrictions:**
- No execution of binaries (except Python)
- No access to `/etc/shadow`, `/root`
- No mount operations
- No capability escalation

**Installation:**
```bash
sudo cp config/apparmor-profile /etc/apparmor.d/bge-m3-embedding
sudo apparmor_parser -r -W /etc/apparmor.d/bge-m3-embedding
```

### 7. API Security

#### 7.1 Authentication

**Control:** API Key-based authentication

```bash
curl -X POST http://localhost:8000/embed \
  -H "X-API-Key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"texts":["test"]}'
```

**Key Generation:**
```bash
openssl rand -base64 32
```

**Environment Variable:**
```bash
export API_KEY="your-secure-random-key"
```

#### 7.2 Rate Limiting

**Control:** SlowAPI rate limiting (default: 60 requests/minute per IP)

```python
RATE_LIMIT_PER_MINUTE=60
```

**Protection Against:**
- Denial of Service (DoS) attacks
- Brute-force API key attacks
- Resource exhaustion

#### 7.3 Input Validation

**Control:** Pydantic request validation

**Enforced Limits:**
- Max batch size: 32 texts
- Max text length: 32,768 characters (~8192 tokens)
- No empty strings
- Type checking on all inputs

#### 7.4 Security Headers

**Implemented Headers:**
```http
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
X-XSS-Protection: 1; mode=block
Strict-Transport-Security: max-age=31536000; includeSubDomains
Content-Security-Policy: default-src 'none'
Referrer-Policy: no-referrer
```

### 8. Logging Security

**Control:** Logging without PII

**Practices:**
- No request bodies in logs
- No API keys in logs
- IP addresses hashed or truncated
- Structured logging (JSON format available)
- Log rotation (max 3 files × 10MB)

**Example:**
```python
logger.info(f"Request: {request.method} {request.url.path}")
# NOT logged: request body, headers with keys
```

### 9. Dependency Security

**Control:** Pinned versions with vulnerability scanning

**Requirements:**
- All versions pinned in `requirements.txt`
- Hash verification supported (`uv pip compile --generate-hashes`)
- Regular updates via Dependabot/Renovate
- Automated vulnerability scanning (Trivy)

**Scanning:**
```bash
./scripts/security-scan.sh
```

### 10. Supply Chain Security

**Control:** Software Bill of Materials (SBOM) generation

**Formats:**
- CycloneDX JSON
- SPDX JSON

**Generation:**
```bash
trivy image --format cyclonedx --output sbom.json bge-m3-secure:latest
```

**Verification:**
- SHA256 checksums for all model files
- GPG signature verification (where available)
- Reproducible builds

---

## Deployment Security

### Docker Deployment

**Secure Deployment Command:**
```bash
docker run -d \
  --name bge-m3-secure \
  --read-only \
  --security-opt=no-new-privileges:true \
  --security-opt=apparmor=bge-m3-embedding \
  --security-opt=seccomp=./config/seccomp-profile.json \
  --cap-drop=ALL \
  --tmpfs /tmp:noexec,nosuid,size=2G \
  --memory=8g \
  --cpus=4.0 \
  --pids-limit=200 \
  -p 8000:8000 \
  -e API_KEY="$(openssl rand -base64 32)" \
  bge-m3-secure:latest
```

### Docker Compose Deployment

**Usage:**
```bash
# Set API key
export API_KEY="$(openssl rand -base64 32)"

# Deploy
docker-compose -f docker-compose.secure.yml up -d

# Verify
docker-compose -f docker-compose.secure.yml ps
curl http://localhost:8000/health
```

### Kubernetes Deployment

See `config/network-policy.yaml` for:
- Pod Security Standards (restricted)
- Network Policies (zero-trust)
- Security Contexts
- Resource Limits
- Service Account (minimal permissions)

---

## Runtime Security

### Health Monitoring

**Health Check Endpoint:**
```bash
curl http://localhost:8000/health
```

**Response:**
```json
{
  "status": "healthy",
  "model_loaded": true,
  "version": "1.0.0"
}
```

### Metrics & Observability

**Prometheus Metrics:**
```bash
curl http://localhost:8000/metrics
```

**Available Metrics:**
- `bge_m3_requests_total` - Total requests
- `bge_m3_request_duration_seconds` - Latency histogram
- `bge_m3_embeddings_total` - Embeddings generated
- `bge_m3_errors_total` - Error count by type

### Security Scanning (Production)

**Continuous Scanning:**
```bash
# Weekly vulnerability scan
0 2 * * 0 /path/to/security-scan.sh

# Daily health check
0 * * * * /path/to/pre-deployment-check.sh
```

**Alert on:**
- New CRITICAL vulnerabilities
- Failed health checks
- Container restarts (unexpected)
- High error rates

---

## Monitoring & Incident Response

### Security Events to Monitor

1. **Authentication Failures**
   - Failed API key attempts
   - Rate limit violations

2. **Anomalous Behavior**
   - Unusual request patterns
   - Large batch sizes
   - High error rates

3. **System Events**
   - Container restarts
   - OOM (Out of Memory) kills
   - Health check failures

### Incident Response Runbook

#### 1. Suspected Compromise

```bash
# Immediately isolate container
docker network disconnect bge-m3-network bge-m3-embedding-service

# Capture logs
docker logs bge-m3-embedding-service > incident-$(date +%Y%m%d-%H%M%S).log

# Capture container state
docker inspect bge-m3-embedding-service > container-state.json

# Stop and remove
docker stop bge-m3-embedding-service
docker rm bge-m3-embedding-service

# Deploy fresh instance
docker-compose -f docker-compose.secure.yml up -d
```

#### 2. API Key Compromise

```bash
# Generate new API key
export NEW_API_KEY="$(openssl rand -base64 32)"

# Update and restart
docker-compose -f docker-compose.secure.yml down
API_KEY="$NEW_API_KEY" docker-compose -f docker-compose.secure.yml up -d

# Invalidate old key (if using key rotation system)
```

#### 3. DoS Attack

```bash
# Identify attacking IPs from logs
docker logs bge-m3-embedding-service | grep "rate limit" | awk '{print $X}'

# Block at firewall level
sudo iptables -A INPUT -s ATTACKER_IP -j DROP

# Increase rate limiting (temporarily)
# Edit .env: RATE_LIMIT_PER_MINUTE=30
docker-compose -f docker-compose.secure.yml restart
```

---

## Compliance & Certifications

### ISO 27001 Alignment

**Controls Implemented:**
- A.9.2 User Access Management → API Key Authentication
- A.12.6 Technical Vulnerability Management → Automated Scanning
- A.14.2 Security in Development → Secure SDLC
- A.18.1 Privacy → No PII Logging

### NIST Cybersecurity Framework

**Functions:**
- **Identify:** Asset inventory, SBOM
- **Protect:** Access controls, encryption at rest
- **Detect:** Logging, monitoring, health checks
- **Respond:** Incident response runbook
- **Recover:** Automated restarts, backup/restore

### CIS Docker Benchmark

**Compliance Score:** 95%+ (target)

**Key Controls:**
- 4.1: Non-root user ✅
- 4.5: Content trust (recommended) ⚠️
- 4.6: Health check ✅
- 5.1: AppArmor profile ✅
- 5.2: SELinux/seccomp ✅
- 5.3: Linux kernel capabilities ✅

**Verification:**
```bash
docker run --rm --net host --pid host --userns host --cap-add audit_control \
  -v /var/lib:/var/lib:ro -v /var/run/docker.sock:/var/run/docker.sock:ro \
  docker/docker-bench-security
```

### FLT Isolation Department Requirements

See [FLT-COMPLIANCE.md](./FLT-COMPLIANCE.md) for detailed compliance documentation.

**Status:**
- ✅ Air-gap deployment capability
- ✅ Antivirus scan compatibility
- ✅ Binary file justification
- ✅ No internet connectivity required
- ✅ Audit trail & logging
- ⏳ FLT approval pending

---

## Security Checklist

### Pre-Deployment

- [ ] Run vulnerability scan: `./scripts/security-scan.sh`
- [ ] Run pre-deployment check: `./scripts/pre-deployment-check.sh`
- [ ] Verify no CRITICAL vulnerabilities in SBOM
- [ ] Generate unique API key: `openssl rand -base64 32`
- [ ] Review and update `.env` file
- [ ] Install AppArmor profile (if using)
- [ ] Verify seccomp profile is accessible
- [ ] Test read-only filesystem compatibility
- [ ] Verify model file integrity (checksums)
- [ ] Review container logs configuration
- [ ] Set up monitoring & alerting
- [ ] Document deployment architecture
- [ ] Conduct security review with team

### Post-Deployment

- [ ] Verify container is running: `docker ps`
- [ ] Check health endpoint: `curl http://localhost:8000/health`
- [ ] Test authentication: Verify API key required
- [ ] Test rate limiting: Send rapid requests
- [ ] Verify non-root execution: `docker exec <container> whoami`
- [ ] Check security options: `docker inspect <container>`
- [ ] Monitor resource usage: `docker stats`
- [ ] Review logs for errors: `docker logs <container>`
- [ ] Test inference: Send sample embedding request
- [ ] Verify metrics endpoint: `curl http://localhost:8000/metrics`
- [ ] Schedule periodic vulnerability scans
- [ ] Document any issues or deviations

### Ongoing Maintenance

- [ ] Weekly vulnerability scans
- [ ] Monthly dependency updates
- [ ] Quarterly security audits
- [ ] Annual penetration testing
- [ ] Log review (daily/weekly)
- [ ] Incident response drill (quarterly)
- [ ] Update security documentation
- [ ] Review access controls

---

## Contact & Support

**Security Team:** security@example.com
**Incident Reporting:** incidents@example.com
**Documentation:** https://github.com/your-org/bge-m3-dockerization

---

## Appendix

### A. Glossary

- **AppArmor:** Linux kernel security module for mandatory access control
- **Distroless:** Minimal container image with only runtime dependencies
- **SBOM:** Software Bill of Materials - inventory of software components
- **Seccomp:** Linux kernel feature for syscall filtering
- **CVE:** Common Vulnerabilities and Exposures
- **CIS:** Center for Internet Security

### B. References

- [Docker Security Best Practices](https://docs.docker.com/engine/security/)
- [OWASP Docker Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [Trivy Documentation](https://aquasecurity.github.io/trivy/)

### C. Version History

| Version | Date       | Changes                          |
|---------|------------|----------------------------------|
| 1.0.0   | 2025-11-15 | Initial security documentation   |

---

*This document is confidential and intended for internal use only.*
