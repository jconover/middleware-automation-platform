# AWS Deployment Guide

Deploy Open Liberty application servers to AWS using ECS Fargate or EC2.

> **Note:** This guide uses the unified `environments/aws/` environment which supports dev/stage/prod deployments. The legacy `environments/prod-aws/` is deprecated.

---

## Prerequisites

### Required Tools

- **Terraform** >= 1.6.0
- **AWS CLI** v2 - configured with credentials (`aws configure`)
- **Podman** 4.0+ - for building container images
- **Maven** 3.x - for building the sample application (Java 17)

### AWS IAM Permissions

Your AWS user/role needs permissions for:
- EC2, VPC, ECS, ECR, RDS, ElastiCache, ELB, IAM, Secrets Manager, CloudWatch, S3

> **Tip**: Use `AdministratorAccess` for initial setup. Scope down for production.

### SSH Key

```bash
ssh-keygen -t ed25519 -f ~/.ssh/ansible_ed25519 -C "ansible"
```

### Network Access

Add your IP to `management_allowed_cidrs` in `terraform.tfvars`:
```bash
curl -s ifconfig.me
```

---

## Quick Start

```bash
# 1. Bootstrap Terraform state (one-time)
cd automated/terraform/bootstrap
terraform init && terraform apply -auto-approve

# 2. Configure and deploy infrastructure
cd ../environments/aws
# Edit envs/prod.tfvars - set your IP in management_allowed_cidrs

terraform init -backend-config=backends/prod.backend.hcl
terraform plan -var-file=envs/prod.tfvars
terraform apply -var-file=envs/prod.tfvars

# 3. Build and push container (multi-stage build compiles sample-app from source)
cd ../../..
podman build -t liberty-app:1.0.0 -f containers/liberty/Containerfile .

aws ecr get-login-password --region us-east-1 | \
  podman login --username AWS --password-stdin $(terraform -chdir=automated/terraform/environments/aws output -raw ecr_repository_url | cut -d/ -f1)

ECR_URL=$(terraform -chdir=automated/terraform/environments/aws output -raw ecr_repository_url)
podman tag liberty-app:1.0.0 ${ECR_URL}:1.0.0
podman push ${ECR_URL}:1.0.0

# 4. Deploy to ECS
aws ecs update-service --cluster mw-prod-cluster --service mw-prod-liberty --force-new-deployment

# 5. Verify
ALB_DNS=$(terraform -chdir=automated/terraform/environments/aws output -raw alb_dns_name)
curl http://$ALB_DNS/health/ready
```

---

## Multi-Environment Deployment

The unified environment supports dev/stage/prod from a single codebase with isolated state.

### Environment Differences

| Setting | Dev | Stage | Prod |
|---------|-----|-------|------|
| VPC CIDR | 10.10.0.0/16 | 10.20.0.0/16 | 10.30.0.0/16 |
| Availability Zones | 2 | 2 | 3 |
| ECS Tasks | 1-2 | 2-4 | 2-6 |
| Fargate Spot | 80% | 70% | 70% |
| RDS Multi-AZ | No | Yes | Yes |
| RDS Proxy | No | Yes | Yes |
| WAF | No | Yes | Yes |
| GuardDuty | No | Yes | Yes |
| Blue-Green Deploy | No | Yes | Yes |
| S3/ECR Replication | No | No | Yes |

### Switching Environments

```bash
# Development
cd automated/terraform/environments/aws
terraform init -backend-config=backends/dev.backend.hcl
terraform apply -var-file=envs/dev.tfvars

# Staging (use -reconfigure when switching backends)
terraform init -backend-config=backends/stage.backend.hcl -reconfigure
terraform apply -var-file=envs/stage.tfvars

# Production
terraform init -backend-config=backends/prod.backend.hcl -reconfigure
terraform apply -var-file=envs/prod.tfvars
```

---

## Architecture

