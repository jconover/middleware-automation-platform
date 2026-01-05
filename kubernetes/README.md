# Kubernetes Deployment

This directory contains Kustomize-based Kubernetes manifests for deploying Open Liberty and supporting infrastructure. The configurations follow security best practices and support multiple deployment environments.

## Quick Start

### Deploy to Local Homelab (Beelink Cluster)

```bash
# Create namespace
kubectl create namespace liberty

# Preview resources
kubectl kustomize kubernetes/overlays/local-homelab/

# Deploy Liberty application
kubectl apply -k kubernetes/overlays/local-homelab/

# Verify deployment
kubectl get pods -n liberty -w
```

### Expose via MetalLB LoadBalancer

```bash
kubectl patch svc liberty-service -n liberty -p '{"spec": {"type": "LoadBalancer", "loadBalancerIP": "192.168.68.200"}}'
```

### Verify Health

```bash
curl http://192.168.68.200:9080/health/ready
```

## Directory Structure

```
kubernetes/
├── README.md                     # This file
├── base/                         # Base Kustomize configuration
│   ├── kustomization.yaml        # Base kustomization manifest
│   ├── liberty-deployment.yaml   # Deployment, Service, HPA, PDB, RBAC, NetworkPolicy
│   ├── monitoring/               # Prometheus Operator resources
│   │   ├── kustomization.yaml
│   │   ├── liberty-servicemonitor.yaml
│   │   ├── liberty-prometheusrule.yaml
│   │   ├── alertmanager-config.yaml
│   │   ├── alertmanager-config-local.yaml
│   │   └── alertmanager-secrets.yaml
│   └── network-policies/         # Zero-trust network security
│       ├── kustomization.yaml
│       ├── README.md
│       ├── 00-namespace-labels.yaml
│       ├── 01-default-deny.yaml
│       ├── 02-liberty-ingress.yaml
│       ├── 03-liberty-egress.yaml
│       ├── 04-monitoring-policies.yaml
│       ├── 05-jenkins-policies.yaml
│       └── 06-awx-policies.yaml
└── overlays/                     # Environment-specific configurations
    ├── README.md
    ├── local-homelab/            # Beelink cluster (192.168.68.0/24)
    ├── aws/                      # AWS EKS
    ├── dev/                      # Development
    └── prod/                     # Production hardening
```

### Base vs Overlays

| Directory   | Purpose                                                                                                                              |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `base/`     | Common configuration shared across all environments. Contains the Deployment, Service, HPA, PDB, RBAC, and NetworkPolicy resources.  |
| `overlays/` | Environment-specific customizations that patch the base. Each overlay adjusts replicas, resources, network CIDRs, and configuration. |

## Available Overlays

| Overlay         | Use Case                   | Replicas | Resources                     | Network         |
| --------------- | -------------------------- | -------- | ----------------------------- | --------------- |
| `local-homelab` | Beelink 3-node k3s cluster | 1-4      | 250m-2000m CPU, 512Mi-2Gi RAM | 192.168.68.0/24 |
| `aws`           | AWS EKS production         | 2-10     | 500m-4000m CPU, 1Gi-4Gi RAM   | VPC CIDR        |
| `dev`           | Development/testing        | 1-3      | 250m-1000m CPU, 512Mi-1Gi RAM | Inherits base   |
| `prod`          | Production hardening       | 3-20     | 1000m-4000m CPU, 2Gi-4Gi RAM  | Inherits base   |

### When to Use Each Overlay

**local-homelab**: Use for the Beelink homelab cluster. Optimized for limited hardware with reduced resource requests and homelab-specific network CIDRs.

**aws**: Use for AWS EKS deployments. Includes VPC-aware network policies and higher resource allocation for cloud infrastructure.

**dev**: Use for development and testing. Single replica, minimal resources, debug logging enabled, relaxed PodDisruptionBudget.

**prod**: Use for production deployments requiring maximum security. Includes Pod Security Admission enforcement, strict PDB, and ECR image references.

## Deployment Order Checklist

Follow this order when deploying to a new cluster:

1. **Prerequisites**

   - [ ] Kubernetes cluster is running and accessible
   - [ ] kubectl configured with correct context
   - [ ] CNI plugin supports NetworkPolicies (Calico, Cilium, or Weave)
   - [ ] Prometheus Operator installed (for monitoring resources)

2. **Create Namespace**

   ```bash
   kubectl create namespace liberty
   ```

3. **Create Secrets**

   ```bash
   kubectl create secret generic liberty-secrets \
     --from-literal=db.password='YOUR_DB_PASSWORD' \
     -n liberty
   ```

4. **Deploy Liberty Application**

   ```bash
   kubectl apply -k kubernetes/overlays/local-homelab/
   ```

5. **Deploy Monitoring (Optional)**

   ```bash
   kubectl apply -k kubernetes/base/monitoring/
   ```

