# BGE-M3 Secure Docker Deployment

Production BGE-M3 embedding model with maximum security + performance for air-gapped DMZ environments.

## Quick Start

```bash
# Build
docker build -f docker/Dockerfile.secure -t bge-m3:latest .

# Deploy
export API_KEY="$(openssl rand -base64 32)"
docker-compose -f docker-compose.secure.yml up -d

# Test
curl -X POST http://localhost:8000/embed \
  -H "X-API-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"texts": ["test"], "return_dense": true}'
```

## Security Features

- **Distroless base** (95% attack surface reduction)
- **Non-root** (UID 65532)
- **Read-only filesystem**
- **Seccomp + AppArmor**
- **CAP_DROP ALL**
- **API key auth + rate limiting**
- **ONNX CPU optimization** (2-4x faster)

## Air-Gap Deployment

```bash
# Prepare offline bundle (internet-connected machine)
./scripts/offline-build.sh prepare

# Transfer bundle to air-gapped environment

# Build offline
./scripts/offline-build.sh build
docker-compose -f docker-compose.secure.yml up -d
```

## Project Structure

```
├── app/                     # FastAPI + BGE-M3
├── docker/                  # Dockerfile + configs
├── config/                  # seccomp, apparmor
├── scripts/                 # security-scan, offline-build
├── security/                # AV whitelist, checksums
├── docs/                    # Security docs
└── docker-compose.secure.yml
```

## Security Scan

```bash
./scripts/security-scan.sh    # SBOM, CVE scan, CIS check
./scripts/pre-deployment-check.sh  # Validation
```

## Monitoring

- Health: `curl http://localhost:8000/health`
- Metrics: `curl http://localhost:8000/metrics`
- Logs: `docker-compose logs -f`

## Docs

- [SECURITY.md](docs/SECURITY.md) - Security controls
- [FLT-COMPLIANCE.md](docs/FLT-COMPLIANCE.md) - FLT approval docs
- [av-whitelist.txt](security/av-whitelist.txt) - Antivirus config

## Requirements

- Docker 20.10+
- 8GB RAM, 4 CPUs
- Linux kernel 4.4+

## License

MIT License