```
                              Internet
                                 │
                           ┌─────┴─────┐
                           │    WAF    │  AWS Managed Rules
                           └─────┬─────┘
                                 │
                           ┌─────┴─────┐
                           │    ALB    │  (Public Subnets)
                           └─────┬─────┘
                                 │
              ┌──────────────────┼──────────────────┐
              │                  │                  │
       ┌──────┴──────┐    ┌──────┴──────┐    ┌─────┴─────┐
       │ ECS Fargate │    │     EC2     │    │ Monitoring│
       │  (default)  │    │ (optional)  │    │  Server   │
       └──────┬──────┘    └──────┬──────┘    └───────────┘
              │                  │           Prometheus/Grafana
              └────────┬─────────┘
                       │ (Private Subnets)
            ┌──────────┼──────────┐
            │          │          │
       ┌────┴────┐ ┌───┴────┐ ┌───┴───┐
       │   RDS   │ │ Redis  │ │  NAT  │
       │PostgreSQL│ │ElastiCache│ │Gateway│
       └─────────┘ └────────┘ └───────┘

┌─────────────────────────────────────────────────────────┐
│ Security: CloudTrail │ GuardDuty │ Security Hub │ WAF   │
│ Storage:  ECR │ S3 (ALB Logs) │ Secrets Manager        │
└─────────────────────────────────────────────────────────┘
```

### Compute Options

| Mode | Settings | Traffic |
|------|----------|---------|
| ECS Only | `ecs_enabled=true`, `liberty_instance_count=0` | All → Fargate |
| EC2 Only | `ecs_enabled=false`, `liberty_instance_count=2` | All → EC2 |
| Both | `ecs_enabled=true`, `liberty_instance_count=2` | Default→ECS, `X-Target: ec2`→EC2 |

### Components

| Component | Service | Description |
|-----------|---------|-------------|
| VPC | 10.10.0.0/16 | 2 public + 2 private subnets |
| WAF | Web Application Firewall | AWS Managed Rules (OWASP, SQLi, rate limiting) |
| ALB | Application LB | Health checks on `/health/ready`, HTTPS with auto-redirect |
| ECS Fargate | Serverless | Auto-scales 2-6 tasks |
| RDS | PostgreSQL 15 | Encrypted, auto-scaling storage |
| ElastiCache | Redis 7.0 | Session cache with TLS + AUTH token |
| ECR | Container Registry | Liberty images with vulnerability scanning |
| NAT Gateway | Egress | Internet access for private subnets |
| Monitoring | EC2 | Prometheus + Grafana with ECS service discovery |
| Secrets Manager | Credentials | Auto-generated DB, Redis, and Grafana passwords |
| CloudTrail | Audit Logs | API activity logging with S3 + CloudWatch |
| GuardDuty | Threat Detection | Malware protection, security findings |
| Security Hub | Compliance | CIS Benchmarks, AWS Best Practices |

---

## Configuration

Edit `automated/terraform/environments/aws/envs/prod.tfvars` (or `dev.tfvars`/`stage.tfvars` for other environments):

### Compute Selection

| Variable | Default | Description |
|----------|---------|-------------|
| `ecs_enabled` | `true` | Enable ECS Fargate |
| `liberty_instance_count` | `0` | Number of EC2 instances (0 for ECS-only) |

### ECS Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `ecs_task_cpu` | `512` | CPU units (256-4096) |
| `ecs_task_memory` | `1024` | Memory MB |
| `ecs_min_capacity` | `2` | Min tasks |
| `ecs_max_capacity` | `6` | Max tasks |
| `ecs_cpu_target` | `70` | Scale-out CPU % |

### Infrastructure

| Variable | Default | Est. Cost |
|----------|---------|-----------|
| `db_instance_class` | `db.t3.micro` | ~$15/mo |
| `cache_node_type` | `cache.t3.micro` | ~$12/mo |
| `create_monitoring_server` | `true` | ~$30/mo |
| `create_management_server` | `true` | ~$30/mo |

---

## Building and Pushing Containers

The Containerfile uses a multi-stage build that compiles the sample-app from source, so no separate Maven build step is required.

