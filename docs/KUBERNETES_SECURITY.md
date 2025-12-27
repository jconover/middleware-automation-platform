# Kubernetes Security Hardening Guide

This document describes the security controls implemented in the Kubernetes manifests for the Middleware Automation Platform. The configurations follow the CIS Kubernetes Benchmark and Pod Security Standards (PSS).

## Table of Contents

- [Security Overview](#security-overview)
- [Pod Security Standards](#pod-security-standards)
- [Security Context Configuration](#security-context-configuration)
- [Network Policies](#network-policies)
- [Resource Management](#resource-management)
- [Deployment Guide](#deployment-guide)
- [Security Checklist](#security-checklist)

---

## Security Overview

The platform implements defense-in-depth security with multiple layers:

| Layer | Control | Implementation |
|-------|---------|----------------|
| Namespace | Pod Security Admission | `pod-security.kubernetes.io/*` labels |
| Pod | Security Context | `runAsNonRoot`, `fsGroup`, `seccompProfile` |
| Container | Security Context | `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`, `capabilities: drop: ALL` |
| Network | NetworkPolicy | Ingress/Egress restrictions |
| Resources | Quotas & Limits | ResourceQuota, LimitRange |

---

## Pod Security Standards

Kubernetes 1.23+ includes Pod Security Admission (PSA), which replaces the deprecated PodSecurityPolicy. We enforce the **restricted** profile for Liberty applications.

### Security Levels

| Level | Description | Usage |
|-------|-------------|-------|
| **privileged** | Unrestricted, allows known privilege escalations | Not used |
| **baseline** | Minimally restrictive, prevents known privilege escalations | AWX (due to container requirements) |
| **restricted** | Heavily restricted, current Pod hardening best practices | Liberty applications |

### Namespace Labels

```yaml
# Production Liberty namespace
metadata:
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/audit: restricted
```

---

## Security Context Configuration

### Pod-Level Security Context

Applied to all containers in the pod:

```yaml
spec:
  securityContext:
    # Prevent running as root user
    runAsNonRoot: true
    runAsUser: 1001
    runAsGroup: 1001

    # File system group for volume permissions
    fsGroup: 1001
    fsGroupChangePolicy: OnRootMismatch

    # Seccomp profile for syscall filtering
    seccompProfile:
      type: RuntimeDefault
```

### Container-Level Security Context

Applied to individual containers (defense in depth):

```yaml
containers:
  - name: liberty
    securityContext:
      # Non-root execution
      runAsNonRoot: true
      runAsUser: 1001
      runAsGroup: 1001

      # Prevent privilege escalation
      allowPrivilegeEscalation: false
      privileged: false

      # Read-only root filesystem
      readOnlyRootFilesystem: true

      # Drop all Linux capabilities
      capabilities:
        drop:
          - ALL

      # Seccomp syscall filtering
      seccompProfile:
        type: RuntimeDefault
```

### Read-Only Root Filesystem

When `readOnlyRootFilesystem: true` is set, writable paths must be provided via emptyDir volumes:

```yaml
volumeMounts:
  - name: liberty-logs
    mountPath: /logs
  - name: liberty-tmp
    mountPath: /tmp
  - name: liberty-workarea
    mountPath: /opt/ol/wlp/output/defaultServer/workarea

volumes:
  - name: liberty-logs
    emptyDir:
      sizeLimit: 500Mi
  - name: liberty-tmp
    emptyDir:
      sizeLimit: 256Mi
  - name: liberty-workarea
    emptyDir:
      sizeLimit: 256Mi
```

---

## Network Policies

Network policies implement microsegmentation by default-denying all traffic and explicitly allowing only necessary communication.

### Liberty Network Policy

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: liberty-network-policy
spec:
  podSelector:
    matchLabels:
      app: liberty
  policyTypes:
    - Ingress
    - Egress
```

#### Ingress Rules

| Source | Ports | Purpose |
|--------|-------|---------|
| Ingress controllers (nginx/traefik) | 9080, 9443 | HTTP/HTTPS traffic |
| Monitoring namespace | 9080 | Prometheus scraping |
| Same app pods | 9080, 9443 | Inter-pod communication |

#### Egress Rules

| Destination | Ports | Purpose |
|-------------|-------|---------|
| kube-dns | 53 (UDP/TCP) | DNS resolution |
| Database namespace | 5432 | PostgreSQL connections |
| External (non-RFC1918) | 443 | External API calls |

### AWX Network Policy

AWX requires additional egress for automation:

| Destination | Ports | Purpose |
|-------------|-------|---------|
| All | 22 | SSH to managed nodes |
| All | 5985, 5986 | WinRM to Windows nodes |
| All | 443, 8443 | HTTPS for SCM/APIs |

---

## Resource Management

### Resource Quotas

Prevent resource exhaustion at the namespace level:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: liberty-resource-quota
spec:
  hard:
    requests.cpu: "10"
    requests.memory: "20Gi"
    limits.cpu: "40"
    limits.memory: "40Gi"
    pods: "20"
    persistentvolumeclaims: "10"
```

### Limit Ranges

Enforce default and maximum resource constraints:

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: liberty-limit-range
spec:
  limits:
    - type: Container
      default:
        cpu: "1000m"
        memory: "1Gi"
      defaultRequest:
        cpu: "250m"
        memory: "512Mi"
      min:
        cpu: "100m"
        memory: "128Mi"
      max:
        cpu: "4000m"
        memory: "4Gi"
```

### Container Resources

All containers specify explicit requests and limits:

```yaml
resources:
  requests:
    cpu: "500m"
    memory: "1Gi"
    ephemeral-storage: "256Mi"
  limits:
    cpu: "2000m"
    memory: "2Gi"
    ephemeral-storage: "1Gi"
```

---

## Deployment Guide

### Using Kustomize

Deploy to development:
```bash
kubectl apply -k kubernetes/overlays/dev
```

Deploy to production:
```bash
kubectl apply -k kubernetes/overlays/prod
```

### Environment Differences

| Setting | Development | Production |
|---------|-------------|------------|
| Replicas | 1 | 3 |
| CPU Request | 250m | 1000m |
| Memory Request | 512Mi | 2Gi |
| Image Pull Policy | IfNotPresent | Always |
| HPA Min Replicas | 1 | 3 |
| HPA Max Replicas | 3 | 20 |
| PDB Min Available | 0 | 2 |

### Verifying Security

Check Pod Security Admission:
```bash
# Verify namespace labels
kubectl get namespace liberty-prod -o yaml | grep pod-security

# Test a privileged pod (should be rejected)
kubectl run test-privileged --image=nginx --privileged -n liberty-prod
```

Verify security context:
```bash
# Check running container security context
kubectl exec -it <pod-name> -n liberty-prod -- id
# Expected: uid=1001 gid=1001 groups=1001

# Verify read-only root filesystem
kubectl exec -it <pod-name> -n liberty-prod -- touch /test-file
# Expected: touch: cannot touch '/test-file': Read-only file system
```

Verify network policies:
```bash
# List network policies
kubectl get networkpolicies -n liberty-prod

# Test connectivity (from an allowed source)
kubectl exec -it <ingress-pod> -n ingress-nginx -- curl http://liberty-service.liberty-prod:9080/health
```

---

## Security Checklist

### Pod Security

- [x] `runAsNonRoot: true` - Prevents root user execution
- [x] `runAsUser/runAsGroup` - Explicit non-root UID/GID
- [x] `allowPrivilegeEscalation: false` - Prevents privilege escalation
- [x] `privileged: false` - Prevents privileged containers
- [x] `readOnlyRootFilesystem: true` - Immutable container filesystem
- [x] `capabilities.drop: ALL` - Drops all Linux capabilities
- [x] `seccompProfile: RuntimeDefault` - Enables syscall filtering

### Network Security

- [x] NetworkPolicy ingress rules - Restricts incoming traffic
- [x] NetworkPolicy egress rules - Restricts outgoing traffic
- [x] Default-deny policy approach - Explicit allow-listing

### Resource Security

- [x] CPU/Memory requests and limits - Prevents resource starvation
- [x] Ephemeral storage limits - Prevents disk exhaustion
- [x] ResourceQuota - Namespace-level limits
- [x] LimitRange - Default container limits

### Additional Controls

- [x] ServiceAccount with `automountServiceAccountToken: false`
- [x] Pod anti-affinity for high availability
- [x] AppArmor annotations for MAC enforcement
- [x] Proper labeling for observability and policy targeting
- [x] Image versioning (no `latest` tag in production)

---

## References

- [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [Open Liberty Container Security](https://openliberty.io/docs/latest/container-images.html)
- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
