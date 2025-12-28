# End-to-End Testing Guide

This guide provides a structured approach to testing all three deployment options: Podman (local), Kubernetes (local cluster), and AWS (production). Complete testing in this order for the best experience.

## Prerequisites Checklist

Before starting, verify these tools are installed:

```bash
# Required for all environments
podman --version        # 4.0+
java --version          # 17+
mvn --version           # 3.8+
git --version           # 2.30+

# Required for Kubernetes
kubectl version --client
helm version            # 3.x

# Required for AWS
terraform --version     # 1.6+
aws --version           # AWS CLI v2
```

---

## Phase 1: Podman (Local Container)

**Time estimate:** ~10 minutes
**Reference:** [LOCAL_PODMAN_DEPLOYMENT.md](LOCAL_PODMAN_DEPLOYMENT.md)

### 1.1 Clean Up Previous State

```bash
# Remove any existing containers
podman rm -f liberty-server liberty-dev 2>/dev/null || true

# Remove old images (optional, forces rebuild)
podman rmi liberty-app:1.0.0 2>/dev/null || true

# Clean up unused resources
podman system prune -f
```

### 1.2 Build Sample Application

```bash
cd /home/justin/Projects/middleware-automation-platform

# Build the WAR file
mvn -f sample-app/pom.xml clean package

# Verify WAR was created
ls -la sample-app/target/sample-app.war
```

**Expected:** `sample-app.war` file exists (~10-50KB)

### 1.3 Build Container Image

```bash
# Copy WAR to container build directory
cp sample-app/target/sample-app.war containers/liberty/apps/

# Build the container image
cd containers/liberty
podman build -t liberty-app:1.0.0 -f Containerfile .

# Verify image was created
podman images | grep liberty-app
```

**Expected:** Image `localhost/liberty-app:1.0.0` appears in list

### 1.4 Run Container

```bash
# Run Liberty container
podman run -d --name liberty-server \
    -p 9080:9080 \
    -p 9443:9443 \
    liberty-app:1.0.0

# Watch logs for startup (Ctrl+C to exit)
podman logs -f liberty-server
```

**Expected logs:** Look for `CWWKF0011I: The defaultServer server is ready to run a smarter planet.`

### 1.5 Verify Endpoints

```bash
# Wait for container to be healthy (up to 2 minutes)
timeout 120 bash -c 'until curl -sf http://localhost:9080/health/ready; do sleep 5; done' && echo "READY"

# Test all endpoints
echo "=== Health Checks ==="
curl -s http://localhost:9080/health/ready | jq .
curl -s http://localhost:9080/health/live | jq .

echo "=== Metrics ==="
curl -s http://localhost:9080/metrics | head -20

echo "=== Sample App ==="
curl -s http://localhost:9080/sample-app/api/hello
```

**Expected:**
- Health endpoints return `{"status":"UP"}`
- Metrics return Prometheus-format data
- Sample app returns hello message

### 1.6 Podman Verification Checklist

| Check | Command | Expected |
|-------|---------|----------|
| Container running | `podman ps \| grep liberty` | Shows `liberty-server` |
| Health ready | `curl localhost:9080/health/ready` | `{"status":"UP"}` |
| Health live | `curl localhost:9080/health/live` | `{"status":"UP"}` |
| Metrics exposed | `curl localhost:9080/metrics \| wc -l` | 100+ lines |
| App responding | `curl localhost:9080/sample-app/api/hello` | JSON response |

### 1.7 Cleanup (Before Moving to Kubernetes)

```bash
podman stop liberty-server
podman rm liberty-server
```

---

## Phase 2: Kubernetes (Local Cluster)

**Time estimate:** ~30-45 minutes
**Reference:** [LOCAL_KUBERNETES_DEPLOYMENT.md](LOCAL_KUBERNETES_DEPLOYMENT.md)

### 2.1 Verify Cluster Access

```bash
# Confirm kubectl is configured
kubectl get nodes

# Expected: 3 nodes (k8s-master, k8s-worker-01, k8s-worker-02)
```

### 2.2 Optional: Clean Reinstall

If you want a fresh start, uninstall existing components:

