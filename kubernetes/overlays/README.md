# Kubernetes Overlays

This directory contains Kustomize overlays for deploying Liberty to different environments. Each overlay customizes the base configuration for specific network configurations, resource constraints, and security requirements.

## Available Overlays

| Overlay | Purpose | Network CIDR | K8s Platform |
|---------|---------|--------------|--------------|
| `local-homelab` | Beelink 3-node cluster | `192.168.68.0/24` | k3s |
| `aws` | AWS EKS production | `10.0.0.0/16` (VPC) | EKS |
| `dev` | Development/testing | Inherits base | Any |
| `prod` | Production hardening | Inherits base | Any |

## Usage

### Deploy to Local Homelab (Beelink Cluster)

```bash
# Preview resources
kubectl kustomize kubernetes/overlays/local-homelab/

# Apply to cluster
kubectl apply -k kubernetes/overlays/local-homelab/
```

### Deploy to AWS EKS

```bash
# Preview resources
kubectl kustomize kubernetes/overlays/aws/

# Apply to cluster
kubectl apply -k kubernetes/overlays/aws/
```

### Deploy for Development

```bash
kubectl apply -k kubernetes/overlays/dev/
```

### Deploy for Production

```bash
kubectl apply -k kubernetes/overlays/prod/
```

## Environment-Specific Configuration

### Network CIDRs

Each environment has different network configurations that affect NetworkPolicies:

| Environment | External Access CIDR | K8s API Server | Notes |
|-------------|---------------------|----------------|-------|
| Local Homelab | `192.168.68.0/24` | `10.43.0.1/32` | k3s ClusterIP |
| AWS EKS | VPC CIDR (e.g., `10.0.0.0/16`) | Security Groups | No IP-based rules needed |
| Generic | `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` | Varies | RFC1918 ranges |

### Creating a Custom Overlay

1. Create a new directory:
   ```bash
   mkdir -p kubernetes/overlays/my-environment
   ```

2. Create `kustomization.yaml`:
   ```yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization

   resources:
     - ../../base

   namespace: liberty

   commonLabels:
     environment: my-environment

   patches:
     # Customize replicas
     - target:
         kind: Deployment
         name: liberty-app
       patch: |-
         - op: replace
           path: /spec/replicas
           value: 2

   configMapGenerator:
     - name: liberty-config
       behavior: merge
       literals:
         - db.host=my-database.example.com
   ```

3. For custom NetworkPolicy CIDRs, create `network-policies-patch.yaml`:
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: allow-external-access-to-grafana
     namespace: monitoring
   spec:
     ingress:
       - from:
           - ipBlock:
               cidr: YOUR_NETWORK_CIDR/24
         ports:
           - protocol: TCP
             port: 3000
   ```

4. Reference the patch in `kustomization.yaml`:
   ```yaml
   resources:
     - ../../base
     - network-policies-patch.yaml
   ```

## Overlay Structure

```
overlays/
├── README.md                    # This file
├── local-homelab/
│   └── kustomization.yaml       # Beelink cluster config
├── aws/
│   ├── kustomization.yaml       # AWS EKS config
│   └── network-policies-patch.yaml  # AWS-specific CIDRs
├── dev/
│   └── kustomization.yaml       # Development config
└── prod/
    ├── kustomization.yaml       # Production config
    └── pod-security-admission.yaml  # PSA enforcement
```

## Key Differences Between Overlays

### local-homelab
- Reduced resource requirements (limited hardware)
- 1-2 replicas (3-node cluster)
- k3s-specific Kubernetes API CIDR (`10.43.0.1/32`)
- Direct network access from `192.168.68.0/24`

### aws
- Higher resource allocation
- 2-10 replicas with HPA
- VPC CIDR-based NetworkPolicies
- ALB health check compatibility

### dev
- Single replica
- Minimal resources
- Debug logging enabled
- Relaxed PDB settings

### prod
- 3+ replicas minimum
- Enterprise resource allocation
- INFO logging
- Strict PDB (min 2 available)
- Pod Security Admission enforced
