# Terraform Modules

## Overview

This directory contains reusable Terraform modules for the AWS infrastructure. These modules are used by the unified `environments/aws/` environment, which supports dev/stage/prod deployments from a single codebase.

## Module Inventory

| Module | Status | Description |
|--------|--------|-------------|
| `networking/` | Complete | VPC, subnets, NAT gateway, route tables, VPC flow logs |
| `security-groups/` | Complete | Security groups for ALB, Liberty EC2, ECS, RDS, ElastiCache, monitoring |
| `compute/` | Complete | EC2 Liberty instances with IAM roles, key pairs, CloudWatch logs |
| `database/` | Complete | RDS PostgreSQL, ElastiCache Redis, RDS Proxy, Secrets Manager |
| `ecs/` | Complete | ECS Fargate cluster, service, task definition, auto-scaling, blue-green |
| `loadbalancer/` | Complete | ALB, target groups, listeners, HTTPS/self-signed certs |
| `monitoring/` | Complete | Prometheus/Grafana EC2 with ECS discovery, AlertManager |
| `security-compliance/` | Complete | CloudTrail, GuardDuty, Security Hub, WAF |
| `storage/` | Placeholder | Reserved for future S3/EBS implementations |

## Environment Architecture

The `environments/aws/` directory uses these modules with a unified codebase pattern:

```
environments/aws/
├── backends/
│   ├── dev.backend.hcl      # State: environments/dev/terraform.tfstate
│   ├── stage.backend.hcl    # State: environments/stage/terraform.tfstate
│   └── prod.backend.hcl     # State: environments/prod/terraform.tfstate
├── envs/
│   ├── dev.tfvars           # Minimal resources, no security features
│   ├── stage.tfvars         # Prod-like but smaller scale
│   └── prod.tfvars          # Full HA, security, blue-green
├── main.tf                  # Orchestrates all modules
├── variables.tf             # 55+ variables with validation
├── outputs.tf
└── providers.tf
```

### Usage

```bash
# Initialize for specific environment
cd automated/terraform/environments/aws
terraform init -backend-config=backends/dev.backend.hcl

# Plan/Apply with environment-specific variables
terraform plan -var-file=envs/dev.tfvars
terraform apply -var-file=envs/dev.tfvars

# Switch environments (re-init required)
terraform init -backend-config=backends/prod.backend.hcl -reconfigure
terraform plan -var-file=envs/prod.tfvars
```

## Module Details

### networking/
VPC infrastructure with security best practices:
- Configurable CIDR and availability zones (2-6 AZs)
- Public/private subnet separation
- NAT gateway (single or HA per-AZ)
- VPC flow logs with KMS encryption
- Internet gateway and route tables

### security-groups/
Conditional security group creation:
- ALB, ECS, Liberty EC2, RDS, ElastiCache, monitoring, management, bastion
- Configurable ingress CIDRs
- Optional egress restriction

### compute/
EC2 Liberty instances:
- Auto-scaling across subnets
- IAM roles with SSM and CloudWatch permissions
- SSH key pair management
- CloudWatch log groups
- Configurable instance types and storage

### database/
Managed data stores:
- RDS PostgreSQL with Multi-AZ option
- ElastiCache Redis cluster with AUTH tokens
- RDS Proxy for connection pooling
- Secrets Manager for credentials
- Automated backups and encryption

### ecs/
ECS Fargate deployment:
- Cluster with Container Insights
- Service with circuit breaker
- Task definition with health checks
- Auto-scaling (CPU, memory, request count)
- Fargate Spot capacity provider
- Blue-green deployment support
- X-Ray tracing integration

### loadbalancer/
Application Load Balancer:
- HTTP/HTTPS listeners
- ECS and EC2 target groups
- Self-signed certificate fallback
- Access logging to S3
- Health check configuration
- Sticky sessions support

### monitoring/
Observability stack:
- Prometheus with ECS service discovery
- Grafana with auto-generated credentials
- AlertManager with Slack integration
- CloudWatch log groups
- Static target configuration

### security-compliance/
Security and compliance features:
- CloudTrail with S3 storage
- GuardDuty threat detection
- Security Hub aggregation
- WAF with rate limiting and managed rules
- SNS alerts for security events

## Legacy Environment

The `environments/prod-aws/` directory contains the original production deployment with mostly inline resources. It is being superseded by the unified `environments/aws/` architecture but remains operational.

| Aspect | prod-aws (Legacy) | aws (Current) |
|--------|-------------------|---------------|
| Module usage | 1 of 8 (networking only) | All 8 modules |
| Multi-environment | No | Yes (dev/stage/prod) |
| Backend config | Hardcoded | Partial backend files |
| Maintenance | Higher overhead | Lower overhead |

---

**Last Updated:** 2026-01-06