```bash
# Remove Liberty namespace
kubectl delete namespace liberty --wait=false 2>/dev/null || true

# Remove monitoring stack
helm uninstall prometheus -n monitoring 2>/dev/null || true
kubectl delete namespace monitoring --wait=false 2>/dev/null || true

# Remove AWX
kubectl delete namespace awx --wait=false 2>/dev/null || true

# Remove Jenkins
helm uninstall jenkins -n jenkins 2>/dev/null || true
kubectl delete namespace jenkins --wait=false 2>/dev/null || true

# Wait for namespaces to terminate
echo "Waiting for namespaces to terminate..."
sleep 30
kubectl get namespaces
```

### 2.3 Load Container Image to k3s

```bash
cd /home/justin/Projects/middleware-automation-platform

# Save image to tar
podman save liberty-app:1.0.0 -o /tmp/liberty-app.tar

# Import on k8s-master
sudo k3s ctr images import /tmp/liberty-app.tar

# Import on k8s-worker-01
scp /tmp/liberty-app.tar 192.168.68.88:/tmp/
ssh 192.168.68.88 "sudo k3s ctr images import /tmp/liberty-app.tar"

# Import on k8s-worker-02
scp /tmp/liberty-app.tar 192.168.68.83:/tmp/
ssh 192.168.68.83 "sudo k3s ctr images import /tmp/liberty-app.tar"

# Verify import
sudo k3s crictl images | grep liberty-app
```

### 2.4 Deploy Liberty to Kubernetes

```bash
# Create namespace
kubectl create namespace liberty

# Create ConfigMap
kubectl create configmap liberty-config \
  --namespace liberty \
  --from-file=server.xml=/home/justin/Projects/middleware-automation-platform/containers/liberty/server.xml

# Apply deployment
kubectl apply -k kubernetes/overlays/local

# Watch pods come up
kubectl get pods -n liberty -w
```

**Expected:** 3 pods reach `Running` state (matches HPA minReplicas)

### 2.5 Verify Liberty in Kubernetes

```bash
# Port forward for testing
kubectl port-forward svc/liberty-service 9080:9080 -n liberty &
PF_PID=$!
sleep 5

# Test endpoints
echo "=== Health Checks ==="
curl -s http://localhost:9080/health/ready | jq .

echo "=== Metrics ==="
curl -s http://localhost:9080/metrics | head -10

echo "=== Sample App ==="
curl -s http://localhost:9080/sample-app/api/hello

# Kill port-forward
kill $PF_PID 2>/dev/null
```

### 2.6 Deploy Monitoring Stack

```bash
# Add Helm repos
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create namespace
kubectl create namespace monitoring

# Deploy Prometheus/Grafana with MetalLB IPs
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --set prometheus.service.type=LoadBalancer \
    --set prometheus.service.loadBalancerIP=192.168.68.201 \
    --set grafana.service.type=LoadBalancer \
    --set grafana.service.loadBalancerIP=192.168.68.202 \
    --set alertmanager.service.type=LoadBalancer \
    --set alertmanager.service.loadBalancerIP=192.168.68.203 \
    --wait --timeout 10m

# Verify LoadBalancer IPs
kubectl get svc -n monitoring | grep LoadBalancer
```

### 2.7 Deploy Jenkins (Optional)

```bash
# Create namespace and secret
kubectl create namespace jenkins
JENKINS_PASS=$(openssl rand -base64 24)
echo "Jenkins password: $JENKINS_PASS"
kubectl create secret generic jenkins-admin-secret \
  --namespace jenkins \
  --from-literal=jenkins-admin-password="$JENKINS_PASS"

# Deploy Jenkins
helm upgrade --install jenkins jenkins/jenkins \
  --namespace jenkins \
  --values ci-cd/jenkins/kubernetes/values.yaml \
  --wait --timeout 15m

# Verify LoadBalancer IP
kubectl get svc -n jenkins | grep LoadBalancer
```

### 2.8 Deploy AWX (Optional)

```bash
# Create namespace and secret
kubectl create namespace awx
AWX_PASS=$(openssl rand -base64 24)
echo "AWX password: $AWX_PASS"
kubectl create secret generic awx-admin-password \
  --namespace=awx \
  --from-literal=password="$AWX_PASS"

# Install AWX Operator
kubectl apply -f https://raw.githubusercontent.com/ansible/awx-operator/devel/deploy/awx-operator.yaml

# Wait for operator
kubectl wait --namespace awx \
  --for=condition=ready pod \
  --selector=control-plane=controller-manager \
  --timeout=120s

# Deploy AWX
kubectl apply -f awx/awx-deployment.yaml

# Wait for AWX (can take 5-10 minutes)
kubectl get pods -n awx -w
```

