# Liberty Container

Open Liberty application container with Jakarta EE 10 and MicroProfile 6.

## Build Requirements

**IMPORTANT:** This container must be built from the repository root, not from this directory.

The Containerfile uses a multi-stage build that:
1. Stage 1 (builder): Compiles the WAR from `sample-app/` using Maven
2. Stage 2 (runtime): Creates a minimal Liberty image with the compiled application

## Build Commands

All commands must be run from the **repository root** (`middleware-automation-platform/`).

### Standard Build

```bash
podman build -t liberty-app:1.0.0 -f containers/liberty/Containerfile .
```

### Build with Version Metadata

```bash
podman build -t liberty-app:1.0.0 \
  --build-arg VERSION=1.0.0 \
  --build-arg GIT_COMMIT=$(git rev-parse --short HEAD) \
  --build-arg BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ") \
  -f containers/liberty/Containerfile .
```

### Build for Docker Hub

```bash
podman build -t docker.io/jconover/liberty-app:1.0.0 \
  -f containers/liberty/Containerfile .
```

## Run

```bash
podman run -d -p 9080:9080 -p 9443:9443 --name liberty liberty-app:1.0.0
```

## Verify

```bash
# Health check
curl http://localhost:9080/health/ready

# Metrics endpoint
curl http://localhost:9080/metrics

# Application
curl http://localhost:9080/sample-app/api/hello
```

## Configuration Files

| File | Purpose |
|------|---------|
| `Containerfile` | Multi-stage build definition |
| `server.xml` | Liberty server configuration |
| `jvm.options` | JVM tuning parameters |

## Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 9080 | HTTP | Application and health endpoints |
| 9443 | HTTPS | Secure application access |

## Health Endpoints

| Endpoint | Purpose |
|----------|---------|
| `/health/ready` | Readiness probe |
| `/health/live` | Liveness probe |
| `/health/started` | Startup probe |

## Why Build from Repository Root?

The Containerfile references paths relative to the repository root:
- `sample-app/pom.xml` - Maven project file
- `sample-app/src/` - Application source code
- `containers/liberty/server.xml` - Liberty configuration

Building from this directory would fail because these paths would not exist in the build context.
