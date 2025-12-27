# Kubernetes NetworkPolicies

This directory contains NetworkPolicy resources implementing zero-trust network security for the Middleware Automation Platform.

## Overview

NetworkPolicies enforce network segmentation at the pod level, controlling which pods can communicate with each other and with external services. This implementation follows the principle of least privilege - all traffic is denied by default, and only explicitly required traffic is allowed.

## Architecture

```
                                    ┌─────────────────────────┐
                                    │    External Traffic     │
                                    │   (192.168.68.0/24)     │
                                    └───────────┬─────────────┘
                                                │
                              ┌─────────────────┼─────────────────┐
                              │                 │                 │
                              ▼                 ▼                 ▼
                    ┌─────────────────┐ ┌─────────────┐ ┌─────────────────┐
                    │  NGINX Ingress  │ │   MetalLB   │ │  LoadBalancer   │
                    │   (Namespace)   │ │  (L2 ARP)   │ │   (External)    │
                    └────────┬────────┘ └──────┬──────┘ └────────┬────────┘
                             │                 │                 │
         ┌───────────────────┼─────────────────┼─────────────────┼───────────────────┐
         │                   │                 │                 │                   │
         ▼                   ▼                 ▼                 ▼                   ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐ ┌───────────────┐
│     Liberty     │ │    Prometheus   │ │     Grafana     │ │     Jenkins     │ │      AWX      │
│   (liberty ns)  │ │  (monitoring)   │ │  (monitoring)   │ │  (jenkins ns)   │ │   (awx ns)    │
│                 │ │                 │ │                 │ │                 │ │               │
│  ┌───────────┐  │ │  ┌───────────┐  │ │  ┌───────────┐  │ │  ┌───────────┐  │ │ ┌───────────┐ │
│  │ Port 9080 │◄─┼─┼──│  Scrape   │  │ │  │ Port 3000 │  │ │  │ Port 8080 │  │ │ │ Port 8052 │ │
│  │ Port 9443 │  │ │  │ Port 9090 │◄─┼─┼──│  Queries  │  │ │  │ Port 50000│  │ │ │   SSH→    │─┼──► Managed Hosts
│  └───────────┘  │ │  └───────────┘  │ │  └───────────┘  │ │  └───────────┘  │ │ └───────────┘ │
│        │        │ │        ▲        │ │                 │ │        │        │ │       │       │
│        ▼        │ │        │        │ │                 │ │        ▼        │ │       ▼       │
│  ┌───────────┐  │ │        │        │ │                 │ │  ┌───────────┐  │ │ ┌───────────┐ │
│  │ Database  │──┼─┼────────┼────────┼─┼─────────────────┼─┼──│  Agents   │  │ │ │PostgreSQL │ │
│  │  Egress   │  │ │        │        │ │                 │ │  │   Pods    │  │ │ │  (5432)   │ │
│  └───────────┘  │ │        │        │ │                 │ │  └───────────┘  │ │ └───────────┘ │
└─────────────────┘ └────────┼────────┘ └─────────────────┘ └─────────────────┘ └───────────────┘
         │                   │
         └───────────────────┘
                  │
                  ▼
         ┌─────────────────┐
         │    External     │
         │   - Database    │
         │   - Redis       │
         │   - APIs        │
         └─────────────────┘
```

## Policy Files

| File | Purpose |
|------|---------|
| `00-namespace-labels.yaml` | Labels namespaces for NetworkPolicy selectors |
| `01-default-deny.yaml` | Default deny-all ingress/egress policies |
| `02-liberty-ingress.yaml` | Ingress rules for Liberty application pods |
| `03-liberty-egress.yaml` | Egress rules for Liberty (database, external APIs) |
| `04-monitoring-policies.yaml` | Prometheus, Grafana, AlertManager policies |
| `05-jenkins-policies.yaml` | Jenkins controller and agent policies |
| `06-awx-policies.yaml` | AWX web, task, and database policies |

