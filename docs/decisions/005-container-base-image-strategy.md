# ADR-005: Container Base Image Strategy

## Status

Accepted

## Date

2026-01-02

## Context

The Middleware Automation Platform requires a container base image strategy for deploying Open Liberty application servers. The container must meet several critical requirements:

1. **Enterprise Readiness**: Must be suitable for production workloads in regulated environments
2. **Security Compliance**: Must support security scanning, CVE patching, and run as non-root
3. **Performance**: Must provide optimal startup time and memory efficiency for Java workloads
4. **Maintainability**: Must be officially supported with predictable update cycles
5. **Size Optimization**: Must minimize image size to reduce registry storage and deployment time
6. **Build Reproducibility**: Must support consistent, repeatable builds across environments

The platform deploys to multiple targets:
- AWS ECS Fargate (container-native, serverless)
- AWS EC2 with Ansible (traditional VM-based)
- Local Kubernetes (3-node Beelink homelab cluster)
- Local Podman (single-machine development)

## Decision

We adopt the following container base image strategy:

### Base Image Selection

```
icr.io/appcafe/open-liberty:kernel-slim-java17-openj9-ubi
```

This image combines:
- **Open Liberty kernel-slim**: Minimal Liberty runtime with on-demand feature installation
- **Java 17**: LTS release with long-term support (until 2029)
- **Eclipse OpenJ9**: IBM's JVM optimized for cloud workloads
- **UBI (Red Hat Universal Base Image)**: Enterprise-grade base with RHEL compatibility

### Multi-Stage Build Pattern

The Containerfile implements a two-stage build:

**Stage 1 - Builder**:
```dockerfile
FROM docker.io/library/maven:3.9-eclipse-temurin-17 AS builder
```
- Compiles the application WAR from source using Maven
- Uses dependency caching for faster rebuilds
- Produces only the compiled artifact for the runtime stage

**Stage 2 - Runtime**:
```dockerfile
FROM icr.io/appcafe/open-liberty:kernel-slim-java17-openj9-ubi AS runtime
```
- Installs only required Liberty features via `features.sh`
- Copies compiled WAR from builder stage
- Configures server with `configure.sh`

### Non-Root Execution

The container runs as UID 1001 (the default non-root user in Open Liberty images):
```dockerfile
USER 1001
```

Root access is used only for installing required system packages (curl for health checks), then immediately dropped.

### Feature Installation Strategy

Liberty features are installed dynamically based on `server.xml` configuration:
```dockerfile
RUN features.sh
```

This ensures only required features are included:
- restfulWS-3.1, jsonb-3.0, cdi-4.0 (Jakarta EE 10)
- mpHealth-4.0, mpMetrics-5.0, mpConfig-3.0 (MicroProfile 6)
- jdbc-4.3, ssl-1.0 (Infrastructure)

## Consequences

### Positive

1. **Smaller Image Size**: kernel-slim starts at ~300MB vs ~600MB for full Liberty image. Final image with features is approximately 450MB.

2. **Faster Startup**: OpenJ9 with class data sharing provides sub-10-second startup times. The kernel-slim variant avoids loading unused features.

3. **Enterprise Support**: UBI base provides:
   - RHEL binary compatibility
   - Regular security updates from Red Hat
   - Certification for OpenShift and enterprise Kubernetes platforms
   - Access to Red Hat's vulnerability database

4. **Security Compliance**:
   - Non-root execution satisfies PCI-DSS and SOC2 requirements
   - UBI images are regularly scanned and patched
   - No hardcoded credentials or secrets in the image
   - Minimal attack surface with kernel-slim variant

5. **Memory Efficiency**: OpenJ9 typically uses 30-50% less memory than HotSpot for equivalent workloads, reducing infrastructure costs in ECS Fargate (billed by memory).

6. **Build Reproducibility**: Multi-stage builds ensure the same source always produces the same artifact, regardless of local Maven cache state.

7. **Layer Caching**: Dockerfile structure optimizes cache hits:
   - Base image layer (rarely changes)
   - System packages layer (rarely changes)
   - Server configuration layer (changes occasionally)
   - Features layer (changes when server.xml changes)
   - Application layer (changes frequently)

### Negative

1. **OpenJ9-Specific Configuration**: JVM options must be OpenJ9-compatible. Options like `-XX:+UseG1GC` (HotSpot-specific) will cause startup failures.

2. **Debugging Complexity**: OpenJ9's memory model differs from HotSpot. Teams familiar with HotSpot tooling may need training on OpenJ9 diagnostics.

