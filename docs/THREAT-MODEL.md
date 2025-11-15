# BGE-M3 Embedding Service - Threat Model

**Version:** 1.0.0
**Date:** 2025-11-15
**Framework:** STRIDE (Microsoft Threat Modeling)
**Scope:** BGE-M3 Embedding Service in Air-Gapped DMZ Environment

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [System Overview](#system-overview)
3. [STRIDE Analysis](#stride-analysis)
4. [Attack Vectors](#attack-vectors)
5. [Mitigations](#mitigations)
6. [Residual Risks](#residual-risks)

---

## Executive Summary

This threat model analyzes the BGE-M3 Embedding Service deployment using the STRIDE methodology. The service operates in a high-security air-gapped DMZ environment with stringent isolation requirements.

**Risk Level:** Medium (Post-Mitigation)
- High-value target (ML model serving)
- Air-gapped deployment reduces remote attack surface
- Comprehensive security controls implemented

---

## System Overview

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     DMZ Environment (Air-Gapped)             │
│                                                              │
│  ┌──────────────┐         ┌──────────────────────┐          │
│  │   Client     │─────────│  BGE-M3 Container    │          │
│  │ Application  │  HTTP   │                      │          │
│  │              │         │  ┌────────────────┐  │          │
│  └──────────────┘         │  │  FastAPI App   │  │          │
│                           │  │  (Port 8000)   │  │          │
│                           │  ├────────────────┤  │          │
│                           │  │  BGE-M3 Model  │  │          │
│                           │  │  (ONNX/CPU)    │  │          │
│                           │  └────────────────┘  │          │
│                           │                      │          │
│                           │  Distroless Runtime  │          │
│                           │  Non-root User       │          │
│                           │  Read-only FS        │          │
│                           └──────────────────────┘          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Trust Boundaries

1. **External → DMZ:** No inbound connections (air-gapped)
2. **Client → API:** API key authentication required
3. **Container → Host:** Isolated via Docker security controls
4. **Process → Kernel:** Restricted via seccomp, AppArmor, capabilities

### Assets

| Asset | Description | Confidentiality | Integrity | Availability |
|-------|-------------|-----------------|-----------|--------------|
| BGE-M3 Model | ~4.59 GB embedding model | High | High | High |
| API Keys | Authentication credentials | Critical | High | Medium |
| Embedding Data | Generated embeddings | Medium | High | High |
| Container Runtime | Docker container | Low | Critical | High |
| Application Code | FastAPI service | Medium | High | High |

---

## STRIDE Analysis

### S - Spoofing Identity

#### Threat 1: API Key Theft/Spoofing

**Description:** Attacker obtains or guesses valid API key to impersonate authorized client.

**Impact:** Unauthorized access to embedding service
- **Confidentiality:** High (access to embeddings)
- **Integrity:** Medium (can submit malicious inputs)
- **Availability:** Medium (resource exhaustion)

**Likelihood:** Low (with proper key management)

**Mitigations:**
- ✅ Strong API key generation (cryptographically random, 256-bit)
- ✅ API keys stored as secrets (not in environment variables in production)
- ✅ Rate limiting prevents brute-force attacks
- ✅ Logging of authentication failures
- ⚠️ Key rotation not automated (manual process)

**Residual Risk:** Low

---

#### Threat 2: Container Identity Spoofing

**Description:** Malicious container pretends to be BGE-M3 service.

**Impact:** Clients connect to rogue service, exposing data.

**Likelihood:** Very Low (air-gapped, isolated network)

**Mitigations:**
- ✅ Signed container images (Docker Content Trust recommended)
- ✅ Image digest pinning
- ✅ Network isolation (dedicated bridge network)
- ✅ TLS certificate verification (if using HTTPS)

**Residual Risk:** Very Low

---

### T - Tampering

#### Threat 3: Model File Tampering

**Description:** Attacker modifies model files to inject backdoor or corrupt embeddings.

**Impact:**
- **Integrity:** Critical (corrupted model outputs)
- **Confidentiality:** High (backdoored model could exfiltrate data)

**Likelihood:** Low (read-only filesystem, checksums)

**Mitigations:**
- ✅ Read-only filesystem prevents runtime modifications
- ✅ SHA256 checksums for all model files
- ✅ Model files copied during build (immutable)
- ✅ Models mounted read-only (if external volume)
- ⚠️ No digital signatures on model files (Hugging Face limitation)

**Residual Risk:** Low

---

#### Threat 4: Application Code Tampering

**Description:** Attacker modifies application code at runtime.

**Impact:** Arbitrary code execution, data exfiltration.

**Likelihood:** Very Low (distroless, read-only FS)

**Mitigations:**
- ✅ Distroless base image (no shell, no package manager)
- ✅ Read-only filesystem
- ✅ Non-root user (cannot modify system files)
- ✅ AppArmor profile prevents file write operations
- ✅ Code compiled to bytecode only (no .py files in final image)

**Residual Risk:** Very Low

---

#### Threat 5: Dependency Tampering (Supply Chain Attack)

**Description:** Malicious Python package or base image injected during build.

**Impact:** Complete system compromise.

**Likelihood:** Low (pinned versions, hash verification)

**Mitigations:**
- ✅ All dependencies pinned to specific versions
- ✅ UV package manager with hash verification support
- ✅ Base images pinned by digest (SHA256)
- ✅ SBOM generation for audit trail
- ✅ Vulnerability scanning of all dependencies
- ✅ Offline build capability (manual review possible)

**Residual Risk:** Low

---

### R - Repudiation

#### Threat 6: Denial of API Usage

**Description:** User denies making API requests (no audit trail).

**Impact:** Inability to trace malicious activity or misuse.

**Likelihood:** Medium (if logging insufficient)

**Mitigations:**
- ✅ Comprehensive request logging (timestamp, endpoint, status)
- ✅ Prometheus metrics (requests per endpoint)
- ⚠️ IP addresses not logged by default (privacy)
- ⚠️ No request ID correlation across services
- ❌ No cryptographic non-repudiation (digital signatures)

**Residual Risk:** Medium

**Recommendations:**
- Implement request ID generation and propagation
- Consider API request signing for critical operations
- Centralized log aggregation (ELK, Splunk)

---

### I - Information Disclosure

#### Threat 7: Embedding Data Leakage

**Description:** Unauthorized access to generated embeddings reveals sensitive information.

**Impact:**
- **Confidentiality:** High (embeddings may encode sensitive text)

**Likelihood:** Low (API key required, rate limited)

**Mitigations:**
- ✅ API key authentication
- ✅ No embeddings stored persistently
- ✅ HTTPS recommended for transport encryption
- ✅ Memory cleared on container restart
- ⚠️ No field-level encryption of embeddings
- ⚠️ No data loss prevention (DLP) on outputs

**Residual Risk:** Medium (depends on client's security)

**Recommendations:**
- Enforce TLS 1.3 for all API communications
- Implement output filtering/sanitization if needed
- Client-side encryption of embeddings

---

#### Threat 8: Model Architecture Leakage

**Description:** Attacker extracts model architecture or weights through API.

**Impact:**
- **Confidentiality:** Medium (model is publicly available, but customizations could leak)

**Likelihood:** Low (model inference only, no gradient access)

**Mitigations:**
- ✅ API provides only embedding outputs (black box)
- ✅ Rate limiting prevents large-scale model extraction
- ✅ No model download endpoint
- ✅ No gradient information exposed
- ⚠️ Model inversion attacks theoretically possible

**Residual Risk:** Low

---

#### Threat 9: Error Message Information Disclosure

**Description:** Detailed error messages reveal system internals.

**Impact:** Attacker gains knowledge of system configuration.

**Likelihood:** Medium (common vulnerability)

**Mitigations:**
- ✅ Generic error messages to clients ("Internal server error")
- ✅ Detailed errors logged server-side only
- ✅ No stack traces in API responses
- ✅ No version information in headers (Server header removed)

**Residual Risk:** Low

---

#### Threat 10: Log Data Exposure

**Description:** Logs contain sensitive information (API keys, PII).

**Impact:** Credential theft, privacy violation.

**Likelihood:** Low (logging controls implemented)

**Mitigations:**
- ✅ No API keys logged
- ✅ No request bodies logged
- ✅ IP addresses hashed or truncated (configurable)
- ✅ Access logs disabled by default
- ✅ Log rotation and size limits
- ⚠️ Logs stored in plain text (not encrypted at rest)

**Residual Risk:** Low

**Recommendations:**
- Encrypt log files at rest
- Centralized log management with access controls

---

### D - Denial of Service

#### Threat 11: Resource Exhaustion (CPU/Memory)

**Description:** Attacker sends large batches or very long texts to exhaust resources.

**Impact:** Service unavailability for legitimate users.

**Likelihood:** Medium (without rate limiting)

**Mitigations:**
- ✅ Rate limiting (60 requests/minute per IP)
- ✅ Max batch size enforced (32 texts)
- ✅ Max text length enforced (8192 tokens ≈ 32,768 chars)
- ✅ Docker memory limits (8GB)
- ✅ Docker CPU limits (4 cores)
- ✅ PID limits (200 processes)
- ✅ Request timeout (configurable)

**Residual Risk:** Low

---

#### Threat 12: Container Crash (Availability)

**Description:** Malformed input crashes the application or model.

**Impact:** Service downtime.

**Likelihood:** Low (input validation)

**Mitigations:**
- ✅ Input validation (Pydantic models)
- ✅ Exception handling (all endpoints)
- ✅ Health checks (automatic restart on failure)
- ✅ Restart policy (unless-stopped)
- ⚠️ No circuit breaker pattern

**Residual Risk:** Low

---

#### Threat 13: Fork Bomb / Process Exhaustion

**Description:** Attacker spawns unlimited processes to exhaust system.

**Likelihood:** Very Low (PID limits)

**Mitigations:**
- ✅ PID limits (200 processes)
- ✅ No shell access
- ✅ Non-root user (cannot modify ulimits)

**Residual Risk:** Very Low

---

### E - Elevation of Privilege

#### Threat 14: Container Escape

**Description:** Attacker breaks out of container to access host system.

**Impact:** **Critical** - Full host compromise.

**Likelihood:** Very Low (multiple security layers)

**Mitigations:**
- ✅ Distroless image (no tools for exploitation)
- ✅ Non-root user (UID 65532)
- ✅ Read-only filesystem
- ✅ No new privileges flag
- ✅ All capabilities dropped
- ✅ Seccomp profile (blocks dangerous syscalls)
- ✅ AppArmor profile (MAC)
- ✅ Latest kernel recommended (container escape mitigations)

**Residual Risk:** Very Low

---

#### Threat 15: Privilege Escalation via Python/Dependencies

**Description:** Vulnerability in Python or dependency allows privilege escalation.

**Impact:** Container compromise.

**Likelihood:** Low (vulnerability scanning)

**Mitigations:**
- ✅ Regular vulnerability scanning (Trivy)
- ✅ Minimal dependencies (reduce attack surface)
- ✅ CPU-only PyTorch (no GPU driver vulnerabilities)
- ✅ Non-root user (limits impact)
- ⚠️ Python CVEs addressed via updates (manual process)

**Residual Risk:** Low

**Recommendations:**
- Automated dependency updates with testing
- Subscribe to CVE feeds for Python, PyTorch, FastAPI

---

#### Threat 16: API Key to Full System Access

**Description:** Valid API key allows escalation beyond intended access.

**Impact:** Lateral movement, data access.

**Likelihood:** Very Low (API is isolated)

**Mitigations:**
- ✅ API provides only embedding functionality (no admin endpoints)
- ✅ No file upload/download capabilities
- ✅ No command execution endpoints
- ✅ Principle of least privilege

**Residual Risk:** Very Low

---

## Attack Vectors

### Attack Vector 1: Malicious Input Injection

**Attack Path:**
1. Attacker obtains valid API key
2. Sends crafted input to trigger buffer overflow or code execution
3. Exploits vulnerability in model inference or text processing

**Mitigations:**
- Input validation (length, type)
- Sandboxed model execution
- Regular security updates

**Residual Risk:** Low

---

### Attack Vector 2: Dependency Vulnerability Exploitation

**Attack Path:**
1. CVE published for FastAPI, PyTorch, or other dependency
2. Attacker crafts exploit
3. Gains code execution in container

**Mitigations:**
- Automated vulnerability scanning
- Rapid patching process
- Defense in depth (even with code execution, limited damage due to containerization)

**Residual Risk:** Low

---

### Attack Vector 3: Supply Chain Compromise

**Attack Path:**
1. Malicious package introduced in dependency tree
2. Downloaded during build process
3. Backdoor included in final image

**Mitigations:**
- Hash verification
- SBOM generation and review
- Offline build capability
- Multi-person review for production builds

**Residual Risk:** Low

---

### Attack Vector 4: Side-Channel Attacks

**Attack Path:**
1. Attacker uses API to infer sensitive information via timing/errors
2. Model extraction through repeated queries
3. Privacy violation

**Mitigations:**
- Rate limiting
- Constant-time operations where possible
- Noise injection (future consideration)

**Residual Risk:** Medium

---

## Mitigations Summary

| Threat Category | Mitigations Implemented | Effectiveness |
|----------------|-------------------------|---------------|
| Spoofing | API keys, image signing | High |
| Tampering | Read-only FS, checksums, distroless | Very High |
| Repudiation | Logging, metrics | Medium |
| Information Disclosure | Generic errors, no PII logging, TLS | High |
| Denial of Service | Rate limiting, resource limits, input validation | High |
| Elevation of Privilege | Non-root, seccomp, AppArmor, cap drop | Very High |

---

## Residual Risks

### High Priority (Address in Next Iteration)

1. **Automated Key Rotation**
   - Current: Manual API key updates
   - Recommendation: Implement automatic key rotation with grace period

2. **Request Traceability**
   - Current: Limited correlation across services
   - Recommendation: Implement distributed tracing (OpenTelemetry)

3. **Encrypted Logs**
   - Current: Logs in plain text
   - Recommendation: Encrypt logs at rest

### Medium Priority

1. **Model Extraction Defense**
   - Current: Rate limiting only
   - Recommendation: Implement watermarking or usage analytics

2. **Field-Level Encryption**
   - Current: Transport encryption only
   - Recommendation: Encrypt embeddings at rest (client-side)

### Low Priority (Accept Risk)

1. **No Digital Signatures on Model**
   - Risk: Model tampering (mitigated by checksums)
   - Justification: Upstream (Hugging Face) limitation

2. **No Non-Repudiation**
   - Risk: Users can deny actions
   - Justification: Not critical for embedding service

---

## Assumptions

1. **Air-Gapped Environment:** No internet connectivity prevents remote attacks
2. **Trusted Internal Network:** Clients within DMZ are semi-trusted
3. **Physical Security:** Host system is physically secured
4. **Security Updates:** Regular patching process in place
5. **Monitoring:** Security team monitors logs and alerts

---

## Out of Scope

- DDoS attacks (handled at network perimeter)
- Physical attacks (secured data center)
- Social engineering (security awareness training)
- Insider threats (handled by access controls and monitoring)

---

## Recommendations

### Immediate (Pre-Deployment)

1. ✅ Generate strong API key: `openssl rand -base64 32`
2. ✅ Run security scan: `./scripts/security-scan.sh`
3. ✅ Review SBOM for high-risk dependencies
4. ✅ Enable TLS for API communication
5. ✅ Configure centralized logging

### Short-Term (1-3 Months)

1. Implement API key rotation
2. Add distributed tracing
3. Encrypt logs at rest
4. Conduct penetration testing
5. Implement alerting for security events

### Long-Term (6-12 Months)

1. Automate security patching
2. Implement SIEM integration
3. Add model watermarking
4. Conduct red team exercise
5. Achieve security certifications

---

## Review & Updates

This threat model should be reviewed:
- **Quarterly:** General review and updates
- **On major changes:** Architecture, dependencies, deployment
- **After incidents:** Update based on lessons learned
- **Annually:** Comprehensive threat modeling workshop

**Next Review:** 2026-02-15

---

## Sign-Off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Security Architect | TBD | 2025-11-15 | |
| Development Lead | TBD | 2025-11-15 | |
| FLT Security | TBD | Pending | |

---

*This document is confidential and intended for security review purposes only.*
