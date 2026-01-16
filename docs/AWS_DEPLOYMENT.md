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

## Database Migrations

The Jenkins pipeline includes Flyway database migration support that runs automatically before application deployment. Migrations are versioned SQL scripts that ensure database schema changes are applied consistently across environments.

### How It Works

1. **Pipeline Integration**: The "Database Migration" stage runs after tests pass but before deployment
2. **Validation First**: Flyway validates all pending migrations before applying them
3. **Atomic Execution**: Migrations run in order and are recorded in a `flyway_schema_history` table
4. **Automatic Rollback Prevention**: The pipeline blocks deployment if migrations fail

### Migration File Location

Migration files are located in:
```
sample-app/src/main/resources/db/migration/
```

**Current migrations:**
| File | Description |
|------|-------------|
| `V1__create_schema.sql` | Initial schema: users, roles, sessions, API keys, sample data |
| `V2__add_audit_tables.sql` | Audit logging tables for compliance and security |

### Naming Convention

Files must follow Flyway's naming convention:
```
V{version}__{description}.sql

Examples:
V1__create_schema.sql
V2__add_audit_tables.sql
V3__add_notifications_table.sql
```

- **Version**: Sequential number (V1, V2, V3...)
- **Separator**: Double underscore (`__`)
- **Description**: Snake_case description of the change

### Credential Retrieval

**AWS (prod-aws environment):**
Credentials are retrieved from AWS Secrets Manager at runtime:
```bash
# Secret path pattern: mw-{env}/database/credentials
aws secretsmanager get-secret-value \
  --secret-id mw-prod/database/credentials \
  --query SecretString --output text | jq -r '.host, .dbname, .username'
```

The pipeline extracts `host`, `port`, `dbname`, `username`, and `password` from the secret and constructs the JDBC URL automatically.

**Non-AWS environments (dev, staging):**
Credentials are stored in Jenkins as:
- `db-credentials-{environment}` - Username/password credential
- `db-url-{environment}` - JDBC URL string credential

### Running Migrations Manually

If you need to run migrations outside the pipeline:

```bash
# From the sample-app directory
cd sample-app

# Set environment variables
export FLYWAY_URL="jdbc:postgresql://your-db-host:5432/your-db-name"
export FLYWAY_USER="your-username"
export FLYWAY_PASSWORD="your-password"

# Validate pending migrations (dry run)
mvn flyway:validate -B

# View migration status
mvn flyway:info -B

# Apply pending migrations
mvn flyway:migrate -B

# View current schema version
mvn flyway:info -B
```

**For AWS RDS:**
```bash
# Get credentials from Secrets Manager
DB_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id mw-prod/database/credentials \
  --query SecretString --output text)

export FLYWAY_URL="jdbc:postgresql://$(echo $DB_SECRET | jq -r '.host'):5432/$(echo $DB_SECRET | jq -r '.dbname')"
export FLYWAY_USER=$(echo $DB_SECRET | jq -r '.username')
export FLYWAY_PASSWORD=$(echo $DB_SECRET | jq -r '.password')

cd sample-app
mvn flyway:migrate -B
```

### Best Practices

**Writing Migrations:**
1. **Idempotent when possible**: Use `CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`
2. **Backward compatible**: New columns should have defaults or be nullable
3. **Small and focused**: One logical change per migration
4. **Include comments**: Document the purpose and any considerations
5. **Test locally first**: Run migrations against a local database before committing

**Schema Changes:**
| Change Type | Approach |
|-------------|----------|
| Add column | `ALTER TABLE ... ADD COLUMN ... DEFAULT ...` |
| Drop column | Deploy app changes first, then drop in separate migration |
| Rename column | Create new column, copy data, update app, drop old column |
| Add index | Use `CREATE INDEX CONCURRENTLY` for large tables |

**Things to Avoid:**
- Never modify an already-applied migration (causes checksum mismatch)
- Never use `flyway:clean` in production (drops all objects)
- Never commit migrations with syntax errors (validate locally first)