## Prerequisites

1. **CNI Plugin with NetworkPolicy Support**: Ensure your CNI plugin supports NetworkPolicies:
   - Calico (recommended for k3s)
   - Cilium
   - Weave Net
   - Canal

   **Check current CNI:**
   ```bash
   kubectl get pods -n kube-system | grep -E 'calico|cilium|weave|canal'
   ```

2. **Namespace Labels**: Policies use namespace selectors. Labels must be applied first.

## Installation

### Step 1: Apply Namespace Labels

```bash
kubectl apply -f kubernetes/base/network-policies/00-namespace-labels.yaml
```

Verify labels:
```bash
kubectl get namespaces --show-labels | grep -E 'liberty|monitoring|jenkins|awx'
```

### Step 2: Apply Allow Policies First

**Critical**: Apply allow policies BEFORE default deny policies to avoid losing connectivity.

```bash
# Liberty policies
kubectl apply -f kubernetes/base/network-policies/02-liberty-ingress.yaml
kubectl apply -f kubernetes/base/network-policies/03-liberty-egress.yaml

# Monitoring policies
kubectl apply -f kubernetes/base/network-policies/04-monitoring-policies.yaml

# Jenkins policies
kubectl apply -f kubernetes/base/network-policies/05-jenkins-policies.yaml

# AWX policies
kubectl apply -f kubernetes/base/network-policies/06-awx-policies.yaml
```

### Step 3: Apply Default Deny Policies

```bash
kubectl apply -f kubernetes/base/network-policies/01-default-deny.yaml
```

### Apply All at Once (After Initial Setup)

```bash
kubectl apply -f kubernetes/base/network-policies/
```

## Verification

### Check Policies Are Applied

```bash
# List all NetworkPolicies
kubectl get networkpolicy -A

# Describe a specific policy
kubectl describe networkpolicy allow-ingress-from-prometheus -n liberty
```

### Test Connectivity

```bash
# Test Liberty health endpoint from Prometheus pod
kubectl exec -n monitoring deploy/prometheus-kube-prometheus-prometheus \
  -- wget -qO- http://liberty-service.liberty.svc:9080/health/ready

# Test denied traffic (should fail with timeout)
kubectl run test-pod --rm -it --image=busybox --restart=Never \
  -- wget -qO- --timeout=5 http://liberty-service.liberty.svc:9080/health/ready
```

### Debug Connectivity Issues

```bash
# Check pod labels match policy selectors
kubectl get pods -n liberty --show-labels

# Check namespace labels
kubectl get namespace liberty --show-labels

# Describe policy to see resolved rules
kubectl describe networkpolicy allow-ingress-from-prometheus -n liberty

# Test from a specific namespace
kubectl run debug -n monitoring --rm -it --image=nicolaka/netshoot --restart=Never \
  -- curl -v http://liberty-service.liberty.svc.cluster.local:9080/health/ready
```

## Policy Details

### Liberty Ingress Rules

| Source | Port | Purpose |
|--------|------|---------|
| ingress-nginx namespace | 9080, 9443 | External traffic via Ingress |
| monitoring namespace (Prometheus) | 9080 | Metrics scraping |
| jenkins namespace | 9080 | Deployment verification |
| awx namespace | 9080, 9443 | Ansible health checks |
| metallb-system namespace | 9080, 9443 | LoadBalancer health probes |
| liberty pods (same namespace) | 9080, 9443 | Pod-to-pod communication |

### Liberty Egress Rules

| Destination | Port | Purpose |
|-------------|------|---------|
| kube-dns (kube-system) | 53 | DNS resolution |
| PostgreSQL pods | 5432 | Database connections |
| Redis pods | 6379 | Session caching |
| External HTTPS (0.0.0.0/0) | 443 | Third-party APIs |
| Kubernetes API | 443 | Service discovery |
| Liberty pods (same namespace) | 9080, 9443 | Internal communication |

