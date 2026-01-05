# Kubernetes Cluster Management Scripts

This directory contains scripts for managing the Beelink 3-node Kubernetes homelab cluster.

## Cluster Configuration

| Node          | IP Address    | Role                   |
| ------------- | ------------- | ---------------------- |
| k8s-master-01 | 192.168.68.93 | Control Plane + Worker |
| k8s-worker-01 | 192.168.68.86 | Worker                 |
| k8s-worker-02 | 192.168.68.88 | Worker                 |

### MetalLB IP Assignments

| Service         | IP Address     | Port         |
| --------------- | -------------- | ------------ |
| Ingress/Liberty | 192.168.68.200 | 80/443, 9080 |
| Prometheus      | 192.168.68.201 | 9090         |
| Grafana         | 192.168.68.202 | 3000         |
| Alertmanager    | 192.168.68.203 | 9093         |
| Loki            | 192.168.68.204 | 3100         |
| Jaeger          | 192.168.68.205 | 16686        |
| Jenkins         | 192.168.68.206 | 8080         |

## Scripts

### `teardown.sh` - Complete Cluster Teardown

Safely removes all cluster components in the correct dependency order.

```bash
# Preview what would be done
./teardown.sh --dry-run

# Standard teardown (preserves backups and PVCs)
./teardown.sh

# Full teardown including persistent data
./teardown.sh --delete-data

# Complete cluster reset (kubeadm reset on all nodes)
./teardown.sh --delete-data --reset-cluster

# Skip confirmation prompts
./teardown.sh -y
```

**Options:**

- `--skip-backup` - Skip the backup phase
- `--delete-data` - Delete all PVCs and persistent data
- `--reset-cluster` - Reset kubeadm on all nodes
- `--dry-run` - Show what would be done
- `-y, --yes` - Skip confirmation prompts

### `rebuild.sh` - Complete Cluster Rebuild

Rebuilds the entire cluster from scratch with all components.

```bash
# Rebuild existing cluster (skip kubeadm init)
./rebuild.sh

# Initialize new cluster
./rebuild.sh --init-cluster

# Skip optional components
./rebuild.sh --skip-monitoring --skip-apps

# Preview
./rebuild.sh --dry-run
```

**Options:**

- `--init-cluster` - Initialize kubeadm cluster (only if not exists)
- `--skip-init` - Skip cluster initialization
- `--skip-monitoring` - Skip monitoring stack
- `--skip-apps` - Skip application deployment
- `--dry-run` - Show what would be done
- `-y, --yes` - Skip confirmation prompts

### `backup.sh` - Cluster Backup

Creates comprehensive backups of all cluster resources.

```bash
# Standard backup
./backup.sh

# Custom output directory
./backup.sh -o /path/to/backup

# Include secret values (handle with care!)
./backup.sh --include-secrets

# Grafana dashboards only
./backup.sh --grafana-only
```

**Options:**

- `-o, --output DIR` - Backup output directory
- `--include-secrets` - Include secret values in backup
- `--grafana-only` - Only backup Grafana dashboards

### `verify.sh` - Cluster Verification

Validates all cluster components are healthy.

```bash
# Full verification
./verify.sh

# Quick check
./verify.sh --quick

# JSON output (for automation)
./verify.sh --json

# Verbose output
./verify.sh -v
```

**Options:**

- `--quick` - Quick check (skip detailed tests)
- `--json` - Output results as JSON
- `-v, --verbose` - Show detailed output

### `node-prep.sh` - Node Preparation

Prepares a node for Kubernetes installation. Run on each node before cluster init.

```bash
# SSH to each node and run:
sudo ./node-prep.sh

# Specify Kubernetes version
sudo ./node-prep.sh --k8s-version 1.34

# Preview
sudo ./node-prep.sh --dry-run
```

**Options:**

- `--k8s-version VERSION` - Kubernetes version (default: 1.30)
- `--dry-run` - Show what would be done

## Typical Workflows

### Fresh Cluster Setup

```bash
# 1. Prepare all nodes (run on each node)
scp node-prep.sh user@192.168.68.93:/tmp/
scp node-prep.sh user@192.168.68.86:/tmp/
scp node-prep.sh user@192.168.68.88:/tmp/

ssh user@192.168.68.93 "sudo /tmp/node-prep.sh"
ssh user@192.168.68.86 "sudo /tmp/node-prep.sh"
ssh user@192.168.68.88 "sudo /tmp/node-prep.sh"

# 2. Initialize and rebuild cluster
./rebuild.sh --init-cluster

# 3. Verify
./verify.sh
```