### Troubleshooting Migrations

| Issue | Solution |
|-------|----------|
| Checksum mismatch | Someone modified an applied migration. Use `flyway:repair` with caution, or restore the original file |
| Migration failed | Fix the SQL, increment version (V3 becomes V4), and redeploy |
| Out of order | Set `flyway.outOfOrder=true` in `pom.xml` (not recommended for prod) |
| Connection timeout | Check security groups allow access from Jenkins pod to RDS |

**Repair Command (use with caution):**
```bash
# Only use if you understand the implications
mvn flyway:repair \
  -Dflyway.url="${FLYWAY_URL}" \
  -Dflyway.user="${FLYWAY_USER}" \
  -Dflyway.password="${FLYWAY_PASSWORD}"
```

### Flyway Configuration

The Flyway Maven plugin is configured in `sample-app/pom.xml`:

| Setting | Value | Description |
|---------|-------|-------------|
| `flyway.schemas` | `public` | Target schema |
| `flyway.locations` | `classpath:db/migration` | Migration file location |
| `flyway.baselineOnMigrate` | `false` | Don't auto-baseline |
| `flyway.validateOnMigrate` | `true` | Validate before applying |
| `flyway.cleanDisabled` | `true` | Prevent accidental `clean` |

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

### Rollback Procedures

#### Automatic Rollback (Jenkins Pipeline)

The Jenkins pipeline (`ci-cd/Jenkinsfile`) includes automatic rollback support for ECS deployments:

1. **Before deployment**: The pipeline captures the current task definition ARN
2. **On failure**: If the ECS deployment or health check fails, the pipeline automatically rolls back to the previous task definition
3. **Notification**: Slack notifications include rollback status when configured

The rollback triggers when:
- ECS service fails to stabilize after `update-service --force-new-deployment`
- Health checks fail after deployment (readiness probe, API info endpoint)

**Pipeline environment variables used for rollback:**
- `PREVIOUS_TASK_DEF_ARN`: Stores the task definition ARN before deployment
- `ECS_DEPLOYMENT_ATTEMPTED`: Flag indicating if deployment was attempted (for notification purposes)

#### Manual Rollback Commands

If you need to manually roll back outside the pipeline:

```bash
# 1. List recent task definition revisions
aws ecs list-task-definitions \
  --family-prefix mw-prod-liberty \
  --sort DESC \
  --max-items 5

# 2. Identify the previous working revision (e.g., mw-prod-liberty:42)
#    You can also check the ECS console for deployment history

# 3. Get details of a specific task definition to verify it's the correct one
aws ecs describe-task-definition \
  --task-definition mw-prod-liberty:42 \
  --query 'taskDefinition.{revision:revision,image:containerDefinitions[0].image,cpu:cpu,memory:memory}'

# 4. Roll back to the previous task definition
aws ecs update-service \
  --cluster mw-prod-cluster \
  --service mw-prod-liberty \
  --task-definition mw-prod-liberty:42 \
  --region us-east-1

# 5. Wait for rollback to complete
aws ecs wait services-stable \
  --cluster mw-prod-cluster \
  --services mw-prod-liberty \
  --region us-east-1

# 6. Verify the rollback
aws ecs describe-services \
  --cluster mw-prod-cluster \
  --services mw-prod-liberty \
  --query 'services[0].{status:status,running:runningCount,desired:desiredCount,taskDef:taskDefinition}'
```

#### Identifying the Previous Task Definition

To find which task definition to roll back to:

```bash
# View recent deployments with timestamps
aws ecs describe-services \
  --cluster mw-prod-cluster \
  --services mw-prod-liberty \
  --query 'services[0].deployments[*].{id:id,status:status,taskDef:taskDefinition,created:createdAt,running:runningCount}' \
  --output table

# List all revisions for the task definition family
aws ecs list-task-definitions \
  --family-prefix mw-prod-liberty \
  --status ACTIVE \
  --sort DESC
```