### 2.9 Kubernetes Verification Checklist

| Service | URL | Verification |
|---------|-----|--------------|
| Liberty | Port-forward 9080 | `curl localhost:9080/health/ready` |
| Prometheus | http://192.168.68.201:9090 | UI loads, Status > Targets shows UP |
| Grafana | http://192.168.68.202:3000 | Login with admin/prom-operator |
| Jenkins | http://192.168.68.206:8080 | Login page loads |
| AWX | http://192.168.68.205 | Login page loads |

### 2.10 Get Credentials

```bash
# Grafana
kubectl get secret prometheus-grafana -n monitoring \
  -o jsonpath='{.data.admin-password}' | base64 -d && echo

# Jenkins
kubectl get secret jenkins-admin-secret -n jenkins \
  -o jsonpath='{.data.jenkins-admin-password}' | base64 -d && echo

# AWX
kubectl get secret awx-admin-password -n awx \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

---

## Phase 3: AWS Production

**Time estimate:** ~30-45 minutes
**Reference:** Main [README.md](../README.md#option-4-aws-production-deployment)

### 3.1 Prerequisites

```bash
# Verify AWS CLI is configured
aws sts get-caller-identity

# Verify SSH key exists
ls -la ~/.ssh/ansible_ed25519.pub
```

### 3.2 Choose Compute Model

Edit `automated/terraform/environments/prod-aws/terraform.tfvars`:

```bash
cd /home/justin/Projects/middleware-automation-platform/automated/terraform/environments/prod-aws

# Copy example if needed
cp terraform.tfvars.example terraform.tfvars

# Edit to set your options
# For ECS (recommended):
#   ecs_enabled = true
#   liberty_instance_count = 0
#
# For EC2:
#   ecs_enabled = false
#   liberty_instance_count = 2
```

**Important:** Set `management_allowed_cidrs` to your public IP:
```bash
MY_IP=$(curl -s ifconfig.me)
echo "Your IP: $MY_IP/32"
```

### 3.3 Deploy Infrastructure

```bash
cd /home/justin/Projects/middleware-automation-platform/automated/terraform/environments/prod-aws

# Initialize Terraform
terraform init

# Review plan
terraform plan

# Apply (takes 5-10 minutes)
terraform apply
```

### 3.4 Push Container to ECR (ECS only)

```bash
# Get ECR push commands
terraform output ecr_push_commands

# Follow the output commands (example):
# aws ecr get-login-password --region us-east-1 | podman login --username AWS --password-stdin <account>.dkr.ecr.us-east-1.amazonaws.com
# podman tag liberty-app:1.0.0 <account>.dkr.ecr.us-east-1.amazonaws.com/mw-prod-liberty:latest
# podman push <account>.dkr.ecr.us-east-1.amazonaws.com/mw-prod-liberty:latest

# Force ECS to pull new image
aws ecs update-service \
  --cluster mw-prod-cluster \
  --service mw-prod-liberty \
  --force-new-deployment
```

### 3.5 Verify Deployment

```bash
# Get ALB DNS name
ALB_DNS=$(terraform output -raw alb_dns_name)
echo "ALB URL: http://$ALB_DNS"

# Test health endpoint
curl -s http://$ALB_DNS/health/ready

# Test sample app
curl -s http://$ALB_DNS/sample-app/api/hello
```

### 3.6 AWS Verification Checklist

| Check | Command | Expected |
|-------|---------|----------|
| ECS tasks running | `aws ecs list-tasks --cluster mw-prod-cluster` | 2+ task ARNs |
| ALB health | `curl $ALB_DNS/health/ready` | `{"status":"UP"}` |
| Prometheus | `terraform output prometheus_url` | UI accessible |
| Grafana | `terraform output grafana_url` | Login page loads |

### 3.7 Cleanup AWS Resources

When done testing, stop or destroy to avoid costs:

```bash
# Stop services (preserves state, ~$5/month for stopped RDS)
./automated/scripts/aws-stop.sh

# OR fully destroy everything
terraform destroy
```

---

## Quick Verification Script

Save this as `verify-all.sh` to quickly check all environments:

```bash
#!/bin/bash
set -e