### Cluster Reset and Rebuild

```bash
# 1. Backup current state
./backup.sh

# 2. Full teardown
./teardown.sh --delete-data --reset-cluster -y

# 3. Re-prepare nodes (if needed)
# ...

# 4. Rebuild
./rebuild.sh --init-cluster

# 5. Verify
./verify.sh
```

### Partial Rebuild (Keep Cluster)

```bash
# 1. Backup
./backup.sh

# 2. Teardown workloads only (keep cluster)
./teardown.sh --skip-backup

# 3. Rebuild workloads
./rebuild.sh --skip-init

# 4. Verify
./verify.sh
```

### Daily Operations

```bash
# Morning health check
./verify.sh --quick

# Weekly backup
./backup.sh -o ~/backups/weekly-$(date +%Y%m%d)

# Before maintenance
./backup.sh
./verify.sh
```

## Teardown Order

The teardown script removes components in this order:

1. **ArgoCD Applications** - GitOps managed resources
2. **Liberty Application** - Scale down, remove HPA, deployment
3. **AWX** - Uninstall operator
4. **Jenkins** - Helm uninstall
5. **Monitoring Stack** - Promtail → Loki → Prometheus
6. **Infrastructure** - Certificates, External Secrets, Ingress, cert-manager
7. **Network Policies** - All namespace policies
8. **Storage** - PVCs, Longhorn
9. **MetalLB** - L2Advertisement, IPAddressPool
10. **Namespaces** - Clean up remaining namespaces
11. **Cluster Reset** - kubeadm reset (optional)

## Rebuild Order

The rebuild script deploys components in this order:

1. **Cluster Init** - kubeadm init, join workers (optional)
2. **CNI** - Calico network plugin
3. **Storage** - Longhorn
4. **MetalLB** - L2 mode, IP pool
5. **Namespaces** - Create and label with PSS
6. **cert-manager** - Certificate management
7. **Ingress** - NGINX Ingress Controller
8. **Monitoring** - Prometheus, Grafana, Loki, Promtail
9. **External Secrets** - ESO operator and stores
10. **Network Policies** - Default-deny and allow rules
11. **Secrets** - Liberty and TLS secrets
12. **Applications** - Liberty deployment
13. **CI/CD** - Jenkins
14. **GitOps** - ArgoCD (optional)

## Backup Contents

Backups include:

```
backups/TIMESTAMP/
├── secrets/           # Secret metadata (or full if --include-secrets)
├── configmaps/        # All ConfigMaps
├── pvcs/              # PVC and PV definitions
├── rbac/              # ServiceAccounts, Roles, Bindings
├── helm/              # Helm release values and manifests
├── grafana/           # Dashboards, datasources, alerts
│   └── dashboards/
├── custom-resources/  # ExternalSecrets, Certificates, etc.
├── cluster/           # Nodes, namespaces, deployments
└── MANIFEST.txt       # Backup summary
```

## Prerequisites

- `kubectl` configured with cluster access
- `helm` v3+
- `jq` for JSON processing
- `curl` for health checks
- SSH access to nodes (for cluster reset)

## Troubleshooting

### Namespace Stuck in Terminating

```bash
# Force delete stuck namespace
NAMESPACE=stuck-namespace
kubectl get namespace $NAMESPACE -o json | \
  jq '.spec.finalizers = []' | \
  kubectl replace --raw "/api/v1/namespaces/$NAMESPACE/finalize" -f -
```

### PVCs Not Deleting

```bash
# Check for finalizers
kubectl get pvc -A -o json | jq '.items[] | select(.metadata.deletionTimestamp != null)'

# Remove finalizers if needed
kubectl patch pvc <name> -n <namespace> -p '{"metadata":{"finalizers":null}}'
```

### MetalLB IPs Not Assigned

```bash
# Check speaker logs
kubectl logs -n metallb-system -l component=speaker

# Verify IPAddressPool
kubectl get ipaddresspools -n metallb-system -o yaml
```

### Verify Script Fails

```bash
# Run with verbose output
./verify.sh -v

# Check specific component logs
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus
```