3. **Shared Class Cache Limitation**: The OpenJ9 Shared Class Cache (SCC) is disabled (`OPENJ9_SCC=false`) because it can fail in rootless container environments. This slightly increases cold-start time.

4. **UBI Repository Restrictions**: Some packages available in standard RHEL repositories are not in UBI. However, our minimal package requirements (only curl) are satisfied.

5. **Image Pull Time**: First deployment to a new node requires pulling the ~450MB image. Subsequent deployments use cached layers.

### Neutral

1. **IBM Container Registry Dependency**: Images are pulled from `icr.io/appcafe/`. This is IBM's official registry with high availability, but represents an external dependency.

2. **Feature Installation at Build Time**: Features are baked into the image rather than installed at runtime. This increases image size but ensures consistent behavior across deployments.

## Alternatives Considered

### Alternative 1: Full Liberty Image

```
icr.io/appcafe/open-liberty:full-java17-openj9-ubi
```

**Rejected because**:
- Image size approximately 600MB (vs 300MB kernel-slim base)
- Includes all Liberty features regardless of usage
- Longer pull times and increased storage costs
- Larger attack surface with unused components

### Alternative 2: Eclipse Temurin (HotSpot) JDK

```
icr.io/appcafe/open-liberty:kernel-slim-java17-openj9-ubi
                                              ^^^^^^^
# Change to Temurin variant if available, or custom base
```

**Rejected because**:
- Higher memory consumption (30-50% more than OpenJ9)
- Increased ECS Fargate costs (billed by memory)
- HotSpot optimizations (JIT warmup) less beneficial for containerized workloads with frequent restarts
- OpenJ9's InstantOn (when available) provides superior cold-start performance

### Alternative 3: Alpine-Based Image

```
eclipse-temurin:17-jre-alpine + Liberty binaries
```

**Rejected because**:
- Alpine uses musl libc, which has known compatibility issues with some Java libraries
- Not enterprise-supported like UBI
- Requires additional security scanning tooling
- DNS resolution issues in Alpine can affect service discovery
- Limited package availability compared to UBI/RHEL ecosystem

### Alternative 4: Distroless Base

```
gcr.io/distroless/java17 + Liberty binaries
```

**Rejected because**:
- No shell access complicates debugging in production
- Requires custom Liberty integration (no official distroless Liberty image)
- Health check implementation more complex without curl/wget
- Feature installation scripts require shell

### Alternative 5: Custom Base from Scratch

```
FROM scratch
# Build everything from source
```

**Rejected because**:
- Enormous maintenance burden
- No security updates from upstream maintainer
- Requires deep expertise in Java runtime packaging
- Not practical for enterprise environments

### Alternative 6: WebSphere Liberty (Commercial)

```
icr.io/appcafe/websphere-liberty:kernel-slim-java17-openj9-ubi
```

**Considered but not currently needed because**:
- Open Liberty provides all required features
- WebSphere Liberty required for IBM support contracts or specific IBM features
- Can migrate to WebSphere Liberty without Containerfile changes if needed (same base structure)

## Implementation Notes

### Build Command

```bash
# Build from repository root (required for build context)
podman build -t liberty-app:1.0.0 \
  --build-arg VERSION=1.0.0 \
  --build-arg GIT_COMMIT=$(git rev-parse --short HEAD) \
  --build-arg BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ") \
  -f containers/liberty/Containerfile .
```

### JVM Configuration

The `jvm.options` file contains OpenJ9-compatible settings:
```
-Xmx512m
-Xms256m
-Djava.security.egd=file:/dev/urandom
```

### Health Check

Container health is verified via MicroProfile Health:
```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:9080/health/ready || exit 1
```

### OCI Labels

The image includes standard OCI labels for traceability:
- `org.opencontainers.image.version`: Application version
- `org.opencontainers.image.revision`: Git commit SHA
- `org.opencontainers.image.created`: Build timestamp
- `org.opencontainers.image.base.name`: Base image reference

## Related Decisions

- ADR-001 through ADR-004: (Reserved for prior decisions)
- Future: ADR for multi-architecture builds (amd64/arm64)
- Future: ADR for InstantOn checkpoint/restore adoption

## References

- [Open Liberty Container Images](https://openliberty.io/docs/latest/container-images.html)
- [Eclipse OpenJ9 Documentation](https://eclipse.dev/openj9/)
- [Red Hat Universal Base Image](https://developers.redhat.com/products/rhel/ubi)
- [OCI Image Specification](https://github.com/opencontainers/image-spec)
- [MicroProfile Health 4.0](https://download.eclipse.org/microprofile/microprofile-health-4.0/)
