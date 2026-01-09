# AWS Unified Terraform Environment

Multi-environment AWS infrastructure for the Middleware Automation Platform. Deploy Open Liberty application servers with ECS Fargate, EC2, or both from a single codebase.

---

## Quick Start

```bash
# 1. Navigate to aws environment
cd automated/terraform/environments/aws

# 2. Initialize with environment-specific backend
terraform init -backend-config=backends/dev.backend.hcl

# 3. Review the plan
terraform plan -var-file=envs/dev.tfvars

# 4. Deploy infrastructure
terraform apply -var-file=envs/dev.tfvars

# 5. Get application URL
terraform output app_url
```

> **Important:** Complete [Credential Setup](../../../../docs/CREDENTIAL_SETUP.md) before deploying.

---

## Directory Structure

```
aws/
├── backends/                    # Terraform state backend configs
│   ├── dev.backend.hcl
│   ├── stage.backend.hcl
│   └── prod.backend.hcl
├── envs/                        # Environment variable files
│   ├── dev.tfvars
│   ├── stage.tfvars
│   └── prod.tfvars
├── templates/                   # User-data scripts
│   └── management-user-data.sh
├── main.tf                      # Module orchestration
├── variables.tf                 # Input variables (83 variables)
├── outputs.tf                   # Output definitions (60 outputs)
├── locals.tf                    # Computed values
├── providers.tf                 # AWS provider config
├── versions.tf                  # Terraform/provider versions
├── management.tf                # AWX/Jenkins management server
├── route53.tf                   # DNS failover configuration
├── s3-replication.tf            # Disaster recovery replication
├── slo-alarms.tf                # SLO/SLI CloudWatch alarms
└── xray.tf                      # Distributed tracing
```

---

## Prerequisites

| Tool | Version | Verify |
|------|---------|--------|
| Terraform | >= 1.6.0 | `terraform version` |
| AWS CLI | v2 | `aws --version` |
| Podman/Docker | Latest | `podman version` |

**AWS Requirements:**
- IAM credentials with admin access (or scoped permissions)
- S3 bucket for Terraform state: `middleware-platform-terraform-state`
- DynamoDB table for state locking: `terraform-state-lock`

---

## Compute Options

Choose your deployment model by setting variables in your tfvars file:

| Option | Configuration | Use Case |
|--------|--------------|----------|
| **ECS Fargate** | `ecs_enabled = true`<br>`liberty_instance_count = 0` | Serverless, auto-scaling, lower ops overhead |
| **EC2 Instances** | `ecs_enabled = false`<br>`liberty_instance_count = 2` | Full control, Ansible-managed, lower compute cost |
| **Both** | `ecs_enabled = true`<br>`liberty_instance_count = 2` | Migration, A/B testing, comparison |

> **Tip:** When running both, header-based routing sends traffic to ECS by default. Use `X-Target: ec2` header to route to EC2 instances.

---

## Environment Comparison

| Aspect | Development | Staging | Production |
|--------|-------------|---------|------------|
| **VPC CIDR** | 10.10.0.0/16 | 10.20.0.0/16 | 10.30.0.0/16 |
| **Availability Zones** | 2 | 2 | 3 |
| **NAT Gateway HA** | No | No | Yes (per-AZ) |
| **ECS Task CPU/Memory** | 256 / 512 MB | 512 / 1024 MB | 512 / 1024 MB |
| **ECS Desired Count** | 1 | 2 | 2 |
| **ECS Min/Max** | 1-2 | 2-4 | 2-6 |
| **Fargate Spot Weight** | 80% | 50% | 70% |
| **RDS Instance** | db.t3.micro | db.t3.small | db.t3.small |
| **RDS Multi-AZ** | No | Yes | Yes |
| **RDS Proxy** | No | No | Yes |
| **Backup Retention** | 1 day | 3 days | 7 days |
| **HTTPS** | No | Yes (self-signed) | Yes (ACM cert) |
| **CloudTrail** | No | Yes (30 days) | Yes (90 days) |
| **GuardDuty** | No | Yes | Yes |
| **WAF** | No | Yes | Yes |
| **Blue-Green Deploy** | No | Yes | Yes |
| **Est. Monthly Cost** | ~$150-200 | ~$300-400 | ~$400-500 |