### Monitoring Policies

- **Prometheus**: Egress to all scrape targets, ingress from Grafana
- **Grafana**: Egress to Prometheus/AlertManager, ingress from users
- **AlertManager**: Egress to webhook destinations (Slack, SMTP)

### CI/CD Policies

- **Jenkins Controller**: Ingress from webhooks, egress to Git/registries
- **Jenkins Agents**: Egress to Git, registries, Liberty for smoke tests
- **AWX Task**: Egress SSH to managed hosts, Git repos

## Customization

### Adding a New Service

1. Create a new policy file following the naming convention: `NN-servicename-policies.yaml`

2. Define ingress rules:
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: allow-myservice-ingress
     namespace: myservice
   spec:
     podSelector:
       matchLabels:
         app: myservice
     policyTypes:
       - Ingress
     ingress:
       - from:
           - namespaceSelector:
               matchLabels:
                 name: allowed-namespace
         ports:
           - protocol: TCP
             port: 8080
   ```

3. Define egress rules for required external access

4. Add default deny policy for the namespace

### Adjusting CIDR Ranges

The policies use the following CIDR ranges by default:

| CIDR | Purpose |
|------|---------|
| `192.168.68.0/24` | Homelab network (direct external access) |
| `10.0.0.0/8` | Private networks (AWS VPC, internal) |
| `10.43.0.1/32` | k3s Kubernetes API service |
| `0.0.0.0/0` | External internet (with private exclusions) |

Update these in the policy files to match your environment.

## Troubleshooting

### Pods Cannot Communicate

1. **Check policy selectors match pod labels:**
   ```bash
   kubectl get pods -n liberty --show-labels
   kubectl describe networkpolicy -n liberty
   ```

2. **Check namespace labels:**
   ```bash
   kubectl get ns --show-labels
   ```

3. **Verify CNI supports NetworkPolicy:**
   ```bash
   # For k3s with Calico
   kubectl get installation default -o yaml | grep -A5 spec:
   ```

### Prometheus Cannot Scrape Targets

1. **Verify ServiceMonitor labels match:**
   ```bash
   kubectl get servicemonitor -n monitoring -o yaml | grep -A10 selector
   ```

2. **Test connectivity from Prometheus pod:**
   ```bash
   kubectl exec -n monitoring prometheus-prometheus-kube-prometheus-prometheus-0 \
     -- wget -qO- http://liberty-service.liberty.svc:9080/metrics | head -10
   ```

### External Access Blocked

1. **Check MetalLB namespace is labeled:**
   ```bash
   kubectl get ns metallb-system --show-labels
   ```

2. **Verify ipBlock allows your network:**
   ```bash
   kubectl describe networkpolicy allow-grafana-ingress -n monitoring
   ```

### DNS Resolution Fails

Ensure the DNS egress policy includes proper kube-dns pod selector:
```yaml
- to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
  ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
```

## Removing Policies

To remove all NetworkPolicies (restore default allow-all):

```bash
# Remove all policies from a namespace
kubectl delete networkpolicy -n liberty --all

# Remove all policies from all namespaces
kubectl delete networkpolicy -A --all
```

**Warning**: This will allow all traffic. Only do this for troubleshooting.

## Security Considerations

1. **Default Deny**: Always apply default deny policies after allow policies are in place

2. **Least Privilege**: Only allow the minimum required traffic

3. **Label Security**: Namespace labels are trusted; ensure only admins can modify them

4. **CIDR Ranges**: Review and adjust CIDR ranges for your environment

5. **External Access**: Consider using an API gateway instead of direct ipBlock rules

6. **Audit**: Regularly review policies and remove unused rules

## Related Documentation

- [Kubernetes NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Calico NetworkPolicy](https://docs.tigera.io/calico/latest/network-policy/)
- [Liberty Deployment Guide](../../../docs/LOCAL_KUBERNETES_DEPLOYMENT.md)
