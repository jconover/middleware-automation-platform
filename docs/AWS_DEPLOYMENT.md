# AWS Deployment Guide

Deploy Open Liberty application servers to AWS using ECS Fargate or EC2.

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
cd ../environments/prod-aws
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars - set your IP in management_allowed_cidrs

terraform init && terraform apply

# 3. Build and push container
cd ../../..
mvn -f sample-app/pom.xml clean package
podman build -t liberty-app:latest -f containers/liberty/Containerfile .

aws ecr get-login-password --region us-east-1 | \
  podman login --username AWS --password-stdin $(terraform -chdir=automated/terraform/environments/prod-aws output -raw ecr_repository_url | cut -d/ -f1)

ECR_URL=$(terraform -chdir=automated/terraform/environments/prod-aws output -raw ecr_repository_url)
podman tag liberty-app:latest ${ECR_URL}:latest
podman push ${ECR_URL}:latest

# 4. Deploy to ECS
aws ecs update-service --cluster mw-prod-cluster --service mw-prod-liberty --force-new-deployment

# 5. Verify
ALB_DNS=$(terraform -chdir=automated/terraform/environments/prod-aws output -raw alb_dns_name)
curl http://$ALB_DNS/health/ready
```

---

## Architecture

```
                           Internet
                              │
                        ┌─────┴─────┐
                        │    ALB    │  (Public Subnets)
                        └─────┬─────┘
                              │
           ┌──────────────────┴──────────────────┐
           │                                     │
    ┌──────┴──────┐                       ┌──────┴──────┐
    │ ECS Fargate │                       │     EC2     │
    │  (default)  │                       │ (optional)  │
    └──────┬──────┘                       └──────┬──────┘
           │                                     │
           └─────────────────┬───────────────────┘
                             │
                    (Private Subnets)
                             │
              ┌──────────────┴──────────────┐
              │                             │
        ┌─────┴─────┐                 ┌─────┴─────┐
        │    RDS    │                 │   Redis   │
        │ PostgreSQL│                 │ElastiCache│
        └───────────┘                 └───────────┘
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
| ALB | Application LB | Health checks on `/health/ready` |
| ECS Fargate | Serverless | Auto-scales 2-6 tasks |
| RDS | PostgreSQL 15 | Encrypted, auto-scaling storage |
| ElastiCache | Redis 7.0 | Session cache |
| ECR | Container Registry | Liberty images |
| Monitoring | EC2 | Prometheus + Grafana |

---

## Configuration

Edit `automated/terraform/environments/prod-aws/terraform.tfvars`:

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

```bash
# Build application
mvn -f sample-app/pom.xml clean package

# Build container
podman build -t liberty-app:latest -f containers/liberty/Containerfile .

# Login to ECR
aws ecr get-login-password --region us-east-1 | \
  podman login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com

# Push to ECR
ECR_URL=$(terraform -chdir=automated/terraform/environments/prod-aws output -raw ecr_repository_url)
podman tag liberty-app:latest ${ECR_URL}:latest
podman push ${ECR_URL}:latest

# Deploy to ECS
aws ecs update-service --cluster mw-prod-cluster --service mw-prod-liberty --force-new-deployment
```

---

## Operations

### Start/Stop Services

```bash
# Stop all (cost saving)
./automated/scripts/aws-stop.sh

# Start all
./automated/scripts/aws-start.sh

# Full destroy
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
ALB_DNS=$(terraform -chdir=automated/terraform/environments/prod-aws output -raw alb_dns_name)
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

## Monitoring

### URLs

```bash
terraform -chdir=automated/terraform/environments/prod-aws output grafana_url
terraform -chdir=automated/terraform/environments/prod-aws output prometheus_url
```

### Grafana Login

- **Username**: `admin`
- **Password**:
  ```bash
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

### Debug Commands

```bash
# ECS events
aws ecs describe-services --cluster mw-prod-cluster --services mw-prod-liberty \
  --query 'services[0].events[:5]'

# Failed tasks
aws ecs list-tasks --cluster mw-prod-cluster --desired-status STOPPED

# Target health
aws elbv2 describe-target-health --target-group-arn $(terraform output -raw ecs_target_group_arn)
```

---

## Teardown

```bash
# Full destroy
./automated/scripts/aws-stop.sh --destroy

# Or directly
cd automated/terraform/environments/prod-aws
terraform destroy
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
