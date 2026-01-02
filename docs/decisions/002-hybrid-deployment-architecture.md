# ADR 002: Hybrid Deployment Architecture

## Status

Accepted

## Context

The Middleware Automation Platform required deployment targets for both development/testing and production use cases. Several factors influenced this decision:

1. **Cost Management**: AWS services incur ongoing costs even when idle. Developers need an environment for experimentation without cost concerns.

2. **Network Isolation**: Development and production environments should be separate to prevent accidental impact on production systems.

3. **Skill Development**: The platform serves as a learning and demonstration tool. Having multiple deployment targets showcases different orchestration approaches.

4. **Hardware Availability**: A 3-node Beelink Mini PC cluster was available for local Kubernetes deployment, providing real bare-metal experience.

5. **Feedback Loop**: Local development enables faster iteration cycles compared to cloud deployments.

6. **Demonstration Scope**: The platform demonstrates transformation from manual (7 hours) to automated (~28 minutes) deployment. Multiple environments showcase this across different infrastructure types.

## Decision

We adopted a **hybrid deployment architecture** with three distinct deployment targets:

### 1. Local Kubernetes (Development)
- 3-node Beelink Mini PC cluster (192.168.68.0/24 network)
- Uses kubeadm with containerd
- MetalLB for LoadBalancer services
- Longhorn for distributed storage
- Full CI/CD stack: Jenkins, AWX, Prometheus, Grafana
- **Cost**: $0/month operational

### 2. Local Podman (Single-Machine Development)
- Single-machine container deployment
- No orchestration overhead
- Quick iteration for container testing
- Uses same container images as production

### 3. AWS Production
- ECS Fargate or EC2 instances (see ADR-001)
- RDS PostgreSQL for database
- ElastiCache Redis for caching
- Application Load Balancer with optional TLS
- Dedicated monitoring EC2 instance
- **Cost**: ~$157-170/month

### Environment Promotion Path

```
Local Podman (build/test) -> Local Kubernetes (integration) -> AWS Production (deployment)
```

Container images are built once and promoted through environments:
- Local: Direct image import via `ctr` or Docker Hub
- AWS: Push to Amazon ECR

## Consequences

### Positive

1. **Zero-Cost Development**: Local environments have no ongoing cloud costs
2. **Realistic Testing**: Local Kubernetes provides real multi-node behavior
3. **Skill Transferability**: Experience with local Kubernetes translates to cloud Kubernetes
4. **Fast Iteration**: Local deployments complete in seconds vs minutes for cloud
5. **Network Isolation**: No risk of development activities affecting production
6. **Offline Capability**: Development continues without internet connectivity
7. **Complete Stack**: All components (monitoring, CI/CD, orchestration) available locally

### Negative

1. **Hardware Requirements**: Requires physical servers for local Kubernetes
2. **Maintenance Overhead**: Two distinct deployment paths to maintain
3. **Environment Drift**: Risk of differences between local and AWS configurations
4. **Limited Scale Testing**: Local cluster cannot test true production scale
5. **Documentation Complexity**: Three deployment options require comprehensive documentation

## Alternatives Considered

### Alternative 1: AWS Only

Use only AWS for all environments (dev, staging, production).

**Rejected because**:
- Ongoing costs for development environments
- Slower feedback loop for developers
- No offline development capability
- Does not demonstrate local/bare-metal Kubernetes

### Alternative 2: Local Docker Compose Only

Use Docker Compose for all local development instead of Kubernetes.

**Rejected because**:
- Does not demonstrate Kubernetes patterns
- Missing orchestration features (rolling updates, self-healing, HPA)
- Container networking differs significantly from production
- Cannot test ServiceMonitors or Kubernetes-native monitoring

### Alternative 3: Cloud Kubernetes (EKS/GKE/AKS)

Replace local Kubernetes with a managed cloud Kubernetes service.

**Rejected because**:
- Significant monthly costs (~$70/month for control plane alone)
- Does not provide bare-metal Kubernetes experience
- Slower iteration cycles compared to local deployment
- Less educational value regarding Kubernetes administration

### Alternative 4: k3s or minikube Instead of kubeadm

Use lightweight Kubernetes distributions for local development.

**Partially considered**: k3s was evaluated but kubeadm was chosen because:
- Closer to production Kubernetes distributions
- Better learning experience for Kubernetes internals
- More realistic cluster administration experience
- Hardware was sufficient for full kubeadm cluster

## References

- Local Kubernetes guide: `docs/LOCAL_KUBERNETES_DEPLOYMENT.md`
- Local Podman guide: `docs/LOCAL_PODMAN_DEPLOYMENT.md`
- Architecture diagram: `docs/architecture/HYBRID_ARCHITECTURE.md`
- MetalLB IP assignments documented in `CLAUDE.md`
