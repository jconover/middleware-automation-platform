# Prerequisites Guide

This document provides a single source of truth for all prerequisites required to deploy the Middleware Automation Platform. Prerequisites are organized by deployment target: universal requirements that apply to all deployments, followed by environment-specific requirements.

---

## Table of Contents

1. [Universal Prerequisites (All Deployments)](#1-universal-prerequisites-all-deployments)
2. [Local Podman Development](#2-local-podman-development)
3. [Local Kubernetes](#3-local-kubernetes)
4. [AWS Production](#4-aws-production)
5. [CI/CD Pipeline](#5-cicd-pipeline)
6. [Verification Script](#6-verification-script)

---

## 1. Universal Prerequisites (All Deployments)

These requirements apply to all deployment options.

### System Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 2 cores | 4+ cores |
| RAM | 4 GB | 8+ GB |
| Disk | 20 GB free | 50+ GB free |
| OS | Linux, macOS, Windows (WSL2) | Linux (Ubuntu 22.04+, Fedora 38+, RHEL 9+) |

### Required Software

| Tool | Minimum Version | Purpose |
|------|-----------------|---------|
| Git | 2.30+ | Clone repository, version control |
| curl | 7.0+ | HTTP requests for verification |
| Java | 17+ | Build sample application |
| Maven | 3.8+ | Build WAR file from source |

### Verification Commands

```bash
# Git
git --version
# Expected: git version 2.30.0 or higher

# curl
curl --version
# Expected: curl 7.x.x or higher

# Java
java --version
# Expected: openjdk 17.x.x or higher

# Maven
mvn --version
# Expected: Apache Maven 3.8.x or higher
```

### Installing Universal Prerequisites

#### Ubuntu/Debian

```bash
sudo apt update
sudo apt install -y git curl openjdk-17-jdk maven
```

#### Fedora/RHEL

```bash
sudo dnf install -y git curl java-17-openjdk java-17-openjdk-devel maven
```

#### macOS (Homebrew)

```bash
brew install git curl openjdk@17 maven
```

---

## 2. Local Podman Development

For single-machine development using containers without Kubernetes orchestration.

**Reference:** [LOCAL_PODMAN_DEPLOYMENT.md](LOCAL_PODMAN_DEPLOYMENT.md)

### Required Software

| Tool | Minimum Version | Purpose |
|------|-----------------|---------|
| Podman | 4.0+ | Container runtime |
| OR Docker | 20.10+ | Alternative container runtime |

> **Note:** Podman is preferred as it runs rootless by default. Docker can be used as an alternative with the same commands.

### Port Requirements

Ensure these ports are available on your local machine:

| Port | Service | Protocol |
|------|---------|----------|
| 9080 | Liberty HTTP | TCP |
| 9443 | Liberty HTTPS | TCP |
| 5432 | PostgreSQL (optional) | TCP |
| 9090 | Prometheus (optional) | TCP |
| 3000 | Grafana (optional) | TCP |

### Verification Commands

```bash
# Podman version
podman --version
# Expected: podman version 4.0.0 or higher

# OR Docker version
docker --version
# Expected: Docker version 20.10.0 or higher

# Verify Podman/Docker can run containers
podman run --rm hello-world
# OR: docker run --rm hello-world

# Check port availability (Linux)
ss -tuln | grep -E ':(9080|9443|5432|9090|3000)\s'
# Expected: No output means ports are available

# Check port availability (macOS)
lsof -i :9080 -i :9443
# Expected: No output means ports are available
```

### Installing Podman

#### Ubuntu/Debian

```bash
sudo apt update
sudo apt install -y podman
```

#### Fedora/RHEL

```bash
sudo dnf install -y podman
```

#### macOS

```bash
brew install podman
podman machine init
podman machine start
```

---

## 3. Local Kubernetes

For multi-node cluster deployments (e.g., homelab, on-premises).

**Reference:** [LOCAL_KUBERNETES_DEPLOYMENT.md](LOCAL_KUBERNETES_DEPLOYMENT.md)

### Required Software

| Tool | Minimum Version | Purpose |
|------|-----------------|---------|
| kubectl | 1.25+ | Kubernetes CLI |
| Helm | 3.0+ | Package manager for Kubernetes |

### Cluster Requirements

| Requirement | Description |
|-------------|-------------|
| Kubernetes Cluster | 1.25+ (k3s, kubeadm, or similar) |
| Nodes | Minimum 1, recommended 3 for HA |
| LoadBalancer | MetalLB for bare-metal, or cloud LB |
| Storage Class | Longhorn, local-path, or cloud storage |

### Optional (Monitoring)

| Tool | Purpose |
|------|---------|
| Prometheus Operator | Automatic metrics collection |
| ServiceMonitor CRD | Liberty metrics integration |

### Verification Commands

```bash
# kubectl version
kubectl version --client
# Expected: Client Version: v1.25.0 or higher

# Verify cluster access
kubectl cluster-info
# Expected: Kubernetes control plane is running at https://...

# List cluster nodes
kubectl get nodes
# Expected: All nodes in Ready state

# Helm version
helm version
# Expected: version.BuildInfo{Version:"v3.x.x"...}

# Verify Helm repos (optional)
helm repo list
# Expected: Lists configured repositories

# Check for LoadBalancer support (MetalLB)
kubectl get pods -n metallb-system
# Expected: metallb controller and speaker pods running

# Check for storage class
kubectl get storageclass
# Expected: At least one storage class with (default) marker

# Check for Prometheus Operator (optional, for monitoring)
kubectl get crd prometheuses.monitoring.coreos.com
# Expected: CRD exists if Prometheus Operator is installed
```

### Installing kubectl

#### Ubuntu/Debian

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

#### macOS

```bash
brew install kubectl
```

### Installing Helm

#### Linux

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

#### macOS

```bash
brew install helm
```

### Installing Prometheus Operator (for Monitoring)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace
```

---

## 4. AWS Production

For production deployments using ECS Fargate or EC2 instances.

**Reference:** [CREDENTIAL_SETUP.md](CREDENTIAL_SETUP.md) for credential configuration

### Required Software

| Tool | Minimum Version | Purpose |
|------|-----------------|---------|
| AWS CLI | 2.0+ | AWS API interactions |
| Terraform | 1.5+ | Infrastructure provisioning |
| Ansible | 2.14+ | Configuration management (EC2 only) |

### AWS Account Requirements

| Requirement | Description |
|-------------|-------------|
| AWS Account | Active account with billing enabled |
| IAM User/Role | Programmatic access with appropriate permissions |
| Region | Supported region (default: us-east-1) |

### Required IAM Permissions

The IAM user or role must have permissions for:

- **EC2**: Create/manage instances, security groups, key pairs
- **ECS**: Create/manage clusters, services, task definitions
- **ECR**: Create/manage repositories, push/pull images
- **RDS**: Create/manage database instances
- **VPC**: Create/manage VPCs, subnets, NAT gateways, route tables
- **ALB**: Create/manage load balancers, target groups, listeners
- **IAM**: Create/manage roles and instance profiles
- **Secrets Manager**: Create/manage secrets
- **CloudWatch**: Create/manage log groups and metrics

> **Tip:** For initial setup, the `AdministratorAccess` policy works. For production, create a least-privilege policy.

### Verification Commands

```bash
# AWS CLI version
aws --version
# Expected: aws-cli/2.x.x or higher

# Verify AWS credentials are configured
aws sts get-caller-identity
# Expected: Returns Account, UserId, and Arn

# Verify AWS region
aws configure get region
# Expected: Your configured region (e.g., us-east-1)

# Terraform version
terraform --version
# Expected: Terraform v1.5.0 or higher

# Verify Terraform can initialize
cd automated/terraform/environments/prod-aws
terraform init -backend=false
# Expected: Terraform has been successfully initialized

# Ansible version
ansible --version
# Expected: ansible [core 2.14.0] or higher

# Verify Ansible can connect locally
ansible localhost -m ping
# Expected: localhost | SUCCESS
```

### Installing AWS Prerequisites

#### AWS CLI v2

```bash
# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# macOS
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /
```

#### Terraform

```bash
# Linux (Ubuntu/Debian)
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# macOS
brew install terraform
```

#### Ansible

```bash
# Linux (Ubuntu/Debian)
sudo apt update
sudo apt install -y ansible

# macOS
brew install ansible

# Via pip (any platform)
pip install ansible
```

### Credential Configuration

Before deploying to AWS, you must configure credentials for all services.

**See [CREDENTIAL_SETUP.md](CREDENTIAL_SETUP.md) for complete instructions covering:**

- AWS CLI credentials (`aws configure`)
- Grafana admin password (auto-generated, stored in Secrets Manager)
- AWX admin password (Kubernetes secret)
- Liberty passwords (Ansible Vault)
- Database credentials (auto-generated via Terraform)

---

## 5. CI/CD Pipeline

For running Jenkins-based CI/CD pipelines.

**Reference:** `ci-cd/Jenkinsfile`

### Jenkins Requirements

| Requirement | Description |
|-------------|-------------|
| Jenkins | 2.387+ with Pipeline plugin |
| Kubernetes Plugin | For dynamic agent pods |
| Credentials Plugin | For secure credential storage |

### Pipeline Agent Requirements

The Jenkins pipeline uses Kubernetes pods with these containers:

| Container | Image | Purpose |
|-----------|-------|---------|
| maven | maven:3.9-eclipse-temurin-17 | Build WAR file |
| podman | quay.io/podman/stable | Build/push container images |
| ansible | ansible/ansible-runner | Run deployment playbooks |

### AWS Credentials in Jenkins

Configure these credentials in Jenkins:

| Credential ID | Type | Purpose |
|---------------|------|---------|
| aws-credentials | AWS Credentials | ECR push, ECS deployment |
| ecr-registry | Username/Password | ECR authentication |
| ansible-vault-password | Secret Text | Decrypt Ansible Vault |

### Verification Commands

```bash
# Verify Jenkins is accessible (if running locally)
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080
# Expected: 200 or 403 (authentication required)

# Verify Kubernetes plugin is available (from Jenkins)
# Navigate to: Manage Jenkins > Plugins > Installed plugins
# Search for: Kubernetes

# Verify AWS credentials are configured
# Navigate to: Manage Jenkins > Credentials
# Look for: aws-credentials
```

### ECR Access Verification

```bash
# Get ECR login token
aws ecr get-login-password --region us-east-1 | podman login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com
# Expected: Login Succeeded

# List ECR repositories
aws ecr describe-repositories
# Expected: Lists available repositories
```

---

## 6. Verification Script

Run this script to verify all prerequisites for your target deployment.

### Quick Verification by Deployment Type

```bash
#!/bin/bash
# Save as: check-prerequisites.sh
# Usage: ./check-prerequisites.sh [all|podman|kubernetes|aws]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_command() {
    local cmd=$1
    local min_version=$2
    local description=$3

    if command -v "$cmd" &> /dev/null; then
        local version=$($cmd --version 2>&1 | head -n1)
        echo -e "${GREEN}[OK]${NC} $cmd: $version"
        return 0
    else
        echo -e "${RED}[MISSING]${NC} $cmd ($description)"
        return 1
    fi
}

check_port() {
    local port=$1
    local service=$2

    if ss -tuln 2>/dev/null | grep -q ":$port " || lsof -i :$port &>/dev/null; then
        echo -e "${YELLOW}[IN USE]${NC} Port $port ($service)"
        return 1
    else
        echo -e "${GREEN}[AVAILABLE]${NC} Port $port ($service)"
        return 0
    fi
}

echo "=========================================="
echo "Middleware Automation Platform Prerequisites"
echo "=========================================="
echo ""

# Universal prerequisites
echo "--- Universal Prerequisites ---"
check_command "git" "2.30" "Version control"
check_command "curl" "7.0" "HTTP client"
check_command "java" "17" "Java runtime"
check_command "mvn" "3.8" "Maven build tool"
echo ""

TARGET=${1:-all}

if [[ "$TARGET" == "all" || "$TARGET" == "podman" ]]; then
    echo "--- Podman Development Prerequisites ---"
    check_command "podman" "4.0" "Container runtime" || check_command "docker" "20.10" "Container runtime (alternative)"
    echo ""
    echo "Port availability:"
    check_port 9080 "Liberty HTTP"
    check_port 9443 "Liberty HTTPS"
    echo ""
fi

if [[ "$TARGET" == "all" || "$TARGET" == "kubernetes" ]]; then
    echo "--- Kubernetes Prerequisites ---"
    check_command "kubectl" "1.25" "Kubernetes CLI"
    check_command "helm" "3.0" "Helm package manager"
    echo ""
    echo "Cluster status:"
    if kubectl cluster-info &>/dev/null; then
        echo -e "${GREEN}[OK]${NC} Kubernetes cluster is accessible"
        kubectl get nodes --no-headers 2>/dev/null | while read line; do
            node=$(echo $line | awk '{print $1}')
            status=$(echo $line | awk '{print $2}')
            echo "     Node: $node - $status"
        done
    else
        echo -e "${RED}[ERROR]${NC} Cannot connect to Kubernetes cluster"
    fi
    echo ""
fi

if [[ "$TARGET" == "all" || "$TARGET" == "aws" ]]; then
    echo "--- AWS Production Prerequisites ---"
    check_command "aws" "2.0" "AWS CLI"
    check_command "terraform" "1.5" "Infrastructure as Code"
    check_command "ansible" "2.14" "Configuration management"
    echo ""
    echo "AWS credentials:"
    if aws sts get-caller-identity &>/dev/null; then
        identity=$(aws sts get-caller-identity --query 'Arn' --output text)
        echo -e "${GREEN}[OK]${NC} AWS credentials configured: $identity"
    else
        echo -e "${RED}[ERROR]${NC} AWS credentials not configured or invalid"
    fi
    echo ""
fi

echo "=========================================="
echo "Verification complete"
echo "=========================================="
```

### Usage

```bash
# Make the script executable
chmod +x check-prerequisites.sh

# Check all prerequisites
./check-prerequisites.sh all

# Check only Podman prerequisites
./check-prerequisites.sh podman

# Check only Kubernetes prerequisites
./check-prerequisites.sh kubernetes

# Check only AWS prerequisites
./check-prerequisites.sh aws
```

### Expected Output (All Prerequisites Met)

```
==========================================
Middleware Automation Platform Prerequisites
==========================================

--- Universal Prerequisites ---
[OK] git: git version 2.43.0
[OK] curl: curl 8.5.0
[OK] java: openjdk 17.0.10
[OK] mvn: Apache Maven 3.9.6

--- Podman Development Prerequisites ---
[OK] podman: podman version 4.9.0

Port availability:
[AVAILABLE] Port 9080 (Liberty HTTP)
[AVAILABLE] Port 9443 (Liberty HTTPS)

--- Kubernetes Prerequisites ---
[OK] kubectl: Client Version: v1.29.0
[OK] helm: version.BuildInfo{Version:"v3.14.0"...}

Cluster status:
[OK] Kubernetes cluster is accessible
     Node: k8s-master-01 - Ready
     Node: k8s-worker-01 - Ready
     Node: k8s-worker-02 - Ready

--- AWS Production Prerequisites ---
[OK] aws: aws-cli/2.15.0
[OK] terraform: Terraform v1.7.0
[OK] ansible: ansible [core 2.16.0]

AWS credentials:
[OK] AWS credentials configured: arn:aws:iam::123456789012:user/deploy-user

==========================================
Verification complete
==========================================
```

---

## Related Documentation

| Document | Description |
|----------|-------------|
| [CREDENTIAL_SETUP.md](CREDENTIAL_SETUP.md) | Complete credential configuration guide |
| [END_TO_END_TESTING.md](END_TO_END_TESTING.md) | Testing guide for all deployment options |
| [LOCAL_KUBERNETES_DEPLOYMENT.md](LOCAL_KUBERNETES_DEPLOYMENT.md) | Kubernetes deployment guide |
| [LOCAL_PODMAN_DEPLOYMENT.md](LOCAL_PODMAN_DEPLOYMENT.md) | Podman deployment guide |
| [../README.md](../README.md) | Main project documentation |