**Tip**: The ECS console (AWS Console > ECS > Clusters > mw-prod-cluster > Services > mw-prod-liberty > Deployments) provides a visual history of deployments with status and timestamps.

#### Database Rollback Considerations (Flyway)

The pipeline uses Flyway for database migrations. **Database migrations are NOT automatically rolled back** when an ECS deployment fails. This is by design because:

1. Database changes may have already been committed
2. Rollback scripts require careful planning and testing
3. Some migrations (data transformations) cannot be safely reversed

**Before deploying database changes:**

1. **Test migrations thoroughly** in dev/staging environments
2. **Create rollback scripts** for reversible changes:
   ```sql
   -- V2__add_new_column.sql (forward migration)
   ALTER TABLE users ADD COLUMN email_verified BOOLEAN DEFAULT FALSE;

   -- U2__add_new_column.sql (undo migration - requires Flyway Teams)
   ALTER TABLE users DROP COLUMN email_verified;
   ```

3. **For critical rollbacks**, manually revert database changes:
   ```bash
   # Check current migration status
   mvn flyway:info -Dflyway.url=... -Dflyway.user=... -Dflyway.password=...

   # If using Flyway Teams with undo migrations
   mvn flyway:undo -Dflyway.url=... -Dflyway.user=... -Dflyway.password=...

   # For Community edition, apply a new forward migration that reverses changes
   # Create V{next}__rollback_previous_change.sql and run:
   mvn flyway:migrate -Dflyway.url=... -Dflyway.user=... -Dflyway.password=...
   ```

4. **Database credentials** are stored in AWS Secrets Manager:
   ```bash
   # Retrieve credentials for manual rollback operations
   aws secretsmanager get-secret-value \
     --secret-id mw-prod/database/credentials \
     --query SecretString --output text | jq -r '.host, .dbname, .username'
   ```

**Best Practice**: For high-risk database changes, consider a blue-green database strategy or deploy database changes separately from application changes.

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

### Blue-Green Deployments

Blue-Green deployments use AWS CodeDeploy to provide zero-downtime releases with instant rollback capability. When enabled, CodeDeploy manages traffic shifting between two target groups (blue and green) during deployments.

#### Enabling Blue-Green Deployments

Set `enable_blue_green = true` in your environment's tfvars file:

```hcl
# In envs/prod.tfvars or envs/stage.tfvars
enable_blue_green = true
```

**Default by environment:**
| Environment | Blue-Green Enabled |
|-------------|-------------------|
| Dev | No |
| Stage | Yes |
| Prod | Yes |

#### How It Works

1. **Initial State**: Traffic flows to the "blue" target group running the current version
2. **Deployment Triggered**: Push new image to ECR and create a CodeDeploy deployment
3. **Green Provisioning**: CodeDeploy launches new tasks in the "green" target group
4. **Health Checks**: Waits for green tasks to pass ALB health checks
5. **Traffic Shifting**: Gradually shifts traffic from blue to green based on deployment configuration
6. **Termination**: After successful deployment, blue tasks are terminated (default: 5 minute wait)

#### Traffic Shifting Options

Configure the deployment speed via `codedeploy_deployment_config` (default: `CodeDeployDefault.ECSLinear10PercentEvery1Minutes`):

| Configuration | Description | Use Case |
|--------------|-------------|----------|
| `CodeDeployDefault.ECSAllAtOnce` | Shifts all traffic immediately | Fast deployments, non-critical |
| `CodeDeployDefault.ECSLinear10PercentEvery1Minutes` | 10% every minute (default) | Balanced risk/speed |
| `CodeDeployDefault.ECSLinear10PercentEvery3Minutes` | 10% every 3 minutes | More cautious rollout |
| `CodeDeployDefault.ECSCanary10Percent5Minutes` | 10% for 5 min, then 100% | Early detection with canary |
| `CodeDeployDefault.ECSCanary10Percent15Minutes` | 10% for 15 min, then 100% | Extended canary validation |

#### Triggering a Blue-Green Deployment