```bash
# Get complete push commands from terraform output
terraform -chdir=automated/terraform/environments/aws output ecr_push_commands

# Or manually:

# Build container (multi-stage build compiles app from source)
podman build -t liberty-app:1.0.0 -f containers/liberty/Containerfile .

# Login to ECR
aws ecr get-login-password --region us-east-1 | \
  podman login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com

# Push to ECR
ECR_URL=$(terraform -chdir=automated/terraform/environments/aws output -raw ecr_repository_url)
podman tag liberty-app:1.0.0 ${ECR_URL}:1.0.0
podman push ${ECR_URL}:1.0.0

# Deploy to ECS
aws ecs update-service --cluster mw-prod-cluster --service mw-prod-liberty --force-new-deployment
```

---

## Operations

### Start/Stop Services

> **Note:** These scripts currently only work with the legacy `environments/prod-aws/` environment. For the unified environment, use terraform directly.

```bash
# Stop all (cost saving) - legacy environment only
./automated/scripts/aws-stop.sh

# Start all - legacy environment only
./automated/scripts/aws-start.sh

# Full destroy - legacy environment only
./automated/scripts/aws-stop.sh --destroy
```

### Scale ECS

```bash
# Scale to 4 tasks
aws ecs update-service --cluster mw-prod-cluster --service mw-prod-liberty --desired-count 4

# Force new deployment
aws ecs update-service --cluster mw-prod-cluster --service mw-prod-liberty --force-new-deployment
```

### View Logs

```bash
# Tail ECS logs
aws logs tail /ecs/mw-prod-liberty --follow

# Recent logs
aws logs tail /ecs/mw-prod-liberty --since 1h
```

### Health Checks

```bash
ALB_DNS=$(terraform -chdir=automated/terraform/environments/aws output -raw alb_dns_name)
curl http://${ALB_DNS}/health/ready
curl http://${ALB_DNS}/health/live
```

### Service Status

```bash
# ECS status
aws ecs describe-services --cluster mw-prod-cluster --services mw-prod-liberty \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}'

# RDS status
aws rds describe-db-instances --db-instance-identifier mw-prod-postgres \
  --query 'DBInstances[0].DBInstanceStatus' --output text
```

---

## Security

### WAF Protection

WAF is enabled in stage and prod environments with:
- AWS Managed Rules (Common, SQLi, Known Bad Inputs)
- Rate limiting (2000-3000 requests per 5 minutes)
- WAF logging to CloudWatch

### Encryption

| Component | Encryption |
|-----------|------------|
| RDS | AES-256 storage encryption |
| ElastiCache | At-rest and in-transit (TLS + AUTH) |
| S3 | AES-256 (ALB logs), KMS (CloudTrail) |
| Secrets | AWS Secrets Manager |

### Compliance (Stage/Prod)

| Service | Purpose |
|---------|---------|
| CloudTrail | API audit logging |
| GuardDuty | Threat detection, malware protection |
| Security Hub | CIS Benchmarks, AWS Best Practices |
| VPC Flow Logs | Network traffic logging |

### Secrets Management

Credentials are auto-generated and stored in AWS Secrets Manager:
```bash
# Grafana password (for prod environment)
aws secretsmanager get-secret-value --secret-id mw-prod/monitoring/grafana-credentials \
  --query SecretString --output text | jq -r .admin_password

# Database credentials
aws secretsmanager get-secret-value --secret-id mw-prod/database/credentials \
  --query SecretString --output text | jq -r '.username, .password'
```

---

## Monitoring

### URLs

```bash
terraform -chdir=automated/terraform/environments/aws output grafana_url
terraform -chdir=automated/terraform/environments/aws output prometheus_url
```

### Grafana Login

- **Username**: `admin`
- **Password**: Stored in Secrets Manager at `mw-{env}/monitoring/grafana-credentials`
  ```bash
  # For prod environment
  aws secretsmanager get-secret-value --secret-id mw-prod/monitoring/grafana-credentials \
    --query SecretString --output text | jq -r .admin_password
  ```

