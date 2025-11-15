# BGE-M3 Security Documentation

## Security Architecture

```
Application Layer    → API key auth, rate limiting, input validation
Container Layer      → Distroless, non-root (UID 65532), read-only FS
Runtime Security     → Seccomp, AppArmor, CAP_DROP ALL
Network Layer        → Isolated network, no egress
```

## Security Controls

### 1. Container Hardening

| Control | Implementation |
|---------|---------------|
| Base Image | `gcr.io/distroless/python3-debian12:nonroot` |
| User | Non-root UID 65532 |
| Filesystem | Read-only with tmpfs |
| Capabilities | ALL dropped |
| Seccomp | Custom profile (config/seccomp-profile.json) |
| AppArmor | Custom profile (config/apparmor-profile) |

### 2. Application Security

**Authentication:**
```bash
export API_KEY="$(openssl rand -base64 32)"
curl -H "X-API-Key: $API_KEY" http://localhost:8000/embed
```

**Rate Limiting:** 60 requests/minute per IP (configurable)

**Input Validation:**
- Max 32 texts per batch
- Max 8192 tokens per text
- Type checking via Pydantic

**Security Headers:**
- HSTS, CSP, X-Frame-Options, X-Content-Type-Options
- No server header disclosure

### 3. Deployment Security

**Docker Run:**
```bash
docker run -d \
  --read-only \
  --security-opt=no-new-privileges:true \
  --cap-drop=ALL \
  --tmpfs /tmp:noexec,nosuid,size=2G \
  --memory=8g \
  --cpus=4.0 \
  -e API_KEY="$(openssl rand -base64 32)" \
  bge-m3:latest
```

**Docker Compose:** See `docker-compose.secure.yml` for production config

### 4. Security Scanning

```bash
# Vulnerability scan
./scripts/security-scan.sh

# Pre-deployment checks
./scripts/pre-deployment-check.sh

# Manual scans
trivy image --severity CRITICAL,HIGH bge-m3:latest
docker run docker/docker-bench-security
```

## Compliance

**CIS Docker Benchmark:** 95%+ compliance
- 4.1: Non-root user ✓
- 4.6: Health check ✓
- 5.1: AppArmor ✓
- 5.2: Seccomp ✓
- 5.3: Capabilities ✓
- 5.12: Read-only FS ✓

**Supply Chain Security:**
- Pinned dependencies (requirements.txt)
- SBOM generation (CycloneDX, SPDX)
- SHA256 checksums (security/checksums.sha256)
- Zero CRITICAL CVEs target

## Monitoring

**Health Check:**
```bash
curl http://localhost:8000/health
# {"status":"healthy","model_loaded":true}
```

**Prometheus Metrics:**
```bash
curl http://localhost:8000/metrics
# bge_m3_requests_total, bge_m3_request_duration_seconds, etc.
```

**Logs:** No PII, structured JSON format

## Incident Response

**Container Compromise:**
```bash
docker stop <container>
docker logs <container> > incident.log
docker rm <container>
docker-compose up -d  # Deploy fresh
```

**API Key Compromise:**
```bash
export API_KEY="$(openssl rand -base64 32)"
docker-compose restart
```

## Security Checklist

- [ ] Run `./scripts/security-scan.sh` (0 CRITICAL CVEs)
- [ ] Run `./scripts/pre-deployment-check.sh` (all tests pass)
- [ ] Generate unique API key
- [ ] Review `.env` file (no defaults)
- [ ] Verify model checksums
- [ ] Set up monitoring/alerting
- [ ] Review AV whitelist (`security/av-whitelist.txt`)

## References

- [Docker Security](https://docs.docker.com/engine/security/)
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)
- [OWASP Container Security](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)