```bash
# 1. Build and push new image
podman build -t liberty-app:1.1.0 -f containers/liberty/Containerfile .
ECR_URL=$(terraform -chdir=automated/terraform/environments/aws output -raw ecr_repository_url)
podman tag liberty-app:1.1.0 ${ECR_URL}:1.1.0
podman push ${ECR_URL}:1.1.0

# 2. Create deployment via AWS CLI
# First, create an appspec.json file:
cat > appspec.json << 'EOF'
{
  "version": 0.0,
  "Resources": [
    {
      "TargetService": {
        "Type": "AWS::ECS::Service",
        "Properties": {
          "TaskDefinition": "<TASK_DEFINITION_ARN>",
          "LoadBalancerInfo": {
            "ContainerName": "liberty",
            "ContainerPort": 9080
          }
        }
      }
    }
  ]
}
EOF

# 3. Start the deployment
aws deploy create-deployment \
  --application-name mw-prod-liberty \
  --deployment-group-name mw-prod-liberty-dg \
  --revision '{"revisionType": "AppSpecContent", "appSpecContent": {"content": "'"$(cat appspec.json)"'"}}' \
  --description "Deploy version 1.1.0"
```

#### Monitoring Deployment Progress

```bash
# List recent deployments
aws deploy list-deployments \
  --application-name mw-prod-liberty \
  --deployment-group-name mw-prod-liberty-dg \
  --query 'deployments[:5]'

# Get deployment status
DEPLOYMENT_ID="d-XXXXXXXXX"  # From list-deployments output
aws deploy get-deployment --deployment-id $DEPLOYMENT_ID \
  --query 'deploymentInfo.{Status:status,ErrorInfo:errorInformation}'

# Watch deployment progress
watch -n 5 "aws deploy get-deployment --deployment-id $DEPLOYMENT_ID \
  --query 'deploymentInfo.{Status:status,PercentComplete:deploymentOverview}'"
```

You can also monitor deployments in the AWS Console:
- Navigate to **CodeDeploy > Deployments**
- Select the deployment to see traffic shifting progress and task health

#### Rolling Back a Deployment