---

## Modules

This environment uses 8 centralized modules from `../../modules/`:

| Module | Purpose | Always Created |
|--------|---------|----------------|
| `networking` | VPC, subnets, NAT gateway, flow logs | Yes |
| `security-groups` | All security groups | Yes |
| `database` | RDS PostgreSQL, ElastiCache, RDS Proxy | Yes |
| `loadbalancer` | ALB, target groups, HTTPS | Yes |
| `ecs` | ECS Fargate cluster, service, ECR | If `ecs_enabled = true` |
| `compute` | EC2 Liberty instances | If `liberty_instance_count > 0` |
| `monitoring` | Prometheus, Grafana, AlertManager | If `create_monitoring_server = true` |
| `security-compliance` | CloudTrail, GuardDuty, WAF | Yes |

---

## Key Variables

### Required Variables

| Variable | Description |
|----------|-------------|
| `environment` | Environment name: `dev`, `stage`, `prod` |
| `management_allowed_cidrs` | CIDR blocks for management access (cannot be 0.0.0.0/0) |

### Compute Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `ecs_enabled` | `true` | Enable ECS Fargate deployment |
| `liberty_instance_count` | `0` | Number of EC2 instances (0 = ECS only) |
| `ecs_task_cpu` | `512` | CPU units: 256, 512, 1024, 2048, 4096 |
| `ecs_task_memory` | `1024` | Memory in MB (must match CPU) |
| `ecs_desired_count` | `2` | Desired ECS tasks |
| `ecs_min_capacity` | `2` | Minimum tasks for auto-scaling |
| `ecs_max_capacity` | `6` | Maximum tasks for auto-scaling |
| `fargate_spot_weight` | `70` | Spot capacity weight (0-80) |

### Database Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `db_instance_class` | `db.t3.micro` | RDS instance type |
| `db_multi_az` | `true` | Enable Multi-AZ |
| `enable_rds_proxy` | `false` | Enable RDS Proxy (~$11/month) |
| `cache_node_type` | `cache.t3.micro` | ElastiCache node type |

### Security & Compliance

| Variable | Default | Description |
|----------|---------|-------------|
| `enable_cloudtrail` | `true` | Enable audit logging |
| `enable_guardduty` | `true` | Enable threat detection |
| `enable_waf` | `true` | Enable WAF on ALB |
| `waf_rate_limit` | `2000` | Requests per 5 minutes per IP |

### Optional Features

| Variable | Default | Description |
|----------|---------|-------------|
| `create_monitoring_server` | `true` | Deploy Prometheus/Grafana |
| `create_management_server` | `false` | Deploy AWX/Jenkins server |
| `enable_blue_green` | `false` | Enable blue-green deployments |
| `enable_slo_alarms` | `false` | Enable SLO/SLI alarms |
| `enable_s3_replication` | `false` | Enable DR replication |
| `enable_route53_failover` | `false` | Enable DNS failover |
| `enable_xray` | `false` | Enable X-Ray tracing |

> **Full variable reference:** See `variables.tf` for all 83 variables with descriptions and validation rules.

---

## Key Outputs

After `terraform apply`, retrieve important values:

```bash
# Application URL
terraform output app_url

# ECR repository for container pushes
terraform output ecr_repository_url

# Ready-to-use ECR push commands
terraform output ecr_push_commands

# Database endpoint (or RDS Proxy if enabled)
terraform output db_effective_endpoint

# Grafana credentials
terraform output grafana_secret_arn

# Full deployment summary
terraform output deployment_summary
```

### Output Categories

| Category | Key Outputs |
|----------|-------------|
| **Networking** | `vpc_id`, `private_subnet_ids`, `nat_gateway_public_ips` |
| **Load Balancer** | `alb_dns_name`, `app_url`, `ecs_target_group_arn` |
| **Database** | `db_effective_endpoint`, `db_secret_arn`, `cache_endpoint` |
| **ECS** | `ecs_cluster_name`, `ecr_repository_url`, `ecs_service_name` |
| **EC2** | `liberty_instance_ids`, `liberty_instance_private_ips` |
| **Monitoring** | `grafana_url`, `prometheus_url`, `monitoring_public_ip` |
| **Security** | `cloudtrail_arn`, `guardduty_detector_id`, `waf_web_acl_arn` |