6. **Deploy Network Policies (Optional)**

   ```bash
   # Apply allow policies first, then default deny
   kubectl apply -k kubernetes/base/network-policies/
   ```

7. **Verify Deployment**
   ```bash
   kubectl get pods,svc,hpa -n liberty
   ```

## Common kubectl Commands

### Deployment Status

```bash
# Watch pod status
kubectl get pods -n liberty -w

# Check deployment rollout status
kubectl rollout status deployment/liberty-app -n liberty

# View deployment details
kubectl describe deployment liberty-app -n liberty
```

### Logs and Debugging

```bash
# View pod logs
kubectl logs -n liberty -l app=liberty --tail=100

# Follow logs in real-time
kubectl logs -n liberty -l app=liberty -f

# Exec into a pod for debugging
kubectl exec -n liberty -it deployment/liberty-app -- /bin/bash
```

### Health Checks

```bash
# Port-forward to test locally
kubectl port-forward -n liberty svc/liberty-service 9080:9080

# Test health endpoints (in another terminal)
curl http://localhost:9080/health/ready
curl http://localhost:9080/health/live
curl http://localhost:9080/health/started
curl http://localhost:9080/metrics
```

### Scaling

```bash
# Manual scale
kubectl scale deployment liberty-app -n liberty --replicas=3

# View HPA status
kubectl get hpa -n liberty

# Describe HPA for scaling details
kubectl describe hpa liberty-hpa -n liberty
```

### Troubleshooting

```bash
# Check events for issues
kubectl get events -n liberty --sort-by='.lastTimestamp'

# Describe pod for detailed status
kubectl describe pod -n liberty -l app=liberty

# Check resource usage
kubectl top pods -n liberty

# View NetworkPolicies
kubectl get networkpolicy -n liberty
```

### Cleanup

```bash
# Delete deployment (preserves namespace and secrets)
kubectl delete -k kubernetes/overlays/local-homelab/

# Delete namespace and all resources
kubectl delete namespace liberty
```

## Local Kubernetes Cluster Reference

The local homelab uses a 3-node Beelink cluster:

| Node          | IP            | Role                   |
| ------------- | ------------- | ---------------------- |
| k8s-master-01 | 192.168.68.93 | Control Plane + Worker |
| k8s-worker-01 | 192.168.68.86 | Worker                 |
| k8s-worker-02 | 192.168.68.88 | Worker                 |

### MetalLB IP Assignments

| Service      | IP             |
| ------------ | -------------- |
| Liberty      | 192.168.68.200 |
| Prometheus   | 192.168.68.201 |
| Grafana      | 192.168.68.202 |
| Alertmanager | 192.168.68.203 |

## Resources Included in Base

The base configuration deploys these Kubernetes resources:

| Resource                | Name                   | Description                              |
| ----------------------- | ---------------------- | ---------------------------------------- |
| Deployment              | liberty-app            | 3 replicas with rolling update strategy  |
| Service                 | liberty-service        | ClusterIP service on ports 9080/9443     |
| HorizontalPodAutoscaler | liberty-hpa            | Scales 3-10 replicas based on CPU/memory |
| PodDisruptionBudget     | liberty-pdb            | Maintains min 2 available pods           |
| ServiceAccount          | liberty-app            | Minimal privileges, no API token mounted |
| Role/RoleBinding        | liberty-app-role       | Empty role (deny-all RBAC posture)       |
| NetworkPolicy           | liberty-network-policy | Ingress/egress restrictions              |
| ResourceQuota           | liberty-resource-quota | Namespace resource limits                |
| LimitRange              | liberty-limit-range    | Default container resource constraints   |

## Security Features

The base deployment includes enterprise security hardening:

- **Pod Security**: runAsNonRoot, readOnlyRootFilesystem, drop ALL capabilities
- **RBAC**: Minimal ServiceAccount with no Kubernetes API access
- **NetworkPolicy**: Restricts ingress to Ingress controller and Prometheus; restricts egress to DNS, database, and HTTPS
- **Resource Quotas**: Prevents namespace resource exhaustion
- **Seccomp/AppArmor**: Runtime security profiles enabled
- **Pod Anti-Affinity**: Spreads pods across nodes for high availability

## Related Documentation

- [Local Kubernetes Deployment Guide](../docs/LOCAL_KUBERNETES_DEPLOYMENT.md) - Complete setup instructions for the Beelink homelab cluster
- [Local Podman Deployment](../docs/LOCAL_PODMAN_DEPLOYMENT.md) - Single-machine development with Podman
- [Credential Setup](../docs/CREDENTIAL_SETUP.md) - Required credential configuration
- [NetworkPolicies README](base/network-policies/README.md) - Detailed network security documentation
- [Overlays README](overlays/README.md) - Environment-specific overlay details
