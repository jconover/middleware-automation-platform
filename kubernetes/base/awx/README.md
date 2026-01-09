# AWX Deployment for Beelink Homelab

AWX (Ansible Automation Platform) deployment using the AWX Operator on Kubernetes.

## Prerequisites

- Kubernetes cluster with Longhorn storage class
- MetalLB for LoadBalancer services
- kubectl configured to access the cluster

## Quick Start

```bash
# 1. Create the AWX namespace and admin password secret
kubectl create namespace awx
kubectl create secret generic awx-admin-password \
  --namespace=awx \
  --from-literal=password='YOUR_SECURE_PASSWORD_HERE'

# 2. Deploy AWX using Kustomize
kubectl apply -k kubernetes/base/awx/

# 3. Watch the deployment progress
kubectl -n awx get pods -w

# 4. Wait for all pods to be Running (takes 5-10 minutes)
kubectl -n awx wait --for=condition=Ready pods --all --timeout=600s
```

## Access

- **URL**: http://192.168.68.206
- **Username**: admin
- **Password**: (value you set in awx-admin-password secret)

## Components Deployed

| Component | Description |
|-----------|-------------|
| AWX Operator | Manages AWX lifecycle (v2.19.1) |
| AWX Web | Web interface and API |
| AWX Task | Job execution engine |
| PostgreSQL | Database (8Gi Longhorn PVC) |
| Redis | Message queue |

## Resource Requirements

| Component | CPU Request | Memory Request | CPU Limit | Memory Limit |
|-----------|-------------|----------------|-----------|--------------|
| Web | 250m | 512Mi | 1000m | 2Gi |
| Task | 250m | 512Mi | 1000m | 2Gi |
| EE | 100m | 256Mi | 500m | 1Gi |
| Redis | 50m | 128Mi | 250m | 256Mi |

## MetalLB IP Assignment

AWX is assigned **192.168.68.206** in the MetalLB pool.

| Service | IP |
|---------|-----|
| Liberty | 192.168.68.200 |
| Prometheus | 192.168.68.201 |
| Grafana | 192.168.68.202 |
| Alertmanager | 192.168.68.203 |
| Loki | 192.168.68.204 |
| Jaeger | 192.168.68.205 |
| **AWX** | **192.168.68.206** |

## Post-Deployment Setup

After AWX is running, configure it for this project:

### 1. Create Credentials

- **Machine Credential**: SSH key for accessing managed hosts
- **Vault Credential**: Ansible Vault password for encrypted vars
- **SCM Credential**: Git access token (if private repo)

### 2. Create Project

- **Name**: middleware-automation-platform
- **SCM Type**: Git
- **SCM URL**: https://github.com/your-org/middleware-automation-platform.git
- **SCM Branch**: main
- **Playbook Directory**: automated/ansible/playbooks

### 3. Create Inventories

- **Development**: Import from `automated/ansible/inventory/dev.yml`
- **Production AWS**: Import from `automated/ansible/inventory/prod-aws-ec2.yml`

### 4. Create Job Templates

| Name | Playbook | Inventory |
|------|----------|-----------|
| Deploy Full Stack - Dev | site.yml | Development |
| Deploy Full Stack - AWS | site.yml | Production AWS |
| Deploy Sample App | deploy-sample-app.yml | (Survey) |
| Health Check | health-check.yml | (Survey) |

## Troubleshooting

### Pods not starting

```bash
# Check operator logs
kubectl -n awx logs deployment/awx-operator-controller-manager

# Check AWX status
kubectl -n awx get awx awx -o yaml

# Describe pods for events
kubectl -n awx describe pods
```

### Database issues

```bash
# Check PostgreSQL pod
kubectl -n awx logs -l app.kubernetes.io/component=database

# Check PVC status
kubectl -n awx get pvc
```

### Reset admin password

```bash
kubectl -n awx exec -it deployment/awx-web -- awx-manage changepassword admin
```

## Cleanup

```bash
# Delete AWX instance (keeps operator)
kubectl -n awx delete awx awx

# Delete everything including operator
kubectl delete -k kubernetes/base/awx/

# Delete PVCs (if you want to remove data)
kubectl -n awx delete pvc --all
```

## Files

| File | Description |
|------|-------------|
| `kustomization.yaml` | Kustomize configuration |
| `namespace.yaml` | AWX namespace with PSA labels |
| `awx-operator.yaml` | AWX Operator deployment and CRDs |
| `awx-instance.yaml` | AWX Custom Resource and quotas |
| `awx-service.yaml` | LoadBalancer service and NetworkPolicy |