**Automatic Rollback**: CodeDeploy automatically rolls back when:
- Deployment fails (tasks don't become healthy)
- CloudWatch alarm triggers (if configured with `DEPLOYMENT_STOP_ON_ALARM`)

**Manual Rollback**:

```bash
# Stop an in-progress deployment and rollback
aws deploy stop-deployment --deployment-id $DEPLOYMENT_ID --auto-rollback-enabled

# Or create a new deployment with the previous task definition
aws deploy create-deployment \
  --application-name mw-prod-liberty \
  --deployment-group-name mw-prod-liberty-dg \
  --revision '{"revisionType": "AppSpecContent", "appSpecContent": {"content": "'"$(cat previous-appspec.json)"'"}}' \
  --description "Rollback to previous version"
```

#### Key Differences from Rolling Updates

| Aspect | Rolling Update (ECS) | Blue-Green (CodeDeploy) |
|--------|---------------------|------------------------|
| Deployment controller | ECS | CODE_DEPLOY |
| Circuit breaker | Available | Not available |
| Rollback speed | Gradual (new tasks) | Instant (traffic shift) |
| Resource usage | In-place | 2x during deployment |
| Traffic control | None | Configurable shifting |
| Best for | Dev, simple deploys | Prod, zero-downtime |

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

## Disaster Recovery

The unified environment includes comprehensive disaster recovery features for production workloads.

### DR Features Overview

| Feature | Variable | Cost Impact | Recovery Time |
|---------|----------|-------------|---------------|
| RDS Multi-AZ | `db_multi_az` | +100% RDS cost | Automatic (60-120s) |
| Route53 DNS Failover | `enable_route53_failover` | ~$1/month per health check | 30-90 seconds |
| S3 Cross-Region Replication | `enable_s3_replication` | Storage + transfer costs | Near real-time |
| ECR Cross-Region Replication | `enable_ecr_replication` | Storage costs | Near real-time |

### RDS Multi-AZ

RDS Multi-AZ provides automatic failover for the PostgreSQL database. When enabled, AWS maintains a synchronous standby replica in a different Availability Zone.

**How it works:**
- Primary database handles all read/write operations
- Standby replica receives synchronous updates
- Automatic failover occurs on: instance failure, AZ outage, or maintenance
- DNS endpoint automatically points to the new primary

**Configuration:**
```hcl
# In envs/prod.tfvars
db_multi_az = true  # Enabled by default in stage/prod
```

**Failover scenarios:**
- Instance failure: 60-120 seconds automatic recovery
- AZ failure: Automatic promotion of standby
- Maintenance: Planned failover with minimal downtime

### Route53 DNS Failover

Route53 DNS failover provides automatic traffic routing away from unhealthy endpoints. When the primary ALB fails health checks, traffic is routed to a failover target (maintenance page or DR region).

**Prerequisites:**
- A Route53 hosted zone for your domain
- The `domain_name` variable must be set

**Configuration:**
```hcl
# In envs/prod.tfvars
domain_name               = "app.example.com"
route53_zone_name         = "example.com"  # Parent hosted zone
enable_route53_failover   = true
enable_maintenance_page   = true           # Use S3 maintenance page as failover target

# Optional tuning
route53_health_check_interval          = 30   # 10 or 30 seconds
route53_health_check_failure_threshold = 3    # Failures before failover
route53_health_check_regions           = ["us-east-1", "us-west-1", "eu-west-1"]
```

**What gets created:**
- Route53 health check monitoring `/health/ready` endpoint
- Primary DNS record (ALIAS to ALB)
- Secondary/failover DNS record (S3 maintenance page or DR ALB)
- CloudWatch alarms for health check failures

**Failover to DR Region (instead of maintenance page):**
```hcl
enable_maintenance_page = false
dr_alb_dns_name        = "my-dr-alb-123456.us-west-2.elb.amazonaws.com"
dr_alb_zone_id         = "Z35SXDOTRQ7X7K"  # ALB zone ID from DR region
```

### S3 Cross-Region Replication

Replicates ALB access logs and CloudTrail audit logs to a DR region for compliance and disaster recovery.

**Configuration:**
```hcl
# In envs/prod.tfvars
enable_s3_replication = true
dr_region             = "us-west-2"  # Destination region
```

**What gets replicated:**
- ALB access logs bucket
- CloudTrail audit logs bucket

**Recovery use case:** If the primary region becomes unavailable, audit logs and access logs remain available in the DR region for investigation and compliance.

### ECR Cross-Region Replication

Replicates container images to a DR region, enabling rapid deployment in case of regional failure.

**Configuration:**
```hcl
# In envs/prod.tfvars
enable_ecr_replication = true
dr_region              = "us-west-2"
```

**Recovery use case:** Deploy the application in the DR region using the replicated container images without needing to rebuild or push from CI/CD.

### Enabling DR Features in tfvars

**Minimal DR setup (recommended for production):**
```hcl
# envs/prod.tfvars

# Database high availability
db_multi_az = true

# DNS failover with maintenance page
domain_name             = "app.example.com"
route53_zone_name       = "example.com"
enable_route53_failover = true
enable_maintenance_page = true
```

**Full DR setup (for critical workloads):**
```hcl
# envs/prod.tfvars

# Database high availability
db_multi_az = true

# DNS failover
domain_name                            = "app.example.com"
route53_zone_name                      = "example.com"
enable_route53_failover                = true
enable_maintenance_page                = false
dr_alb_dns_name                        = "dr-alb-123456.us-west-2.elb.amazonaws.com"
dr_alb_zone_id                         = "Z35SXDOTRQ7X7K"
route53_health_check_interval          = 10   # Faster detection
route53_health_check_failure_threshold = 2    # Faster failover

# Cross-region replication
enable_s3_replication  = true
enable_ecr_replication = true
dr_region              = "us-west-2"
```

### Recovery Procedures

#### RDS Failover (Automatic)

RDS Multi-AZ failover is automatic. To verify status:

```bash
# Check current AZ and status
aws rds describe-db-instances --db-instance-identifier mw-prod-postgres \
  --query 'DBInstances[0].{Status:DBInstanceStatus,AZ:AvailabilityZone,MultiAZ:MultiAZ}'

# View recent events (including failovers)
aws rds describe-events --source-identifier mw-prod-postgres \
  --source-type db-instance --duration 1440
```

#### Manual DNS Failover

If you need to manually trigger DNS failover:

```bash
# Option 1: Update health check to fail
aws route53 update-health-check --health-check-id <HEALTH_CHECK_ID> \
  --disabled

# Option 2: Update DNS weight to route all traffic to secondary
aws route53 change-resource-record-sets --hosted-zone-id <ZONE_ID> \
  --change-batch file://failover-change.json
```

#### Recovering from Regional Failure

1. **Verify DR region resources:**
   ```bash
   # Check ECR images are replicated
   aws ecr describe-images --repository-name mw-prod-liberty \
     --region us-west-2

   # Check S3 logs are replicated
   aws s3 ls s3://mw-prod-alb-logs-dr-us-west-2/
   ```

2. **Deploy to DR region:**
   ```bash
   cd automated/terraform/environments/aws

   # Initialize for DR region
   terraform init -backend-config=backends/prod-dr.backend.hcl -reconfigure

   # Deploy with DR-specific variables
   terraform apply -var-file=envs/prod-dr.tfvars -var="aws_region=us-west-2"
   ```

3. **Update DNS (if not using automatic failover):**
   ```bash
   # Get DR ALB DNS name
   DR_ALB=$(terraform output -raw alb_dns_name)

   # Update Route53 record
   aws route53 change-resource-record-sets --hosted-zone-id <ZONE_ID> \
     --change-batch '{
       "Changes": [{
         "Action": "UPSERT",
         "ResourceRecordSet": {
           "Name": "app.example.com",
           "Type": "A",
           "AliasTarget": {
             "HostedZoneId": "<DR_ALB_ZONE_ID>",
             "DNSName": "'$DR_ALB'",
             "EvaluateTargetHealth": true
           }
         }
       }]
     }'
   ```

#### Restoring to Primary Region

After the primary region is healthy:

1. **Verify primary region health:**
   ```bash
   # Check ALB health
   aws elbv2 describe-target-health --target-group-arn <TARGET_GROUP_ARN>

   # Check ECS service
   aws ecs describe-services --cluster mw-prod-cluster --services mw-prod-liberty
   ```

2. **Re-enable Route53 health check (if disabled):**
   ```bash
   aws route53 update-health-check --health-check-id <HEALTH_CHECK_ID> \
     --no-disabled
   ```

3. **DNS will automatically failback** once primary passes health checks (if using Route53 failover routing).

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

### Distributed Tracing (X-Ray)

AWS X-Ray provides distributed tracing for visualizing request flows, identifying latency bottlenecks, and debugging errors across services.

#### Enabling X-Ray

Set `enable_xray = true` in your environment tfvars file:

```hcl
# In envs/prod.tfvars (or dev.tfvars, stage.tfvars)
enable_xray        = true
xray_sampling_rate = 0.1  # 10% of requests traced (default)
```

#### What Gets Instrumented

When X-Ray is enabled, the following components are automatically configured:

| Component | Configuration |
|-----------|---------------|
| ECS Tasks | OpenTelemetry environment variables set to export traces to X-Ray |
| IAM | Task role granted `xray:PutTraceSegments`, `xray:PutTelemetryRecords`, and sampling permissions |
| Sampling Rules | Custom rules for Liberty app, error traces, and health checks |
| X-Ray Group | Filter expression for Liberty traces with Insights enabled |
| CloudWatch Dashboard | Pre-configured dashboard for trace metrics |

#### OpenTelemetry Integration

ECS tasks are configured with OpenTelemetry environment variables:

| Variable | Value |
|----------|-------|
| `OTEL_SERVICE_NAME` | `liberty-app` |
| `OTEL_TRACES_EXPORTER` | `xray` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://localhost:2000` |
| `OTEL_PROPAGATORS` | `tracecontext,baggage,xray` |

Your application can use any OpenTelemetry-compatible SDK (Java, Node.js, etc.) to automatically send traces to X-Ray without additional configuration.

#### Sampling Configuration

Three sampling rules are created to control trace volume and cost:

| Rule | Priority | Rate | Purpose |
|------|----------|------|---------|
| Health Checks | 50 (highest) | 1% | Minimize noise from `/health/*` endpoints |
| Errors | 100 | 50% + 5/sec reservoir | Capture more 5xx errors for debugging |
| Default | 1000 | Configurable (default 10%) | Normal traffic sampling |

Adjust the default sampling rate via `xray_sampling_rate` (0.0 to 1.0):

```hcl
# Sample 5% of requests (lower cost)
xray_sampling_rate = 0.05

# Sample 25% of requests (more visibility)
xray_sampling_rate = 0.25
```

#### Viewing Traces in AWS Console

1. **Service Map**: Visualize service dependencies and latency
   ```
   https://{region}.console.aws.amazon.com/xray/home?region={region}#/service-map
   ```

2. **Traces**: Search and filter individual traces
   ```
   https://{region}.console.aws.amazon.com/xray/home?region={region}#/traces
   ```

3. **Analytics**: Query traces with filter expressions
   ```
   https://{region}.console.aws.amazon.com/xray/home?region={region}#/analytics
   ```

4. **CloudWatch Dashboard**: View X-Ray metrics
   ```bash
   # Dashboard name: {env}-xray-traces (e.g., mw-prod-xray-traces)
   aws cloudwatch get-dashboard --dashboard-name mw-prod-xray-traces
   ```

#### X-Ray Insights

X-Ray Insights is enabled for the Liberty trace group, providing:
- Automatic anomaly detection for latency and error rates
- Root cause analysis for performance issues
- Notifications when anomalies are detected

#### Cost

- First 100,000 traces/month: Free
- Traces recorded: $5.00 per million
- Traces retrieved: $0.50 per million

With 10% sampling rate and moderate traffic, expect approximately $5-15/month.

### SLO Alerting

The unified environment includes SLO/SLI CloudWatch alarms that monitor availability, latency, and error rate using ALB and ECS metrics.

#### Enabling SLO Alarms

Set `enable_slo_alarms = true` in your environment's `.tfvars` file:

```hcl
# Enable SLO alerting
enable_slo_alarms = true

# Email for SLO alerts (falls back to security_alert_email if not set)
slo_alert_email = "oncall@example.com"
```

#### SLOs Monitored

| SLO | Default Target | Metric Source |
|-----|----------------|---------------|
| **Availability** | 99.9% (error rate < 0.1%) | ALB 5xx error count / total requests |
| **Latency** | p99 < 500ms | ALB TargetResponseTime |
| **Error Rate** | < 0.5% | ALB 5xx error count / total requests |

#### Alarm Types

**Availability Alarms:**
- **Critical** (14.4x burn rate): Error budget exhaustion in ~2 hours. Triggers on 2 consecutive 5-minute periods.
- **Warning** (6x burn rate): Error budget exhaustion in ~5 days. Triggers on 6 consecutive 5-minute periods (30 min).

**Latency Alarms:**
- **Critical**: p99 latency exceeds threshold (default 500ms)
- **Warning**: p99 latency at 80% of threshold (default 400ms)
- **Tail Latency Critical**: p99 > 2 seconds (severe degradation)

**Error Rate Alarms:**
- **Critical**: Error rate > 0.5%
- **Warning**: Error rate > 0.3% (approaching threshold)

**Health Check Alarms:**
- **Unhealthy Targets**: Any target fails health checks
- **Low Healthy Targets**: Healthy targets below minimum capacity

**ECS Resource Alarms** (when ECS enabled):
- **High CPU**: CPU utilization > 85%
- **High Memory**: Memory utilization > 85%

**Composite Alarm:**
- **Overall SLO Health**: Triggers when ANY critical alarm is in ALARM state

#### Alert Delivery

Alerts are delivered via SNS topic (`{env}-slo-alerts`):
- Email subscription configured via `slo_alert_email` (or `security_alert_email` fallback)
- Alerts sent on both ALARM and OK transitions

To confirm the email subscription:
1. Deploy with `enable_slo_alarms = true` and valid email
2. Check inbox for SNS subscription confirmation email
3. Click the confirmation link

#### Customizing Thresholds

Override defaults in your `.tfvars` file:

```hcl
# Availability target (percentage)
slo_availability_target = 99.9    # Range: 90-99.999

# p99 latency threshold (milliseconds)
slo_latency_threshold_ms = 500    # Range: 50-10000
```

**Burn Rate Calculation:**
- Error budget = `100 - slo_availability_target` (e.g., 99.9% = 0.1% budget)
- Critical threshold = error budget x 14.4
- Warning threshold = error budget x 6

#### Viewing Alarms

```bash
# List all SLO alarms
aws cloudwatch describe-alarms --alarm-name-prefix "mw-prod-slo"

# Check overall SLO health
aws cloudwatch describe-alarms --alarm-names "mw-prod-slo-overall-health"

# View alarm history
aws cloudwatch describe-alarm-history --alarm-name "mw-prod-slo-availability-critical" \
  --history-item-type StateUpdate --max-records 10
```

#### Related Runbooks

Alarm descriptions reference runbooks for incident response:
- `docs/runbooks/liberty-slo-breach.md` - Availability SLO violations
- `docs/runbooks/liberty-slow-responses.md` - Latency issues
- `docs/runbooks/liberty-high-error-rate.md` - Error rate spikes
- `docs/runbooks/liberty-server-down.md` - Unhealthy targets
- `docs/runbooks/liberty-high-heap.md` - Memory pressure

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

### Additional Cost Considerations

| Feature | Cost Impact | Notes |
|---------|-------------|-------|
| Multi-AZ NAT Gateway | +~$32/mo per NAT | Prod uses 3 AZs with HA NAT (+~$64/mo) |
| RDS Proxy | +~$11/mo | Enabled in prod for connection pooling |
| RDS Multi-AZ | +~$15/mo | Doubles RDS cost for failover capability |
| WAF | +~$6/mo + $0.60/million requests | Enabled in stage/prod |
| CloudTrail | +~$2/mo | Enabled in stage/prod |
| GuardDuty | +~$4/mo | Enabled in stage/prod |

### Fargate Spot Savings

Fargate Spot provides up to 70% cost savings compared to On-Demand pricing. Each environment is configured with a different Spot capacity ratio:

| Environment | Spot Weight | Estimated Savings | Notes |
|-------------|-------------|-------------------|-------|
| **Dev** | 80% | ~$16-28/mo | Higher Spot for cost optimization |
| **Stage** | 50% | ~$10-18/mo | Balanced Spot/On-Demand mix |
| **Prod** | 70% | ~$14-25/mo | Aggressive Spot with interruption handling |

> **Note:** Fargate Spot tasks can be interrupted with 2-minute warning. The ECS service automatically replaces interrupted tasks, but design applications for graceful shutdown.

### Cost Reduction

| Strategy | Savings |
|----------|---------|
| Fargate Spot (dev: 80%, stage: 50%, prod: 70%) | 50-70% on compute |
| Single NAT Gateway (dev/stage) | ~$64/mo vs Multi-AZ |
| Disable RDS Proxy (dev/stage) | ~$11/mo |
| Disable RDS Multi-AZ (dev) | ~$15/mo |
| Stop management server when idle | ~$30/mo |
| Disable monitoring server | ~$30/mo |
| Use `--destroy` when not testing | 100% |