### Liberty Endpoints

| Endpoint | Purpose |
|----------|---------|
| `/health/ready` | Readiness probe |
| `/health/live` | Liveness probe |
| `/metrics` | Prometheus metrics |

### Dashboard

Import `monitoring/grafana/dashboards/ecs-liberty.json` in Grafana.

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| ECS tasks failing | Check logs: `aws logs tail /ecs/mw-prod-liberty --follow` |
| ALB returning 503 | Wait 2-3 min for health checks; verify tasks running |
| Cannot reach ALB | Add your IP to `management_allowed_cidrs` |
| Secret scheduled for deletion | `aws secretsmanager delete-secret --secret-id <id> --force-delete-without-recovery` |
| ECR push denied | Re-run ECR login command |
| ECS stuck deploying | Check logs, fix issue, force new deployment |
| Terraform state lock | Wait for other operation, or `terraform force-unlock <LOCK_ID>` if stuck |
| WAF blocking requests | Check WAF logs in CloudWatch; adjust rules or add IP to allow list |
| Multi-environment state conflict | Use correct backend: `terraform init -backend-config=backends/{env}.backend.hcl -reconfigure` |

### Debug Commands

```bash
# ECS events
aws ecs describe-services --cluster mw-prod-cluster --services mw-prod-liberty \
  --query 'services[0].events[:5]'

# Failed tasks
aws ecs list-tasks --cluster mw-prod-cluster --desired-status STOPPED

# Target health (ECS target group)
aws elbv2 describe-target-health --target-group-arn \
  $(aws elbv2 describe-target-groups --names mw-prod-liberty-ecs-tg \
    --query 'TargetGroups[0].TargetGroupArn' --output text)
```

---

## Teardown

```bash
# Full destroy (legacy environment only)
./automated/scripts/aws-stop.sh --destroy

# For unified environment
cd automated/terraform/environments/aws
terraform destroy -var-file=envs/prod.tfvars
```

### Warnings

- **Data Loss**: Destroys RDS databases, ElastiCache, CloudWatch logs permanently
- **ECR Preserved**: Container images not deleted by default
- **RDS Auto-Restart**: Stopped RDS restarts after 7 days

---

## Cost Estimates

> **Note:** Estimates based on us-east-1 pricing. Actual costs vary by usage.
> For accurate estimates, use the [AWS Pricing Calculator](https://calculator.aws/).
>
> *Last updated: January 2026*

### ECS Fargate (Default) - ~$170/month

| Service | Monthly Cost |
|---------|--------------|
| ECS Fargate (2 tasks, 0.5 vCPU, 1GB) | ~$40-50 |
| Application Load Balancer | ~$20 |
| NAT Gateway | ~$35 |
| RDS db.t3.micro | ~$15 |
| ElastiCache cache.t3.micro | ~$12 |
| EC2 Monitoring (t3.small) | ~$15 |
| EC2 Management/AWX (t3.medium) | ~$30 |
| **Total** | **~$170/month** |

### EC2 Instances (Traditional) - ~$157/month

| Service | Monthly Cost |
|---------|--------------|
| Liberty EC2 (2x t3.small) | ~$30 |
| Application Load Balancer | ~$20 |
| NAT Gateway | ~$35 |
| RDS db.t3.micro | ~$15 |
| ElastiCache cache.t3.micro | ~$12 |
| EC2 Monitoring (t3.small) | ~$15 |
| EC2 Management/AWX (t3.medium) | ~$30 |
| **Total** | **~$157/month** |

See the main [README.md](../README.md#aws-cost-estimate-production) for the authoritative cost breakdown.

### Cost Reduction

| Strategy | Savings |
|----------|---------|
| Stop management server when idle | ~$30/mo |
| Disable monitoring server | ~$30/mo |
| Use `--destroy` when not testing | 100% |
| Fargate Spot for non-prod | 50-70% compute |
