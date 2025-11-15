# BGE-M3 Secure Deployment for Air-Gapped Environments

[![Security: Hardened](https://img.shields.io/badge/security-hardened-green.svg)](docs/SECURITY.md)
[![Compliance: FLT](https://img.shields.io/badge/compliance-FLT%20pending-yellow.svg)](docs/FLT-COMPLIANCE.md)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Production-ready deployment of the **BAAI/bge-m3** multi-modal embedding model with enterprise-grade security hardening for air-gapped, DMZ environments requiring Isolation FLT department approval.

---

## 🎯 Overview

This repository provides a **security-hardened**, **production-ready** deployment of the BGE-M3 embedding model designed for:

- **Air-gapped DMZ environments** (zero internet connectivity)
- **Isolation FLT department** security requirements
- **Enterprise antivirus** compatibility (CrowdStrike, Defender, Symantec, etc.)
- **CPU-only inference** (no GPU dependencies)
- **Compliance** with ISO 27001, NIST, CIS benchmarks

### Key Features

✅ **Security Hardening**
- Distroless base image (~95% attack surface reduction)
- Non-root user execution (UID 65532)
- Read-only filesystem support
- Seccomp + AppArmor profiles
- Zero capabilities (CAP_DROP ALL)

✅ **Air-Gap Ready**
- Complete offline build capability
- Pre-packaged models and dependencies
- No runtime internet access required
- Integrity verification via SHA256 checksums

✅ **Enterprise Security**
- API key authentication
- Rate limiting (DDoS protection)
- Security headers (HSTS, CSP, etc.)
- Audit logging (no PII)
- Prometheus metrics

✅ **Compliance**
- SBOM generation (CycloneDX, SPDX)
- Vulnerability scanning (Trivy)
- CIS Docker Benchmark aligned
- Antivirus whitelisting guide

---

## 📋 Quick Start

### Prerequisites

- Docker 20.10+ or Kubernetes 1.25+
- Linux host (kernel 4.4+)
- 8GB RAM minimum
- 4 CPU cores minimum
- 10GB disk space (models + container)

### Build and Deploy

```bash
# 1. Build security-hardened image
docker build -f docker/Dockerfile.secure -t bge-m3-secure:latest .

# 2. Run security scan
./scripts/security-scan.sh

# 3. Generate API key and deploy
export API_KEY="$(openssl rand -base64 32)"
docker-compose -f docker-compose.secure.yml up -d

# 4. Test API
curl -X POST http://localhost:8000/embed \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d '{"texts": ["Hello, world!"], "return_dense": true}'
```

---

## 📁 Project Structure

```
bge-m3-dockerization/
├── app/                          # FastAPI application
│   ├── main.py                   # API endpoints
│   ├── models.py                 # Pydantic models
│   └── embedding_service.py      # BGE-M3 wrapper
├── docker/                       # Docker configuration
│   ├── Dockerfile.secure         # Security-hardened Dockerfile
│   └── .dockerignore             # Build context exclusions
├── config/                       # Security profiles
│   ├── seccomp-profile.json      # Syscall filtering
│   ├── apparmor-profile          # Mandatory access control
│   └── network-policy.yaml       # Kubernetes network policy
├── scripts/                      # Deployment scripts
│   ├── security-scan.sh          # Vulnerability scanning
│   ├── pre-deployment-check.sh   # Pre-deployment validation
│   └── offline-build.sh          # Air-gapped build
├── security/                     # Security documentation
│   ├── av-whitelist.txt          # Antivirus whitelist guide
│   └── checksums.sha256.template # File integrity checksums
├── docs/                         # Documentation
│   ├── SECURITY.md               # Security documentation
│   ├── THREAT-MODEL.md           # STRIDE analysis
│   └── FLT-COMPLIANCE.md         # FLT compliance package
├── docker-compose.secure.yml     # Production deployment
├── requirements.txt              # Python dependencies
└── .env.example                  # Environment template
```

---

## 🔒 Security

This deployment implements **defense-in-depth** security:

| Layer | Controls |
|-------|----------|
| **Application** | API key auth, rate limiting, input validation, security headers |
| **Container** | Distroless base, non-root user, read-only FS, minimal deps |
| **Runtime** | Seccomp, AppArmor, capability dropping, no new privileges |
| **Network** | Network policies, isolated network, no egress |

**Security Score:** 95%+ CIS Docker Benchmark compliance

See [docs/SECURITY.md](docs/SECURITY.md) for details.

---

## 🌐 Air-Gapped Deployment

Complete offline deployment in 3 steps:

```bash
# Step 1: Prepare (internet-connected machine)
./scripts/offline-build.sh prepare
# Creates: bge-m3-offline-bundle-YYYYMMDD.tar.gz (~7 GB)

# Step 2: Transfer to air-gapped environment (USB/CD)

# Step 3: Build and deploy (air-gapped machine)
tar -xzf bge-m3-offline-bundle-*.tar.gz
cd bge-m3-offline-bundle
./scripts/offline-build.sh build
docker-compose -f docker-compose.secure.yml up -d
```

---

## 📊 Monitoring

- **Health:** `curl http://localhost:8000/health`
- **Metrics:** `curl http://localhost:8000/metrics` (Prometheus format)
- **Logs:** `docker-compose logs -f`

---

## 📚 Documentation

- **[SECURITY.md](docs/SECURITY.md)** - Comprehensive security documentation
- **[THREAT-MODEL.md](docs/THREAT-MODEL.md)** - STRIDE threat analysis
- **[FLT-COMPLIANCE.md](docs/FLT-COMPLIANCE.md)** - FLT compliance package
- **[av-whitelist.txt](security/av-whitelist.txt)** - Antivirus whitelist guide

---

## 🤝 Support

- **Issues:** Report via GitHub Issues
- **Security:** security@example.com (do not open public issues for vulnerabilities)
- **Documentation:** See `docs/` directory

---

## 📄 License

MIT License - See LICENSE file

**Third-Party:**
- BGE-M3 Model: MIT License (BAAI)
- FastAPI: MIT License
- ONNX Runtime: MIT License

---

<div align="center">

**Built with 🔒 Security in Mind**

[Documentation](docs/) • [Security](docs/SECURITY.md) • [Report Bug](https://github.com/your-org/bge-m3-dockerization/issues)

</div>