---

## Operations

### Switch Environments

```bash
# Switch to staging
terraform init -backend-config=backends/stage.backend.hcl -reconfigure
terraform plan -var-file=envs/stage.tfvars

# Switch to production
terraform init -backend-config=backends/prod.backend.hcl -reconfigure
terraform plan -var-file=envs/prod.tfvars
```

### Deploy New Container Image

```bash
# Build and push (commands from terraform output)
$(terraform output -raw ecr_push_commands)

# Force ECS to pull new image
aws ecs update-service \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --service $(terraform output -raw ecs_service_name) \
  --force-new-deployment
```

### Scale ECS Service

```bash
# Scale to 4 tasks
aws ecs update-service \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --service $(terraform output -raw ecs_service_name) \
  --desired-count 4
```

### Access Monitoring

```bash
# Get URLs
terraform output grafana_url
terraform output prometheus_url

# Retrieve Grafana password
aws secretsmanager get-secret-value \
  --secret-id $(terraform output -raw grafana_secret_arn) \
  --query SecretString --output text | jq -r .admin_password
```

### Teardown

```bash
# Destroy all resources (careful!)
terraform destroy -var-file=envs/dev.tfvars
```

---

## Cost Estimates

| Component | Dev | Stage | Prod |
|-----------|-----|-------|------|
| NAT Gateway | $32 | $32 | $96 (3 AZs) |
| ECS Fargate | $15-30 | $40-80 | $60-120 |
| RDS PostgreSQL | $15 | $30 | $60 |
| ElastiCache | $12 | $12 | $25 |
| ALB | $20 | $20 | $20 |
| Monitoring EC2 | $8 | $15 | $15 |
| CloudTrail/GuardDuty | $0 | $20 | $30 |
| **Total (est.)** | **$100-150** | **$170-210** | **$300-400** |

> **Note:** Costs vary by usage. Use [AWS Pricing Calculator](https://calculator.aws/) for accurate estimates. Fargate Spot can reduce ECS costs by 50-70%.

---

## Related Documentation

| Document | Description |
|----------|-------------|
| [AWS Deployment Guide](../../../../docs/AWS_DEPLOYMENT.md) | Complete deployment walkthrough |
| [Credential Setup](../../../../docs/CREDENTIAL_SETUP.md) | Required credential configuration |
| [Prerequisites](../../../../docs/PREREQUISITES.md) | Tool installation guide |
| [Terraform Troubleshooting](../../../../docs/troubleshooting/terraform-aws.md) | Common issues and solutions |
| [ECS Migration Plan](../../../../docs/plans/ecs-migration-plan.md) | EC2 to ECS migration guide |
| [End-to-End Testing](../../../../docs/END_TO_END_TESTING.md) | Validation procedures |

---

## Architecture

```
                                    ┌─────────────────────────────────────────────┐
                                    │                   VPC                       │
                                    │              (10.x.0.0/16)                  │
┌──────────┐                        │  ┌─────────────────────────────────────┐   │
│ Internet │◄───────────────────────┼──│         Application Load Balancer   │   │
└──────────┘                        │  └──────────────┬──────────────────────┘   │
                                    │                 │                           │
                                    │    ┌────────────┴────────────┐              │
                                    │    ▼                         ▼              │
                                    │  ┌─────────────┐   ┌─────────────┐         │
                                    │  │ ECS Fargate │   │ EC2 Liberty │         │
                                    │  │  (2-6 tasks)│   │ (optional)  │         │
                                    │  └──────┬──────┘   └──────┬──────┘         │
                                    │         │                 │                 │
                                    │         └────────┬────────┘                 │
                                    │                  ▼                          │
                                    │  ┌─────────────────────────────────────┐   │
                                    │  │   RDS PostgreSQL  │  ElastiCache    │   │
                                    │  │    (Multi-AZ)     │    (Redis)      │   │
                                    │  └─────────────────────────────────────┘   │
                                    └─────────────────────────────────────────────┘
```

---

*Last updated: January 2026*
