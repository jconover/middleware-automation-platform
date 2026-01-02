# Disaster Recovery Guide

This document provides comprehensive disaster recovery (DR) procedures for the Middleware Automation Platform. It covers backup strategies, recovery procedures, and testing protocols for all infrastructure components.

## Table of Contents

1. [Recovery Objectives](#recovery-objectives)
2. [Automated Backups](#automated-backups)
3. [Manual Backup Procedures](#manual-backup-procedures)
4. [Recovery Procedures](#recovery-procedures)
5. [Disaster Recovery Testing](#disaster-recovery-testing)
6. [Contact and Escalation](#contact-and-escalation)

---

## Recovery Objectives

### RTO/RPO Summary by Component

| Component | RTO | RPO | Backup Method | Recovery Method |
|-----------|-----|-----|---------------|-----------------|
| RDS PostgreSQL | 1-4 hours | 5 minutes | Automated snapshots + PITR | Restore from snapshot |
| ElastiCache Redis | 30 minutes | 1 day | Daily snapshots | Restore from snapshot |
| ECS Service | 15 minutes | N/A (stateless) | ECR images | Redeploy from ECR |
| Terraform State | 1 hour | Real-time | S3 versioning + DynamoDB | Restore from S3 version |
| Application Config | 30 minutes | Last commit | Git repository | Clone and redeploy |
| Container Images | 15 minutes | Last push | ECR with lifecycle | Rebuild from source |
| Secrets | 1 hour | Real-time | AWS Secrets Manager | Recreate or restore |
| EC2 Instances | 2 hours | N/A (config-as-code) | AMI + Ansible | Recreate via Terraform |

### Definitions

- **RTO (Recovery Time Objective)**: Maximum acceptable time to restore service after a disaster
- **RPO (Recovery Point Objective)**: Maximum acceptable data loss measured in time

---

## Automated Backups

### RDS PostgreSQL Automated Snapshots

The RDS instance is configured with automated backups:

```hcl
# Current configuration (from database.tf)
backup_retention_period = 7          # Days to retain automated backups
backup_window           = "03:00-04:00"  # UTC - Daily backup window
maintenance_window      = "Mon:04:00-Mon:05:00"

# Point-in-time recovery enabled automatically
# Transaction logs retained for PITR within retention period
```

**Verification Command:**
```bash
# Check backup status and retention
aws rds describe-db-instances \
    --db-instance-identifier mw-prod-postgres \
    --query 'DBInstances[0].{BackupRetention:BackupRetentionPeriod,LatestRestorableTime:LatestRestorableTime,BackupWindow:PreferredBackupWindow}' \
    --output table
```

### S3 Terraform State Versioning

Terraform state is stored in S3 with versioning enabled:

```hcl
# Backend configuration (from backend.tf)
terraform {
  backend "s3" {
    bucket         = "middleware-platform-terraform-state"
    key            = "prod-aws/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "middleware-platform-terraform-locks"
    encrypt        = true
  }
}
```

**Verification Command:**
```bash
# Verify versioning is enabled
aws s3api get-bucket-versioning \
    --bucket middleware-platform-terraform-state

# List state file versions
aws s3api list-object-versions \
    --bucket middleware-platform-terraform-state \
    --prefix prod-aws/terraform.tfstate \
    --max-keys 10
```

### ECR Image Retention

ECR lifecycle policy maintains image history:

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Expire untagged images after 7 days",
      "selection": {
        "tagStatus": "untagged",
        "countType": "sinceImagePushed",
        "countUnit": "days",
        "countNumber": 7
      },
      "action": { "type": "expire" }
    },
    {
      "rulePriority": 2,
      "description": "Keep last 10 tagged images",
      "selection": {
        "tagStatus": "any",
        "countType": "imageCountMoreThan",
        "countNumber": 10
      },
      "action": { "type": "expire" }
    }
  ]
}
```

**Verification Command:**
```bash
# List available images
aws ecr describe-images \
    --repository-name mw-prod-liberty \
    --query 'imageDetails[*].{Tags:imageTags,Pushed:imagePushedAt,Size:imageSizeInBytes}' \
    --output table
```

### ElastiCache Redis Snapshots

```hcl
# Current configuration (from database.tf)
snapshot_retention_limit = 1    # Days to retain snapshots
snapshot_window          = "05:00-06:00"  # UTC
```

**Verification Command:**
```bash
# List Redis snapshots
aws elasticache describe-snapshots \
    --cache-cluster-id mw-prod-redis \
    --query 'Snapshots[*].{Name:SnapshotName,Status:SnapshotStatus,Created:NodeSnapshots[0].SnapshotCreateTime}' \
    --output table
```

### Configuration as Code (Git)

All infrastructure and application configuration is maintained in Git:

| Repository Location | Content |
|---------------------|---------|
| `automated/terraform/` | AWS infrastructure definitions |
| `automated/ansible/` | Configuration management playbooks |
| `containers/liberty/` | Container build definitions |
| `kubernetes/` | Local K8s deployment manifests |
| `monitoring/` | Grafana dashboards, Prometheus rules |

**Best Practice:** Ensure all changes are committed before deploying to production.

---

## Manual Backup Procedures

### Create On-Demand RDS Snapshot

Use this before major changes or deployments:

```bash
#!/bin/bash
# Create a manual RDS snapshot

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
DB_IDENTIFIER="mw-prod-postgres"
SNAPSHOT_ID="mw-prod-postgres-manual-${TIMESTAMP}"

# Create snapshot
aws rds create-db-snapshot \
    --db-instance-identifier "${DB_IDENTIFIER}" \
    --db-snapshot-identifier "${SNAPSHOT_ID}" \
    --tags Key=Purpose,Value=Manual Key=CreatedBy,Value=$(whoami)

echo "Creating snapshot: ${SNAPSHOT_ID}"

# Wait for snapshot to complete
aws rds wait db-snapshot-available \
    --db-snapshot-identifier "${SNAPSHOT_ID}"

echo "Snapshot ${SNAPSHOT_ID} is now available"

# Verify
aws rds describe-db-snapshots \
    --db-snapshot-identifier "${SNAPSHOT_ID}" \
    --query 'DBSnapshots[0].{ID:DBSnapshotIdentifier,Status:Status,Created:SnapshotCreateTime,Size:AllocatedStorage}' \
    --output table
```

### Backup Terraform State

Download current state for local backup:

```bash
#!/bin/bash
# Download Terraform state for local backup

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="./terraform-state-backups"
STATE_FILE="${BACKUP_DIR}/terraform-${TIMESTAMP}.tfstate"

mkdir -p "${BACKUP_DIR}"

# Download current state
aws s3 cp \
    s3://middleware-platform-terraform-state/prod-aws/terraform.tfstate \
    "${STATE_FILE}"

# Verify download
if [ -f "${STATE_FILE}" ]; then
    echo "State backed up to: ${STATE_FILE}"
    echo "Size: $(ls -lh ${STATE_FILE} | awk '{print $5}')"

    # Optional: Compress for storage
    gzip -k "${STATE_FILE}"
    echo "Compressed backup: ${STATE_FILE}.gz"
else
    echo "ERROR: Failed to download state file"
    exit 1
fi
```

### List and Restore Terraform State Versions

```bash
#!/bin/bash
# List available Terraform state versions

BUCKET="middleware-platform-terraform-state"
KEY="prod-aws/terraform.tfstate"

# List all versions
aws s3api list-object-versions \
    --bucket "${BUCKET}" \
    --prefix "${KEY}" \
    --query 'Versions[*].{VersionId:VersionId,LastModified:LastModified,Size:Size}' \
    --output table

# To restore a specific version:
# VERSION_ID="your-version-id-here"
# aws s3api get-object \
#     --bucket "${BUCKET}" \
#     --key "${KEY}" \
#     --version-id "${VERSION_ID}" \
#     terraform.tfstate.restored
```

### Export Kubernetes Configurations (Local Cluster)

For the local Beelink homelab Kubernetes cluster:

```bash
#!/bin/bash
# Export all Kubernetes configurations from local cluster

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="./k8s-backup-${TIMESTAMP}"

mkdir -p "${BACKUP_DIR}"

# Ensure kubectl is configured for local cluster
export KUBECONFIG=~/.kube/config

# Export all namespaces
kubectl get namespaces -o yaml > "${BACKUP_DIR}/namespaces.yaml"

# Export deployments, services, configmaps, secrets (all namespaces)
for resource in deployments services configmaps secrets persistentvolumeclaims; do
    kubectl get ${resource} --all-namespaces -o yaml > "${BACKUP_DIR}/${resource}.yaml"
    echo "Exported: ${resource}"
done

# Export custom resources (ServiceMonitors, PrometheusRules)
kubectl get servicemonitors --all-namespaces -o yaml > "${BACKUP_DIR}/servicemonitors.yaml" 2>/dev/null || true
kubectl get prometheusrules --all-namespaces -o yaml > "${BACKUP_DIR}/prometheusrules.yaml" 2>/dev/null || true

# Export Helm releases
helm list --all-namespaces -o yaml > "${BACKUP_DIR}/helm-releases.yaml"

# Create archive
tar -czvf "k8s-backup-${TIMESTAMP}.tar.gz" "${BACKUP_DIR}"
echo "Backup created: k8s-backup-${TIMESTAMP}.tar.gz"

# Cleanup directory
rm -rf "${BACKUP_DIR}"
```

### Export AWS Secrets Manager Secrets

```bash
#!/bin/bash
# Export secret ARNs and metadata (NOT values) for documentation

aws secretsmanager list-secrets \
    --query 'SecretList[?contains(Name, `mw-prod`)].{Name:Name,ARN:ARN,LastChanged:LastChangedDate}' \
    --output table

# IMPORTANT: Never export actual secret values to files
# Secrets should be recreated using known procedures if lost
```

---

## Recovery Procedures

### Scenario 1: Database Corruption or Accidental Deletion

**Symptoms:** Application errors indicating database connectivity or data integrity issues.

#### Option A: Point-in-Time Recovery (Minimal Data Loss)

```bash
#!/bin/bash
# Restore RDS to a specific point in time

# 1. Identify the target restore time
aws rds describe-db-instances \
    --db-instance-identifier mw-prod-postgres \
    --query 'DBInstances[0].LatestRestorableTime' \
    --output text

# 2. Create restored instance (adjust timestamp as needed)
RESTORE_TIME="2025-01-02T10:30:00Z"  # ISO 8601 format, UTC
NEW_INSTANCE_ID="mw-prod-postgres-restored"

aws rds restore-db-instance-to-point-in-time \
    --source-db-instance-identifier mw-prod-postgres \
    --target-db-instance-identifier "${NEW_INSTANCE_ID}" \
    --restore-time "${RESTORE_TIME}" \
    --db-subnet-group-name mw-prod-db-subnet \
    --vpc-security-group-ids sg-xxxxxxxxx  # Get from current instance

# 3. Wait for restore to complete
aws rds wait db-instance-available \
    --db-instance-identifier "${NEW_INSTANCE_ID}"

echo "Restored instance available: ${NEW_INSTANCE_ID}"

# 4. Verify data integrity on restored instance
# Connect and run verification queries

# 5. If verified, swap instances:
#    - Stop application traffic (scale ECS to 0)
#    - Rename original: mw-prod-postgres -> mw-prod-postgres-old
#    - Rename restored: mw-prod-postgres-restored -> mw-prod-postgres
#    - Update Secrets Manager with new endpoint if different
#    - Resume application traffic

# 6. Delete old instance after confirmation period
```

#### Option B: Restore from Snapshot

```bash
#!/bin/bash
# Restore from a specific snapshot

# 1. List available snapshots
aws rds describe-db-snapshots \
    --db-instance-identifier mw-prod-postgres \
    --query 'DBSnapshots[*].{ID:DBSnapshotIdentifier,Created:SnapshotCreateTime,Status:Status}' \
    --output table

# 2. Choose snapshot and restore
SNAPSHOT_ID="mw-prod-postgres-manual-20250102-103000"
NEW_INSTANCE_ID="mw-prod-postgres-from-snapshot"

aws rds restore-db-instance-from-db-snapshot \
    --db-instance-identifier "${NEW_INSTANCE_ID}" \
    --db-snapshot-identifier "${SNAPSHOT_ID}" \
    --db-subnet-group-name mw-prod-db-subnet \
    --vpc-security-group-ids sg-xxxxxxxxx

# 3. Wait and follow same swap procedure as Option A
aws rds wait db-instance-available \
    --db-instance-identifier "${NEW_INSTANCE_ID}"
```

#### Update Application Connection

After restoring to a new instance, update Secrets Manager if the endpoint changed:

```bash
# Get new endpoint
NEW_ENDPOINT=$(aws rds describe-db-instances \
    --db-instance-identifier mw-prod-postgres \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text)

# Update secret (get current secret first, update host, put back)
SECRET_ARN=$(aws secretsmanager list-secrets \
    --query 'SecretList[?contains(Name, `database/credentials`)].ARN' \
    --output text)

# Get current secret value
CURRENT_SECRET=$(aws secretsmanager get-secret-value \
    --secret-id "${SECRET_ARN}" \
    --query 'SecretString' \
    --output text)

# Update host in JSON (using jq)
UPDATED_SECRET=$(echo "${CURRENT_SECRET}" | jq --arg host "${NEW_ENDPOINT}" '.host = $host')

# Put updated secret
aws secretsmanager put-secret-value \
    --secret-id "${SECRET_ARN}" \
    --secret-string "${UPDATED_SECRET}"

# Force ECS to pick up new secret
aws ecs update-service \
    --cluster mw-prod-cluster \
    --service mw-prod-liberty \
    --force-new-deployment
```

---

### Scenario 2: ECS Service Failure / Task Crashes

**Symptoms:** HTTP 503 errors, no healthy targets in ALB, CloudWatch showing task failures.

#### Step 1: Diagnose the Issue

```bash
#!/bin/bash
# Diagnose ECS service issues

CLUSTER="mw-prod-cluster"
SERVICE="mw-prod-liberty"

# Check service status
aws ecs describe-services \
    --cluster "${CLUSTER}" \
    --services "${SERVICE}" \
    --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount,Pending:pendingCount}' \
    --output table

# Check recent events
aws ecs describe-services \
    --cluster "${CLUSTER}" \
    --services "${SERVICE}" \
    --query 'services[0].events[0:5].{Time:createdAt,Message:message}' \
    --output table

# List recent stopped tasks (to see why they failed)
aws ecs list-tasks \
    --cluster "${CLUSTER}" \
    --service-name "${SERVICE}" \
    --desired-status STOPPED \
    --query 'taskArns[0:3]' \
    --output text | xargs -I {} aws ecs describe-tasks \
        --cluster "${CLUSTER}" \
        --tasks {} \
        --query 'tasks[*].{StopCode:stopCode,StoppedReason:stoppedReason,Container:containers[0].reason}'

# Check CloudWatch logs for errors
aws logs filter-log-events \
    --log-group-name "/ecs/mw-prod-liberty" \
    --filter-pattern "ERROR" \
    --start-time $(date -d '1 hour ago' +%s000) \
    --limit 20 \
    --query 'events[*].{Time:timestamp,Message:message}'
```

#### Step 2: Recovery Actions

```bash
#!/bin/bash
# ECS service recovery

CLUSTER="mw-prod-cluster"
SERVICE="mw-prod-liberty"

# Option A: Force new deployment (pulls latest image, restarts all tasks)
aws ecs update-service \
    --cluster "${CLUSTER}" \
    --service "${SERVICE}" \
    --force-new-deployment

# Option B: Rollback to previous task definition
# List task definition revisions
aws ecs list-task-definitions \
    --family-prefix mw-prod-liberty \
    --sort DESC \
    --max-items 5

# Update service to use previous revision
PREVIOUS_TASK_DEF="mw-prod-liberty:X"  # Replace X with previous revision number
aws ecs update-service \
    --cluster "${CLUSTER}" \
    --service "${SERVICE}" \
    --task-definition "${PREVIOUS_TASK_DEF}"

# Option C: Scale up/down to cycle tasks
aws ecs update-service \
    --cluster "${CLUSTER}" \
    --service "${SERVICE}" \
    --desired-count 0

# Wait for drain
sleep 60

aws ecs update-service \
    --cluster "${CLUSTER}" \
    --service "${SERVICE}" \
    --desired-count 2

# Verify recovery
aws ecs wait services-stable \
    --cluster "${CLUSTER}" \
    --services "${SERVICE}"

echo "Service stabilized"
```

#### Step 3: Verify Health

```bash
#!/bin/bash
# Verify ECS recovery

# Check target group health
TG_ARN=$(aws elbv2 describe-target-groups \
    --names mw-prod-liberty-ecs-tg \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)

aws elbv2 describe-target-health \
    --target-group-arn "${TG_ARN}" \
    --query 'TargetHealthDescriptions[*].{Target:Target.Id,Health:TargetHealth.State,Reason:TargetHealth.Reason}' \
    --output table

# Test application endpoint
ALB_DNS=$(aws elbv2 describe-load-balancers \
    --names mw-prod-alb \
    --query 'LoadBalancers[0].DNSName' \
    --output text)

curl -sf "http://${ALB_DNS}/health/ready" && echo "Health check PASSED" || echo "Health check FAILED"
```

---

### Scenario 3: Accidental Terraform Destroy

**Symptoms:** AWS resources missing, terraform state shows resources need to be created.

#### Step 1: Assess Damage

```bash
#!/bin/bash
# Check what was destroyed

cd automated/terraform/environments/prod-aws

# Review what Terraform thinks needs to be created
terraform plan -out=recovery.plan

# If state is corrupted, check for backups first
```

#### Step 2: Restore Terraform State (If Needed)

```bash
#!/bin/bash
# Restore Terraform state from S3 versioning

BUCKET="middleware-platform-terraform-state"
KEY="prod-aws/terraform.tfstate"

# List available versions
aws s3api list-object-versions \
    --bucket "${BUCKET}" \
    --prefix "${KEY}" \
    --query 'Versions[*].{VersionId:VersionId,LastModified:LastModified,IsLatest:IsLatest}' \
    --output table

# Identify the version BEFORE the destroy (by timestamp)
# Then copy that version to current

VERSION_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  # Version before destroy

aws s3api copy-object \
    --bucket "${BUCKET}" \
    --copy-source "${BUCKET}/${KEY}?versionId=${VERSION_ID}" \
    --key "${KEY}"

echo "State restored from version ${VERSION_ID}"

# Pull restored state
terraform init -reconfigure
```

#### Step 3: Recreate Infrastructure

```bash
#!/bin/bash
# Recreate infrastructure from Terraform

cd automated/terraform/environments/prod-aws

# Ensure state is current
terraform init

# Plan and review changes
terraform plan -out=recovery.plan

# Apply if plan looks correct
terraform apply recovery.plan

# Verify resources created
terraform output
```

#### Step 4: Restore Data

After infrastructure is recreated:

```bash
#!/bin/bash
# Restore database from snapshot (new RDS instance was created empty)

# Find most recent snapshot from destroyed instance
aws rds describe-db-snapshots \
    --snapshot-type automated \
    --query 'DBSnapshots[?contains(DBSnapshotIdentifier, `mw-prod`)].{ID:DBSnapshotIdentifier,Created:SnapshotCreateTime}' \
    --output table

# Note: Automated snapshots are retained for a period after instance deletion
# Manual snapshots are retained indefinitely until explicitly deleted

# If snapshots exist, follow Scenario 1 recovery procedure
```

#### Step 5: Redeploy Application

```bash
#!/bin/bash
# Redeploy application after infrastructure recreation

# Push latest image to ECR (if registry was preserved)
# Or rebuild and push from source:
cd /path/to/middleware-automation-platform
podman build -t liberty-app:recovery -f containers/liberty/Containerfile .

# Get ECR push commands
terraform -chdir=automated/terraform/environments/prod-aws output ecr_push_commands

# Execute the push commands output by Terraform

# Force ECS deployment
aws ecs update-service \
    --cluster mw-prod-cluster \
    --service mw-prod-liberty \
    --force-new-deployment

# Wait for stabilization
aws ecs wait services-stable \
    --cluster mw-prod-cluster \
    --services mw-prod-liberty
```

---

### Scenario 4: Complete AWS Region Failure

**Impact:** All resources in us-east-1 unavailable.

#### Prerequisites for Cross-Region DR

> **Note:** The current configuration does not include automatic cross-region replication. Implementing full cross-region DR requires:
>
> - RDS cross-region read replica or automated snapshot copy
> - S3 cross-region replication for Terraform state
> - ECR cross-region replication
> - Duplicate Terraform configuration for DR region

#### Manual Cross-Region Recovery Steps

```bash
#!/bin/bash
# Cross-region disaster recovery (manual process)

DR_REGION="us-west-2"
PRIMARY_REGION="us-east-1"

# Step 1: Copy most recent RDS snapshot to DR region
# Find latest snapshot
LATEST_SNAPSHOT=$(aws rds describe-db-snapshots \
    --region "${PRIMARY_REGION}" \
    --db-instance-identifier mw-prod-postgres \
    --query 'DBSnapshots | sort_by(@, &SnapshotCreateTime) | [-1].DBSnapshotIdentifier' \
    --output text)

# If primary region accessible, copy snapshot
aws rds copy-db-snapshot \
    --source-db-snapshot-identifier "arn:aws:rds:${PRIMARY_REGION}:ACCOUNT_ID:snapshot:${LATEST_SNAPSHOT}" \
    --target-db-snapshot-identifier "${LATEST_SNAPSHOT}-dr" \
    --source-region "${PRIMARY_REGION}" \
    --region "${DR_REGION}"

# Step 2: Copy Terraform state to DR region bucket
aws s3 cp \
    s3://middleware-platform-terraform-state/prod-aws/terraform.tfstate \
    s3://middleware-platform-terraform-state-dr/prod-aws/terraform.tfstate

# Step 3: Copy ECR images to DR region
# Create ECR repo in DR region if not exists
aws ecr create-repository \
    --repository-name mw-prod-liberty \
    --region "${DR_REGION}" 2>/dev/null || true

# Pull and push to DR region (requires docker/podman)
# This needs ECR login for both regions

# Step 4: Update Terraform for DR region
# Create modified terraform.tfvars with:
#   aws_region = "us-west-2"
# And update backend.tf to use DR state bucket

# Step 5: Apply Terraform in DR region
cd automated/terraform/environments/prod-aws
# (after updating config for DR region)
terraform init -reconfigure
terraform apply

# Step 6: Restore database from copied snapshot
# Step 7: Update DNS to point to new ALB in DR region
```

#### Post-Recovery: Failback to Primary

After primary region recovers:

1. Verify primary region health
2. Sync data changes from DR back to primary (if any writes occurred)
3. Stop traffic to DR region
4. Verify primary region services
5. Update DNS to point back to primary
6. Keep DR region warm or destroy to save costs

---

### Scenario 5: Lost Credentials

#### Lost Ansible Vault Password

The Ansible Vault password encrypts sensitive variables in `automated/ansible/`.

**Recovery Steps:**

```bash
#!/bin/bash
# Recovery from lost Ansible Vault password

# 1. The vault password cannot be recovered - you must re-encrypt

# 2. Create new vault password and store securely
openssl rand -base64 32 > ~/.ansible_vault_password
chmod 600 ~/.ansible_vault_password

# 3. Create new encrypted variable file
# Edit the vault file with new values:
ansible-vault create automated/ansible/group_vars/all/vault.yml \
    --vault-password-file ~/.ansible_vault_password

# 4. Add required variables (from CREDENTIAL_SETUP.md):
#    - liberty_keystore_password
#    - liberty_admin_password
#    - (any other application secrets)

# 5. Update vault password in password manager / secrets storage
```

#### Lost AWS Access Keys

```bash
#!/bin/bash
# Recovery from compromised or lost AWS credentials

# 1. IMMEDIATE: If compromised, disable the old key
aws iam update-access-key \
    --user-name YOUR_IAM_USER \
    --access-key-id OLD_ACCESS_KEY_ID \
    --status Inactive

# 2. Create new access key
aws iam create-access-key \
    --user-name YOUR_IAM_USER

# 3. Update local configuration
aws configure
# Enter new Access Key ID and Secret Access Key

# 4. Update CI/CD systems (Jenkins, GitHub Actions, etc.)
# - Jenkins: Update AWS credentials in credential store
# - GitHub: Update repository secrets

# 5. Delete old access key after confirming new one works
aws iam delete-access-key \
    --user-name YOUR_IAM_USER \
    --access-key-id OLD_ACCESS_KEY_ID

# 6. If locked out of AWS entirely:
# - Contact AWS Support
# - Use root account recovery
# - Restore from offline backup of credentials (if available)
```

#### Lost Database Password

```bash
#!/bin/bash
# Recovery from lost RDS password

# Database password is stored in Secrets Manager
# If Secrets Manager is accessible:

SECRET_ARN=$(aws secretsmanager list-secrets \
    --query 'SecretList[?contains(Name, `database/credentials`)].ARN' \
    --output text)

# Retrieve password
aws secretsmanager get-secret-value \
    --secret-id "${SECRET_ARN}" \
    --query 'SecretString' \
    --output text | jq -r '.password'

# If Secrets Manager secret is also lost, reset RDS master password:
NEW_PASSWORD=$(openssl rand -base64 24)

aws rds modify-db-instance \
    --db-instance-identifier mw-prod-postgres \
    --master-user-password "${NEW_PASSWORD}" \
    --apply-immediately

# Update Secrets Manager with new password
CURRENT_SECRET=$(aws secretsmanager get-secret-value \
    --secret-id "${SECRET_ARN}" \
    --query 'SecretString' \
    --output text)

UPDATED_SECRET=$(echo "${CURRENT_SECRET}" | jq --arg pwd "${NEW_PASSWORD}" '.password = $pwd')

aws secretsmanager put-secret-value \
    --secret-id "${SECRET_ARN}" \
    --secret-string "${UPDATED_SECRET}"

# Force ECS task restart to pick up new password
aws ecs update-service \
    --cluster mw-prod-cluster \
    --service mw-prod-liberty \
    --force-new-deployment
```

#### Lost Grafana Admin Password

```bash
#!/bin/bash
# Recovery from lost Grafana admin password

# Grafana password is stored in Secrets Manager
SECRET_ARN=$(aws secretsmanager list-secrets \
    --query 'SecretList[?contains(Name, `grafana`)].ARN' \
    --output text)

# Retrieve current password
aws secretsmanager get-secret-value \
    --secret-id "${SECRET_ARN}" \
    --query 'SecretString' \
    --output text

# If secret is lost, reset via Grafana CLI on monitoring server
MONITORING_IP=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=mw-prod-monitoring" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

ssh -i ~/.ssh/ansible_ed25519 ubuntu@${MONITORING_IP} \
    "sudo grafana-cli admin reset-admin-password NEW_PASSWORD"

# Update Secrets Manager with new password
```

---

## Disaster Recovery Testing

### Monthly DR Drill Checklist

Perform these tests monthly to validate DR procedures:

#### Database Recovery Test

- [ ] Create manual RDS snapshot
- [ ] Restore snapshot to test instance with different identifier
- [ ] Connect to restored instance and verify data integrity
- [ ] Run application smoke tests against restored instance
- [ ] Delete test instance after verification
- [ ] Document: Time to restore, any issues encountered

```bash
# Quick database recovery test script
TEST_SNAPSHOT="mw-prod-postgres-dr-test-$(date +%Y%m%d)"
TEST_INSTANCE="mw-prod-postgres-dr-test"

# Create snapshot
aws rds create-db-snapshot \
    --db-instance-identifier mw-prod-postgres \
    --db-snapshot-identifier "${TEST_SNAPSHOT}"

aws rds wait db-snapshot-available \
    --db-snapshot-identifier "${TEST_SNAPSHOT}"

# Restore to test instance
aws rds restore-db-instance-from-db-snapshot \
    --db-instance-identifier "${TEST_INSTANCE}" \
    --db-snapshot-identifier "${TEST_SNAPSHOT}" \
    --db-instance-class db.t3.micro \
    --db-subnet-group-name mw-prod-db-subnet

aws rds wait db-instance-available \
    --db-instance-identifier "${TEST_INSTANCE}"

echo "Test instance ready. Verify data integrity, then delete:"
echo "aws rds delete-db-instance --db-instance-identifier ${TEST_INSTANCE} --skip-final-snapshot"
```

#### Terraform State Recovery Test

- [ ] List S3 state versions and identify recovery point
- [ ] Download previous state version to local file
- [ ] Compare previous state with current state
- [ ] Document: Number of versions available, oldest version date

```bash
# State recovery test
aws s3api list-object-versions \
    --bucket middleware-platform-terraform-state \
    --prefix prod-aws/terraform.tfstate \
    --max-keys 5 \
    --query 'Versions[*].{VersionId:VersionId,Modified:LastModified}' \
    --output table
```

#### ECS Service Recovery Test

- [ ] Force a new deployment and verify rollout
- [ ] Test rollback to previous task definition
- [ ] Verify auto-scaling responds correctly
- [ ] Document: Deployment time, any issues

```bash
# ECS recovery test
aws ecs update-service \
    --cluster mw-prod-cluster \
    --service mw-prod-liberty \
    --force-new-deployment

aws ecs wait services-stable \
    --cluster mw-prod-cluster \
    --services mw-prod-liberty

# Verify health
curl -sf http://$(aws elbv2 describe-load-balancers --names mw-prod-alb --query 'LoadBalancers[0].DNSName' --output text)/health/ready
```

#### Infrastructure Recreation Test

- [ ] Review `terraform plan` output in non-production environment
- [ ] Verify all configuration is in version control
- [ ] Test Ansible playbook dry-run
- [ ] Document: Any drift from expected state

```bash
# Dry-run tests
cd automated/terraform/environments/prod-aws
terraform plan -detailed-exitcode

cd ../../..
ansible-playbook -i automated/ansible/inventory/dev.yml \
    automated/ansible/playbooks/site.yml --check --diff
```

### Recovery Verification Procedures

After any recovery operation, verify:

#### Application Health Checks

```bash
#!/bin/bash
# Post-recovery verification

ALB_DNS=$(aws elbv2 describe-load-balancers \
    --names mw-prod-alb \
    --query 'LoadBalancers[0].DNSName' \
    --output text)

echo "Testing application endpoints..."

# Health endpoints
curl -sf "http://${ALB_DNS}/health/ready" && echo "Ready: PASS" || echo "Ready: FAIL"
curl -sf "http://${ALB_DNS}/health/live" && echo "Live: PASS" || echo "Live: FAIL"
curl -sf "http://${ALB_DNS}/health/started" && echo "Started: PASS" || echo "Started: FAIL"

# Metrics endpoint
curl -sf "http://${ALB_DNS}/metrics" | head -5 && echo "Metrics: PASS" || echo "Metrics: FAIL"

# Application endpoint (adjust path as needed)
curl -sf "http://${ALB_DNS}/" && echo "Application: PASS" || echo "Application: FAIL"
```

#### Database Connectivity

```bash
#!/bin/bash
# Verify database connectivity from ECS

# Get a running task
TASK_ARN=$(aws ecs list-tasks \
    --cluster mw-prod-cluster \
    --service-name mw-prod-liberty \
    --query 'taskArns[0]' \
    --output text)

# Execute command in container to test DB
aws ecs execute-command \
    --cluster mw-prod-cluster \
    --task "${TASK_ARN}" \
    --container liberty \
    --command "curl -sf localhost:9080/health/ready" \
    --interactive
```

#### Monitoring Verification

```bash
#!/bin/bash
# Verify monitoring stack

MONITORING_IP=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=mw-prod-monitoring" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

# Prometheus targets
curl -sf "http://${MONITORING_IP}:9090/api/v1/targets" | jq '.data.activeTargets | length'

# Grafana health
curl -sf "http://${MONITORING_IP}:3000/api/health"
```

### Documentation of Test Results

After each DR drill, document:

| Field | Value |
|-------|-------|
| Test Date | YYYY-MM-DD |
| Test Type | Database / State / ECS / Full |
| Performed By | Name |
| RTO Achieved | X minutes |
| RPO Achieved | X minutes |
| Issues Encountered | Description |
| Remediation Actions | What was fixed |
| Next Test Date | YYYY-MM-DD |

Store test results in: `docs/dr-test-results/YYYY-MM-DD.md`

---

## Contact and Escalation

### Escalation Template

```
INCIDENT REPORT
===============

Date/Time: YYYY-MM-DD HH:MM UTC
Severity: P1/P2/P3/P4
Status: Active/Mitigated/Resolved

SUMMARY
-------
Brief description of the issue.

IMPACT
------
- Services affected:
- Users affected:
- Data loss (Y/N, amount):

TIMELINE
--------
HH:MM - Issue detected
HH:MM - Initial triage
HH:MM - Escalation
HH:MM - Mitigation applied
HH:MM - Resolution

ROOT CAUSE
----------
Description of what caused the issue.

RESOLUTION
----------
Steps taken to resolve.

PREVENTION
----------
Actions to prevent recurrence.

ATTENDEES
---------
- Primary responder:
- Escalated to:
- Management notified:
```

### Escalation Contacts

| Role | Primary | Backup | Contact Method |
|------|---------|--------|----------------|
| On-Call Engineer | [Name] | [Name] | [Phone/Slack] |
| Platform Lead | [Name] | [Name] | [Phone/Slack] |
| Database Admin | [Name] | [Name] | [Phone/Slack] |
| AWS Account Owner | [Name] | [Name] | [Phone/Slack] |
| Management | [Name] | [Name] | [Phone/Slack] |

### Severity Definitions

| Severity | Definition | Response Time | Example |
|----------|------------|---------------|---------|
| P1 - Critical | Complete service outage | 15 minutes | All production down |
| P2 - High | Major functionality impacted | 1 hour | Database corruption |
| P3 - Medium | Minor functionality impacted | 4 hours | Single instance failure |
| P4 - Low | No immediate impact | 24 hours | Backup job failed |

### External Support Contacts

| Service | Support Portal | Phone |
|---------|----------------|-------|
| AWS Support | https://console.aws.amazon.com/support/ | (business/enterprise) |
| AWS Account ID | [Your Account ID] | N/A |
| Domain Registrar | [Provider] | [Phone] |

---

## Related Documentation

- [Credential Setup Guide](CREDENTIAL_SETUP.md) - Initial credential configuration
- [End-to-End Testing](END_TO_END_TESTING.md) - Comprehensive testing procedures
- [Terraform Troubleshooting](troubleshooting/terraform-aws.md) - Common AWS/Terraform issues
- [Local Kubernetes Deployment](LOCAL_KUBERNETES_DEPLOYMENT.md) - Local cluster procedures

---

## Revision History

| Date | Author | Changes |
|------|--------|---------|
| 2026-01-02 | [Author] | Initial document creation |
