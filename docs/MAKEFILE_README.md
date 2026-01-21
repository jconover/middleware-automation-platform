# Makefile Reference Guide

This document provides comprehensive documentation for the Middleware Automation Platform Makefile, including all targets, configuration options, and deployment workflows.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start Guides](#quick-start-guides)
- [Configuration Variables](#configuration-variables)
- [Terraform Commands](#terraform-commands)
- [Container Build & Push](#container-build--push)
- [Kubernetes Commands](#kubernetes-commands)
- [AWS Operations](#aws-operations)
- [Deployment Workflows](#deployment-workflows)
- [Monitoring Stack](#monitoring-stack)
- [Security & Compliance](#security--compliance)

---

## Prerequisites

### Required CLI Tools

#### Core Tools (Required for most operations)

| Tool | Minimum Version | Purpose | Installation |
|------|-----------------|---------|--------------|
| **make** | 4.0+ | Build automation | `apt install make` / `brew install make` |
| **git** | 2.0+ | Version control, image tagging | `apt install git` / `brew install git` |
| **curl** | 7.0+ | Health checks, API calls | Usually pre-installed |
| **jq** | 1.6+ | JSON parsing for monitoring queries | `apt install jq` / `brew install jq` |

#### Container Runtime (Choose one)

| Tool | Purpose | Installation |
|------|---------|--------------|
| **podman** (default) | Container builds, local development | `apt install podman` / `brew install podman` |
| **docker** | Alternative container runtime | https://docs.docker.com/engine/install/ |

#### Infrastructure as Code

| Tool | Minimum Version | Purpose | Installation |
|------|-----------------|---------|--------------|
| **terraform** | 1.5+ | AWS infrastructure provisioning | https://developer.hashicorp.com/terraform/install |
| **aws-cli** | 2.0+ | AWS service management | https://aws.amazon.com/cli/ |

#### Configuration Management

| Tool | Minimum Version | Purpose | Installation |
|------|-----------------|---------|--------------|
| **ansible** | 2.15+ | Server configuration, deployments | `pip install ansible` |
| **ansible-lint** | 6.0+ | Ansible playbook linting | `pip install ansible-lint` |

#### Kubernetes Tools

| Tool | Minimum Version | Purpose | Installation |
|------|-----------------|---------|--------------|
| **kubectl** | 1.28+ | Kubernetes cluster management | https://kubernetes.io/docs/tasks/tools/ |
| **helm** | 3.12+ | Kubernetes package management | https://helm.sh/docs/intro/install/ |

#### Application Build

| Tool | Minimum Version | Purpose | Installation |
|------|-----------------|---------|--------------|
| **maven** | 3.9+ | Java application builds | `apt install maven` / `brew install maven` |
| **java** | JDK 17+ | Java compilation | `apt install openjdk-17-jdk` |

#### Security Scanning (Optional)

| Tool | Purpose | Installation |
|------|---------|--------------|
| **trivy** | Container vulnerability scanning | https://aquasecurity.github.io/trivy/ |
| **grype** | Alternative container scanner | https://github.com/anchore/grype |
| **tfsec** | Terraform security scanning | `brew install tfsec` |
| **checkov** | IaC security scanning | `pip install checkov` |
| **semgrep** | SAST for application code | `pip install semgrep` |
| **gitleaks** | Secret leak detection | https://github.com/gitleaks/gitleaks |

### AWS Configuration

Configure AWS credentials using one of the following methods:

```bash
# Option 1: AWS CLI configuration (recommended)
aws configure

# Option 2: Environment variables
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-east-1"
```

### Verification

```bash
make dev-setup     # Checks for required tools
make versions      # Shows installed tool versions
make info          # Shows current environment configuration
```

---

## Quick Start Guides

### 1. Local Development (Podman)

The fastest way to get Liberty running locally:

```bash
# One-command quick start
make quick-start

# Or step-by-step:
make container-build                # Build Liberty container image
make container-run                  # Run container (ports 9080, 9443)
make container-health               # Verify health endpoints
```

**Access points:**
- Application: http://localhost:9080
- Health: http://localhost:9080/health/ready
- Metrics: http://localhost:9080/metrics

### 2. AWS ECS Deployment

**First-time setup:**

```bash
# Step 1: Bootstrap Terraform backend (one-time only)
make tf-bootstrap

# Step 2: Create infrastructure
make tf-plan ENV=dev               # Review planned changes
make tf-apply ENV=dev              # Apply infrastructure

# Step 3: Build and push container to ECR
make ecr-push ENV=dev

# Step 4: Deploy to ECS
make ecs-deploy ENV=dev
make ecs-status ENV=dev            # Verify deployment
```

**Subsequent deployments:**

```bash
make deploy-aws-ecs ENV=dev        # Single command: build + push + deploy
```

### 3. AWS EC2 Deployment

```bash
# First-time: Create infrastructure with EC2 instances
make tf-apply ENV=dev

# Deploy via Ansible
make deploy-aws-ec2 ENV=dev        # Single command: build + push + ansible
```

### 4. Homelab Kubernetes

```bash
# Ensure correct kubectl context
make k8s-use-homelab

# Build and push to Docker Hub
make dockerhub-push

# Deploy Liberty
make k8s-deploy-local

# Or single command:
make deploy-local
```

**Homelab service endpoints:**

| Service | URL |
|---------|-----|
| Liberty | http://192.168.68.200:9080 |
| Prometheus | http://192.168.68.201:9090 |
| Grafana | http://192.168.68.202:3000 |
| Alertmanager | http://192.168.68.203:9093 |
| Loki | http://192.168.68.204:3100 |

### 5. Full Stack Deployment

```bash
# Infrastructure + Application in one command
make deploy-full ENV=dev
```

---

## Configuration Variables

| Variable | Default | Description | Example |
|----------|---------|-------------|---------|
| `ENV` | `dev` | Target environment (dev, stage, prod) | `make tf-plan ENV=prod` |
| `VERSION` | Git short hash | Container image tag | `make container-build VERSION=1.2.3` |
| `CONTAINER_RUNTIME` | `podman` | Container runtime (podman/docker) | `make container-build CONTAINER_RUNTIME=docker` |
| `AWS_REGION` | `us-east-1` | AWS region for operations | `make ecs-deploy AWS_REGION=us-west-2` |
| `AWS_ACCOUNT_ID` | Auto-detected | AWS account ID | `make ecr-push AWS_ACCOUNT_ID=123456789012` |
| `DOCKER_HUB_USER` | `jconover` | Docker Hub username | `make dockerhub-push DOCKER_HUB_USER=myuser` |
| `K8S_NAMESPACE` | `liberty` | Kubernetes namespace | `make k8s-status K8S_NAMESPACE=liberty-dev` |
| `MONITORING_NAMESPACE` | `monitoring` | Monitoring stack namespace | `make k8s-deploy-monitoring MONITORING_NAMESPACE=observability` |
| `REPLICAS` | (required) | K8s replica count | `make k8s-scale REPLICAS=3` |
| `COUNT` | (required) | ECS task count | `make ecs-scale COUNT=4` |
| `SECRET` | (required) | Secrets Manager secret name | `make secrets-get SECRET=mw-prod-db-password` |

**Multiple variables can be combined:**
```bash
make deploy-aws-ecs ENV=prod VERSION=2.0.0 AWS_REGION=eu-west-1
```

---

## Terraform Commands

### Core Targets

| Target | Description | Example |
|--------|-------------|---------|
| `tf-bootstrap` | Create S3/DynamoDB backend (one-time) | `make tf-bootstrap` |
| `tf-init` | Initialize Terraform for environment | `make tf-init ENV=dev` |
| `tf-plan` | Generate execution plan | `make tf-plan ENV=dev` |
| `tf-apply` | Apply saved plan | `make tf-apply ENV=dev` |
| `tf-apply-auto` | Apply with auto-approve | `make tf-apply-auto ENV=dev` |
| `tf-destroy` | Destroy infrastructure | `make tf-destroy ENV=dev` |
| `tf-output` | Show Terraform outputs | `make tf-output` |
| `tf-state-list` | List state resources | `make tf-state-list` |
| `tf-refresh` | Sync state with reality | `make tf-refresh ENV=dev` |

### Validation & Security

| Target | Description |
|--------|-------------|
| `tf-validate` | Validate configuration syntax |
| `tf-fmt` | Format Terraform files |
| `tf-fmt-check` | Check formatting (CI) |
| `tf-security-scan` | tfsec security scan |
| `tf-checkov` | Checkov compliance scan |
| `tf-docs` | Generate documentation |
| `tf-cost` | Estimate costs (requires Infracost) |

### Legacy Environment

| Target | Description |
|--------|-------------|
| `tf-legacy-init` | Initialize legacy prod-aws |
| `tf-legacy-plan` | Plan legacy environment |
| `tf-legacy-apply` | Apply legacy environment |
| `tf-legacy-destroy` | Destroy legacy environment |

---

## Container Build & Push

### Build Targets

| Target | Description | Example |
|--------|-------------|---------|
| `container-build` | Build Liberty image | `make container-build VERSION=1.0.0` |
| `container-build-no-cache` | Build without cache | `make container-build-no-cache` |
| `container-run` | Run container locally | `make container-run` |
| `container-stop` | Stop local container | `make container-stop` |
| `container-logs` | View container logs | `make container-logs` |
| `container-shell` | Shell into container | `make container-shell` |
| `container-health` | Check health endpoints | `make container-health` |

### Security Scanning

| Target | Description |
|--------|-------------|
| `container-scan` | Scan with Trivy |
| `container-scan-grype` | Scan with Grype |

### ECR Operations

| Target | Description | Example |
|--------|-------------|---------|
| `ecr-login` | Login to AWS ECR | `make ecr-login` |
| `ecr-push` | Build and push to ECR | `make ecr-push ENV=prod VERSION=1.0.0` |
| `ecr-list` | List ECR images | `make ecr-list ENV=dev` |

**ECR repository naming:** `mw-{ENV}-liberty` (e.g., `mw-dev-liberty`, `mw-prod-liberty`)

### Docker Hub Operations

| Target | Description |
|--------|-------------|
| `dockerhub-login` | Login to Docker Hub |
| `dockerhub-push` | Build and push to Docker Hub |

---

## Kubernetes Commands

### Context Management

| Target | Description |
|--------|-------------|
| `k8s-context` | Show current context |
| `k8s-contexts` | List all contexts |
| `k8s-use-homelab` | Switch to homelab context |
| `k8s-ns` | List namespaces |
| `k8s-nodes` | List cluster nodes |
| `k8s-pods` | List all pods |
| `k8s-services` | List all services |

### Deployment Targets

| Target | Namespace | Description |
|--------|-----------|-------------|
| `k8s-deploy-local` | `liberty` | Deploy to local homelab |
| `k8s-deploy-dev` | `liberty-dev` | Deploy to dev environment |
| `k8s-deploy-prod` | `liberty-prod` | Deploy to prod environment |
| `k8s-deploy-aws` | `liberty-aws` | Deploy to AWS overlay |
| `k8s-delete-local` | `liberty` | Delete local deployment |

### Workload Management

| Target | Description | Example |
|--------|-------------|---------|
| `k8s-status` | Show deployment status | `make k8s-status` |
| `k8s-logs` | Stream pod logs | `make k8s-logs` |
| `k8s-describe` | Describe pods | `make k8s-describe` |
| `k8s-shell` | Shell into pod | `make k8s-shell` |
| `k8s-restart` | Restart deployment | `make k8s-restart` |
| `k8s-rollout-status` | Check rollout status | `make k8s-rollout-status` |
| `k8s-rollback` | Rollback deployment | `make k8s-rollback` |
| `k8s-scale` | Scale deployment | `make k8s-scale REPLICAS=3` |

### Port Forwarding

| Target | Local Port | Service |
|--------|------------|---------|
| `k8s-port-forward-liberty` | 9080 | Liberty |
| `k8s-port-forward-prometheus` | 9090 | Prometheus |
| `k8s-port-forward-grafana` | 3000 | Grafana |
| `k8s-port-forward-alertmanager` | 9093 | Alertmanager |

---

## AWS Operations

### ECS Operations

| Target | Description | Example |
|--------|-------------|---------|
| `ecs-deploy` | Force new deployment | `make ecs-deploy ENV=dev` |
| `ecs-status` | Show service status | `make ecs-status ENV=dev` |
| `ecs-tasks` | List running tasks | `make ecs-tasks ENV=dev` |
| `ecs-logs` | Tail CloudWatch logs | `make ecs-logs ENV=dev` |
| `ecs-scale` | Scale task count | `make ecs-scale ENV=dev COUNT=3` |
| `ecs-stop` | Scale to 0 | `make ecs-stop ENV=dev` |
| `rollback-ecs` | Rollback to previous | `make rollback-ecs ENV=dev` |

### EC2 Operations

| Target | Description |
|--------|-------------|
| `ec2-list` | List tagged EC2 instances |
| `ec2-start` | Start stopped instances |
| `ec2-stop` | Stop running instances |

### RDS Operations

| Target | Description | Example |
|--------|-------------|---------|
| `rds-status` | Show RDS status | `make rds-status` |
| `rds-start` | Start RDS instance | `make rds-start ENV=dev` |
| `rds-stop` | Stop RDS instance | `make rds-stop ENV=dev` |
| `rds-snapshot` | Create snapshot | `make rds-snapshot ENV=dev` |

### Other AWS Services

| Target | Description |
|--------|-------------|
| `elasticache-status` | Show ElastiCache status |
| `alb-status` | Show ALB status |
| `alb-targets` | Show target health |

### Cost Management

| Target | Description |
|--------|-------------|
| `aws-start` | Start all AWS services |
| `aws-stop` | Stop all AWS services |
| `aws-destroy` | Destroy all infrastructure |
| `aws-costs` | Show current month costs |

### Secrets Manager

| Target | Description | Example |
|--------|-------------|---------|
| `secrets-list` | List secrets | `make secrets-list` |
| `secrets-get` | Get secret value | `make secrets-get SECRET=mw-dev-db` |
| `secrets-rotate` | Rotate secret | `make secrets-rotate SECRET=mw-dev-db` |

---

## Deployment Workflows

### deploy-aws-ecs

Build, push to ECR, and deploy to ECS Fargate.

```
deploy-aws-ecs
  └── ecr-push
  │     └── container-build
  │     └── ecr-login
  └── ecs-deploy
```

```bash
make deploy-aws-ecs ENV=prod VERSION=1.2.0
```

### deploy-aws-ec2

Build, push to ECR, and deploy to EC2 via Ansible.

```
deploy-aws-ec2
  └── ecr-push
  │     └── container-build
  │     └── ecr-login
  └── ansible-deploy
```

```bash
make deploy-aws-ec2 ENV=prod VERSION=1.2.0
```

### deploy-full

Complete infrastructure provisioning and application deployment.

```
deploy-full
  └── tf-apply-auto
  └── deploy-aws-ecs
```

```bash
make deploy-full ENV=prod VERSION=1.2.0
```

### deploy-local

Build container and deploy to local Kubernetes.

```
deploy-local
  └── container-build
  └── k8s-deploy-local
```

```bash
make deploy-local VERSION=1.2.0
```

---

## Monitoring Stack

### Deployment Targets

| Target | Description |
|--------|-------------|
| `k8s-deploy-monitoring` | Deploy Prometheus/Grafana stack |
| `k8s-deploy-servicemonitor` | Deploy Liberty ServiceMonitor |
| `k8s-deploy-prometheusrule` | Deploy Liberty alerting rules |
| `k8s-deploy-loki` | Deploy Loki log aggregation |
| `k8s-deploy-promtail` | Deploy Promtail log collector |
| `k8s-delete-monitoring` | Remove monitoring stack |

### Prometheus Queries

| Target | Description |
|--------|-------------|
| `prom-query` | Execute PromQL query |
| `prom-targets` | List scrape targets |
| `prom-alerts` | List active alerts |
| `prom-rules` | List alerting rules |
| `prom-liberty-up` | Check Liberty targets |
| `prom-liberty-requests` | Query request rate |
| `prom-liberty-latency` | Query p95 latency |

### Grafana

| Target | Description |
|--------|-------------|
| `grafana-open` | Open Grafana in browser |
| `grafana-dashboards` | List dashboards |
| `grafana-datasources` | List datasources |
| `grafana-import-dashboard` | Import dashboard JSON |

### Loki Logs

| Target | Description | Example |
|--------|-------------|---------|
| `loki-query` | Execute LogQL query | `make loki-query QUERY='{app="liberty"}'` |
| `loki-liberty-logs` | Get Liberty logs | `make loki-liberty-logs` |
| `loki-liberty-errors` | Get Liberty errors | `make loki-liberty-errors` |
| `loki-labels` | List available labels | `make loki-labels` |
| `loki-ready` | Check Loki readiness | `make loki-ready` |

### Alertmanager

| Target | Description |
|--------|-------------|
| `alertmanager-alerts` | List active alerts |
| `alertmanager-silences` | List silences |
| `alertmanager-silence` | Create silence |

### Recommended Deployment Order

```bash
make k8s-deploy-monitoring       # 1. Deploy Prometheus/Grafana
make k8s-deploy-loki             # 2. Deploy Loki
make k8s-deploy-promtail         # 3. Deploy Promtail
make k8s-deploy-servicemonitor   # 4. Add Liberty to Prometheus
make k8s-deploy-prometheusrule   # 5. Deploy alerting rules
```

---

## Security & Compliance

### Comprehensive Security Scan

```bash
make security-scan-all           # Run all security checks
```

### Container Security

| Target | Description |
|--------|-------------|
| `container-scan` | Trivy vulnerability scan |
| `container-scan-grype` | Grype vulnerability scan |
| `security-sbom` | Generate SBOM |

### Infrastructure Security

| Target | Description |
|--------|-------------|
| `tf-security-scan` | tfsec scan |
| `tf-checkov` | Checkov compliance scan |

### Application Security

| Target | Description |
|--------|-------------|
| `security-sast` | Semgrep SAST scan |
| `security-secrets-scan` | Gitleaks secret detection |
| `security-deps` | Dependency vulnerability scan |

### AWS Security

| Target | Description |
|--------|-------------|
| `security-guardduty` | GuardDuty findings |
| `security-securityhub` | Security Hub findings |

### Ansible Vault

| Target | Description |
|--------|-------------|
| `vault-encrypt` | Encrypt file |
| `vault-decrypt` | Decrypt file |
| `vault-edit` | Edit encrypted file |
| `vault-view` | View encrypted file |

### Kubernetes Security

| Target | Description |
|--------|-------------|
| `k8s-deploy-netpol` | Deploy network policies |
| `k8s-delete-netpol` | Remove network policies |
| `k8s-create-tls-secret` | Create TLS secret |
| `k8s-secrets` | List all secrets |

### CI/CD Security

| Target | Description |
|--------|-------------|
| `pre-commit` | Run pre-commit checks |
| `ci-local` | Run local CI pipeline |

### Recommended Security Workflow

```bash
# During development
make pre-commit
make security-secrets-scan

# Before merging
make ci-local
make security-scan-all

# Before deployment
make tf-security-scan
make container-scan

# Regular maintenance
make security-deps              # Weekly
make security-guardduty         # Monitor threats
```

---

## Quick Reference

### Most Common Commands

```bash
# Local development
make quick-start                 # Build and run locally
make container-health            # Check health

# AWS ECS
make deploy-aws-ecs ENV=dev      # Deploy to ECS
make ecs-status ENV=dev          # Check status
make ecs-logs ENV=dev            # View logs

# Kubernetes
make deploy-local                # Deploy to local K8s
make k8s-status                  # Check status

# Infrastructure
make tf-plan ENV=dev             # Plan changes
make tf-apply ENV=dev            # Apply changes

# Cost management
make aws-stop                    # Stop all (save costs)
make aws-start                   # Start all
```

### Help

```bash
make help                        # Show all available targets
make endpoints                   # Show all service URLs
```