echo "========================================"
echo "  Middleware Platform - Full Verification"
echo "========================================"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_http() {
    local name="$1"
    local url="$2"
    local code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null || echo "000")
    if [ "$code" = "200" ]; then
        echo -e "${GREEN}[PASS]${NC} $name"
        return 0
    else
        echo -e "${RED}[FAIL]${NC} $name (HTTP $code)"
        return 1
    fi
}

echo -e "${YELLOW}=== Podman ===${NC}"
if podman ps | grep -q liberty-server; then
    check_http "Liberty (Podman)" "http://localhost:9080/health/ready"
else
    echo -e "${YELLOW}[SKIP]${NC} Podman container not running"
fi

echo ""
echo -e "${YELLOW}=== Kubernetes ===${NC}"
if kubectl get pods -n liberty 2>/dev/null | grep -q Running; then
    echo -e "${GREEN}[PASS]${NC} Liberty pods running in K8s"
else
    echo -e "${YELLOW}[SKIP]${NC} Liberty not deployed to K8s"
fi

check_http "Prometheus" "http://192.168.68.201:9090/-/ready" || true
check_http "Grafana" "http://192.168.68.202:3000/api/health" || true
check_http "Jenkins" "http://192.168.68.206:8080/login" || true
check_http "AWX" "http://192.168.68.205/api/v2/ping/" || true

echo ""
echo -e "${YELLOW}=== AWS (if deployed) ===${NC}"
if command -v terraform &>/dev/null; then
    cd /home/justin/Projects/middleware-automation-platform/automated/terraform/environments/prod-aws
    ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null || echo "")
    if [ -n "$ALB_DNS" ]; then
        check_http "ALB Health" "http://$ALB_DNS/health/ready" || true
    else
        echo -e "${YELLOW}[SKIP]${NC} AWS not deployed"
    fi
fi

echo ""
echo "========================================"
echo "  Verification Complete"
echo "========================================"
```

---

## Known Issues and Workarounds

### Podman

| Issue | Solution |
|-------|----------|
| SELinux denying volume mounts | Add `:Z` suffix to volume mounts |
| Image pull slow | Use `podman pull` beforehand to cache base image |
| Port already in use | Check with `ss -tlnp \| grep 9080` and stop conflicting process |

### Kubernetes

| Issue | Solution |
|-------|----------|
| ImagePullBackOff | Image not imported to all nodes - run `k3s ctr images import` on each |
| LoadBalancer pending | MetalLB not configured - check `kubectl get ipaddresspools -n metallb-system` |
| Pods not scheduling | Check node resources with `kubectl describe nodes` |

### AWS

| Issue | Solution |
|-------|----------|
| ECS tasks failing | Check CloudWatch logs at `/ecs/mw-prod-liberty` |
| ALB returning 503 | Wait for ECS tasks to pass health checks (~2-3 min) |
| Cannot reach ALB | Check security group allows your IP in `management_allowed_cidrs` |

---

## Testing Sequence Summary

```
┌─────────────────────────────────────────────────────────────────┐
│                    END-TO-END TESTING FLOW                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. PODMAN (10 min)                                             │
│     └─> Build WAR → Build Image → Run Container → Verify        │
│                                                                  │
│  2. KUBERNETES (30-45 min)                                      │
│     └─> Load Image → Deploy Liberty → Deploy Monitoring         │
│         └─> (Optional) Deploy Jenkins/AWX                       │
│                                                                  │
│  3. AWS (30-45 min)                                             │
│     └─> terraform apply → Push to ECR → Force deploy            │
│         └─> Verify ALB → (Optional) Stop/Destroy                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Related Documentation

| Document | Purpose |
|----------|---------|
| [LOCAL_PODMAN_DEPLOYMENT.md](LOCAL_PODMAN_DEPLOYMENT.md) | Complete Podman deployment guide |
| [LOCAL_KUBERNETES_DEPLOYMENT.md](LOCAL_KUBERNETES_DEPLOYMENT.md) | Complete Kubernetes deployment guide |
| [README.md](../README.md) | AWS deployment and project overview |
| [CREDENTIAL_SETUP.md](CREDENTIAL_SETUP.md) | All credential configuration |
| [troubleshooting/terraform-aws.md](troubleshooting/terraform-aws.md) | AWS troubleshooting |
