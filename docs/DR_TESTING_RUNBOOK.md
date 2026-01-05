# Disaster Recovery Testing Runbook

This runbook provides step-by-step procedures for testing disaster recovery capabilities of the Middleware Automation Platform. Regular DR testing validates recovery procedures, identifies gaps, and ensures the team is prepared for actual incidents.

## Table of Contents

1. [Overview](#overview)
2. [Pre-requisites and Preparation](#pre-requisites-and-preparation)
3. [Failover Test Procedure](#failover-test-procedure)
4. [Failback Procedure](#failback-procedure)
5. [RDS Replica Promotion Steps](#rds-replica-promotion-steps)
6. [Route53 Failover Verification](#route53-failover-verification)
7. [Recovery Time and Point Objectives](#recovery-time-and-point-objectives)
8. [Post-Test Validation Checklist](#post-test-validation-checklist)
9. [Rollback Procedures](#rollback-procedures)
10. [Troubleshooting](#troubleshooting)
11. [Terraform Resource Reference](#terraform-resource-reference)

---

## Overview

### DR Testing Schedule

| Test Type | Frequency | Duration | Participants |
|-----------|-----------|----------|--------------|
| Database Backup Validation | Weekly | 30 min | Operations |
| ECS Failover Test | Monthly | 1 hour | Operations, Dev |
| Full DR Drill | Quarterly | 4 hours | All teams |
| Cross-Region DR Test | Annually | 8 hours | All teams + Management |

### Recovery Objectives Summary

| Component | RTO Target | RPO Target | Current Capability |
|-----------|------------|------------|-------------------|
| ECS Service | 15 min | N/A (stateless) | Auto-healing enabled |
| RDS PostgreSQL | 1-4 hours | 5 min (PITR) | Multi-AZ, automated backups |
| ElastiCache Redis | 30 min | 1 day | Multi-AZ with automatic failover |
| Terraform State | 1 hour | Real-time | S3 versioning enabled |
| Container Images | 15 min | Last push | ECR with lifecycle policies |

---

## Pre-requisites and Preparation

### Required Access and Permissions

- [ ] AWS Console access with appropriate IAM permissions
- [ ] AWS CLI configured with credentials
- [ ] kubectl access to local Kubernetes cluster (if applicable)
- [ ] SSH keys for EC2 access (`~/.ssh/ansible_ed25519`)
- [ ] Terraform CLI installed (version 1.0+)
- [ ] Access to Secrets Manager for credential retrieval

### Verify AWS CLI Configuration

```bash
#!/bin/bash
# Verify AWS CLI access and permissions

# Check AWS identity
aws sts get-caller-identity

# Verify RDS permissions
aws rds describe-db-instances --db-instance-identifier mw-prod-postgres --query 'DBInstances[0].DBInstanceStatus' --output text

# Verify ECS permissions
aws ecs describe-clusters --clusters mw-prod-cluster --query 'clusters[0].status' --output text

# Verify Secrets Manager access
aws secretsmanager list-secrets --query 'SecretList[?contains(Name, `mw-prod`)].Name' --output table
```

### Pre-Test Notifications

Before starting DR testing:

1. **Notify stakeholders** via email/Slack
2. **Schedule maintenance window** if testing in production
3. **Confirm backup availability** (see verification commands below)
4. **Document current state** for comparison

### Verify Backup Availability

```bash
#!/bin/bash
# Pre-test backup verification script

echo "=== RDS Backup Status ==="
aws rds describe-db-instances \
    --db-instance-identifier mw-prod-postgres \
    --query 'DBInstances[0].{
        Status: DBInstanceStatus,
        MultiAZ: MultiAZ,
        BackupRetention: BackupRetentionPeriod,
        LatestRestorableTime: LatestRestorableTime,
        BackupWindow: PreferredBackupWindow
    }' \
    --output table

echo ""
echo "=== Recent RDS Snapshots ==="
aws rds describe-db-snapshots \
    --db-instance-identifier mw-prod-postgres \
    --query 'DBSnapshots | sort_by(@, &SnapshotCreateTime) | [-5:].{
        ID: DBSnapshotIdentifier,
        Status: Status,
        Created: SnapshotCreateTime,
        Type: SnapshotType
    }' \
    --output table

echo ""
echo "=== ECR Images Available ==="
aws ecr describe-images \
    --repository-name mw-prod-liberty \
    --query 'imageDetails | sort_by(@, &imagePushedAt) | [-5:].{
        Tags: imageTags[0],
        Pushed: imagePushedAt,
        SizeMB: to_string(imageSizeInBytes)
    }' \
    --output table

echo ""
echo "=== ElastiCache Snapshots ==="
aws elasticache describe-snapshots \
    --cache-cluster-id mw-prod-redis \
    --query 'Snapshots[*].{
        Name: SnapshotName,
        Status: SnapshotStatus,
        Created: NodeSnapshots[0].SnapshotCreateTime
    }' \
    --output table 2>/dev/null || echo "No snapshots found (or Multi-AZ replication group)"

echo ""
echo "=== Terraform State Versions ==="
aws s3api list-object-versions \
    --bucket middleware-platform-terraform-state \
    --prefix prod-aws/terraform.tfstate \
    --max-keys 5 \
    --query 'Versions[*].{
        VersionId: VersionId,
        Modified: LastModified,
        IsLatest: IsLatest
    }' \
    --output table
```

### Create Pre-Test Manual Snapshot

```bash
#!/bin/bash
# Create manual backup before DR test

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
TEST_NAME="dr-test-${TIMESTAMP}"

echo "Creating pre-test RDS snapshot..."
aws rds create-db-snapshot \
    --db-instance-identifier mw-prod-postgres \
    --db-snapshot-identifier "mw-prod-postgres-${TEST_NAME}" \
    --tags Key=Purpose,Value=DR-Test Key=TestName,Value="${TEST_NAME}"

echo "Waiting for snapshot to become available..."
aws rds wait db-snapshot-available \
    --db-snapshot-identifier "mw-prod-postgres-${TEST_NAME}"

echo "Pre-test snapshot created: mw-prod-postgres-${TEST_NAME}"
```

---

## Failover Test Procedure

### Test 1: ECS Service Failover

This test validates ECS auto-recovery and deployment capabilities.

#### Step 1: Document Current State

```bash
#!/bin/bash
# Document current ECS state

CLUSTER="mw-prod-cluster"
SERVICE="mw-prod-liberty"

echo "=== Current ECS Service State ==="
aws ecs describe-services \
    --cluster "${CLUSTER}" \
    --services "${SERVICE}" \
    --query 'services[0].{
        Status: status,
        DesiredCount: desiredCount,
        RunningCount: runningCount,
        PendingCount: pendingCount,
        TaskDefinition: taskDefinition
    }' \
    --output table

echo ""
echo "=== Running Tasks ==="
aws ecs list-tasks \
    --cluster "${CLUSTER}" \
    --service-name "${SERVICE}" \
    --desired-status RUNNING \
    --query 'taskArns' \
    --output table

echo ""
echo "=== Target Group Health ==="
TG_ARN=$(aws elbv2 describe-target-groups \
    --names mw-prod-liberty-ecs-tg \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text 2>/dev/null)

if [ -n "${TG_ARN}" ]; then
    aws elbv2 describe-target-health \
        --target-group-arn "${TG_ARN}" \
        --query 'TargetHealthDescriptions[*].{
            Target: Target.Id,
            Port: Target.Port,
            Health: TargetHealth.State
        }' \
        --output table
fi
```

#### Step 2: Simulate Task Failure

```bash
#!/bin/bash
# Simulate ECS task failure by stopping a task

CLUSTER="mw-prod-cluster"
SERVICE="mw-prod-liberty"

# Get a running task ARN
TASK_ARN=$(aws ecs list-tasks \
    --cluster "${CLUSTER}" \
    --service-name "${SERVICE}" \
    --desired-status RUNNING \
    --query 'taskArns[0]' \
    --output text)

if [ "${TASK_ARN}" != "None" ] && [ -n "${TASK_ARN}" ]; then
    echo "Stopping task: ${TASK_ARN}"
    echo "Start time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

    aws ecs stop-task \
        --cluster "${CLUSTER}" \
        --task "${TASK_ARN}" \
        --reason "DR Test - Simulated failure"

    echo ""
    echo "Task stop initiated. Monitoring recovery..."
else
    echo "ERROR: No running tasks found"
    exit 1
fi
```

#### Step 3: Monitor Recovery

```bash
#!/bin/bash
# Monitor ECS service recovery

CLUSTER="mw-prod-cluster"
SERVICE="mw-prod-liberty"
START_TIME=$(date +%s)
TIMEOUT=300  # 5 minutes

echo "Monitoring ECS recovery (timeout: ${TIMEOUT}s)..."

while true; do
    RUNNING=$(aws ecs describe-services \
        --cluster "${CLUSTER}" \
        --services "${SERVICE}" \
        --query 'services[0].runningCount' \
        --output text)

    DESIRED=$(aws ecs describe-services \
        --cluster "${CLUSTER}" \
        --services "${SERVICE}" \
        --query 'services[0].desiredCount' \
        --output text)

    ELAPSED=$(($(date +%s) - START_TIME))

    echo "[+${ELAPSED}s] Running: ${RUNNING}/${DESIRED}"

    if [ "${RUNNING}" -ge "${DESIRED}" ]; then
        echo ""
        echo "SUCCESS: Service recovered in ${ELAPSED} seconds"
        break
    fi

    if [ ${ELAPSED} -ge ${TIMEOUT} ]; then
        echo ""
        echo "TIMEOUT: Service did not recover within ${TIMEOUT} seconds"
        exit 1
    fi

    sleep 10
done

# Verify health endpoint
ALB_DNS=$(aws elbv2 describe-load-balancers \
    --names mw-prod-alb \
    --query 'LoadBalancers[0].DNSName' \
    --output text)

echo ""
echo "Verifying application health..."
curl -sf "http://${ALB_DNS}/health/ready" && echo " - Health check PASSED" || echo " - Health check FAILED"
```

#### Step 4: Record Results

| Metric | Target | Actual | Pass/Fail |
|--------|--------|--------|-----------|
| Recovery Time | < 5 min | _____ | |
| Tasks Recovered | All | _____ | |
| Health Check | Pass | _____ | |
| Data Loss | None | _____ | |

---

### Test 2: Database Failover (Multi-AZ)

This test validates RDS Multi-AZ automatic failover.

#### Step 2.1: Verify Multi-AZ Configuration

```bash
#!/bin/bash
# Verify RDS Multi-AZ status

aws rds describe-db-instances \
    --db-instance-identifier mw-prod-postgres \
    --query 'DBInstances[0].{
        MultiAZ: MultiAZ,
        AvailabilityZone: AvailabilityZone,
        SecondaryAZ: SecondaryAvailabilityZone,
        Status: DBInstanceStatus
    }' \
    --output table
```

#### Step 2.2: Initiate Failover (Reboot with Failover)

**WARNING: This will cause a brief database outage (typically 60-120 seconds).**

```bash
#!/bin/bash
# Initiate RDS Multi-AZ failover
# CAUTION: Only run during maintenance window

echo "WARNING: This will initiate database failover and cause brief outage."
read -p "Continue? (yes/no): " confirm

if [ "${confirm}" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo "Recording start time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
START_TIME=$(date +%s)

# Get current AZ
CURRENT_AZ=$(aws rds describe-db-instances \
    --db-instance-identifier mw-prod-postgres \
    --query 'DBInstances[0].AvailabilityZone' \
    --output text)

echo "Current AZ: ${CURRENT_AZ}"
echo "Initiating failover..."

aws rds reboot-db-instance \
    --db-instance-identifier mw-prod-postgres \
    --force-failover

echo "Failover initiated. Monitoring..."
```

#### Step 2.3: Monitor Failover

```bash
#!/bin/bash
# Monitor RDS failover progress

DB_IDENTIFIER="mw-prod-postgres"
START_TIME=$(date +%s)
ORIGINAL_AZ="${1:-unknown}"

echo "Monitoring RDS failover..."

while true; do
    STATUS=$(aws rds describe-db-instances \
        --db-instance-identifier "${DB_IDENTIFIER}" \
        --query 'DBInstances[0].DBInstanceStatus' \
        --output text)

    CURRENT_AZ=$(aws rds describe-db-instances \
        --db-instance-identifier "${DB_IDENTIFIER}" \
        --query 'DBInstances[0].AvailabilityZone' \
        --output text)

    ELAPSED=$(($(date +%s) - START_TIME))

    echo "[+${ELAPSED}s] Status: ${STATUS}, AZ: ${CURRENT_AZ}"

    if [ "${STATUS}" == "available" ]; then
        echo ""
        echo "SUCCESS: Database available after ${ELAPSED} seconds"

        if [ "${CURRENT_AZ}" != "${ORIGINAL_AZ}" ] && [ "${ORIGINAL_AZ}" != "unknown" ]; then
            echo "Failover confirmed: AZ changed from ${ORIGINAL_AZ} to ${CURRENT_AZ}"
        fi
        break
    fi

    if [ ${ELAPSED} -ge 600 ]; then
        echo "WARNING: Failover taking longer than expected"
    fi

    sleep 15
done
```

#### Step 2.4: Verify Application Connectivity

```bash
#!/bin/bash
# Verify application connectivity after database failover

CLUSTER="mw-prod-cluster"
SERVICE="mw-prod-liberty"

echo "Waiting 30 seconds for connection pool refresh..."
sleep 30

# Force ECS task refresh if needed
echo "Forcing ECS service deployment to refresh connections..."
aws ecs update-service \
    --cluster "${CLUSTER}" \
    --service "${SERVICE}" \
    --force-new-deployment

echo "Waiting for service stabilization..."
aws ecs wait services-stable \
    --cluster "${CLUSTER}" \
    --services "${SERVICE}"

# Verify health
ALB_DNS=$(aws elbv2 describe-load-balancers \
    --names mw-prod-alb \
    --query 'LoadBalancers[0].DNSName' \
    --output text)

echo ""
echo "Testing application endpoints..."
curl -sf "http://${ALB_DNS}/health/ready" && echo "Health: PASS" || echo "Health: FAIL"
```

---

### Test 3: ElastiCache Redis Failover

This test validates Redis Multi-AZ automatic failover.

#### Step 3.1: Verify ElastiCache Configuration

```bash
#!/bin/bash
# Verify ElastiCache Multi-AZ configuration

aws elasticache describe-replication-groups \
    --replication-group-id mw-prod-redis \
    --query 'ReplicationGroups[0].{
        Status: Status,
        AutomaticFailover: AutomaticFailover,
        MultiAZ: MultiAZ,
        PrimaryEndpoint: NodeGroups[0].PrimaryEndpoint.Address,
        NodeCount: length(NodeGroups[0].NodeGroupMembers)
    }' \
    --output table
```

#### Step 3.2: Initiate Redis Failover

**WARNING: This will cause a brief cache service disruption.**

```bash
#!/bin/bash
# Initiate ElastiCache failover test

echo "WARNING: This will initiate Redis failover."
read -p "Continue? (yes/no): " confirm

if [ "${confirm}" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo "Recording start time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

aws elasticache test-failover \
    --replication-group-id mw-prod-redis \
    --node-group-id 0001

echo "Failover test initiated."
```

#### Step 3.3: Monitor Redis Failover

```bash
#!/bin/bash
# Monitor ElastiCache failover

START_TIME=$(date +%s)

while true; do
    STATUS=$(aws elasticache describe-replication-groups \
        --replication-group-id mw-prod-redis \
        --query 'ReplicationGroups[0].Status' \
        --output text)

    ELAPSED=$(($(date +%s) - START_TIME))

    echo "[+${ELAPSED}s] Status: ${STATUS}"

    if [ "${STATUS}" == "available" ]; then
        echo ""
        echo "SUCCESS: Redis available after ${ELAPSED} seconds"
        break
    fi

    if [ ${ELAPSED} -ge 300 ]; then
        echo "WARNING: Failover taking longer than expected"
    fi

    sleep 10
done
```

---

## Failback Procedure

### ECS Failback (Rollback to Previous Task Definition)

```bash
#!/bin/bash
# Rollback ECS to previous task definition

CLUSTER="mw-prod-cluster"
SERVICE="mw-prod-liberty"

echo "=== Current Task Definition ==="
CURRENT_TASK_DEF=$(aws ecs describe-services \
    --cluster "${CLUSTER}" \
    --services "${SERVICE}" \
    --query 'services[0].taskDefinition' \
    --output text)

echo "Current: ${CURRENT_TASK_DEF}"

echo ""
echo "=== Available Task Definitions ==="
aws ecs list-task-definitions \
    --family-prefix mw-prod-liberty \
    --sort DESC \
    --max-items 5 \
    --query 'taskDefinitionArns' \
    --output table

echo ""
read -p "Enter task definition to rollback to (e.g., mw-prod-liberty:3): " TARGET_TASK_DEF

if [ -z "${TARGET_TASK_DEF}" ]; then
    echo "No task definition specified. Aborted."
    exit 1
fi

echo "Rolling back to: ${TARGET_TASK_DEF}"
aws ecs update-service \
    --cluster "${CLUSTER}" \
    --service "${SERVICE}" \
    --task-definition "${TARGET_TASK_DEF}"

echo "Waiting for service stabilization..."
aws ecs wait services-stable \
    --cluster "${CLUSTER}" \
    --services "${SERVICE}"

echo "Rollback complete."
```

### Database Failback (Return to Primary AZ)

RDS Multi-AZ failback is automatic. To manually trigger:

```bash
#!/bin/bash
# Trigger RDS failback to original AZ

echo "Current AZ configuration:"
aws rds describe-db-instances \
    --db-instance-identifier mw-prod-postgres \
    --query 'DBInstances[0].{
        PrimaryAZ: AvailabilityZone,
        SecondaryAZ: SecondaryAvailabilityZone
    }' \
    --output table

echo ""
echo "To failback, initiate another reboot with failover:"
echo "aws rds reboot-db-instance --db-instance-identifier mw-prod-postgres --force-failover"
echo ""
read -p "Proceed with failback? (yes/no): " confirm

if [ "${confirm}" == "yes" ]; then
    aws rds reboot-db-instance \
        --db-instance-identifier mw-prod-postgres \
        --force-failover

    echo "Failback initiated. Monitor with:"
    echo "watch -n 5 'aws rds describe-db-instances --db-instance-identifier mw-prod-postgres --query \"DBInstances[0].{Status:DBInstanceStatus,AZ:AvailabilityZone}\" --output table'"
fi
```

---

## RDS Replica Promotion Steps

Use this procedure when the primary RDS instance is unrecoverable and you need to promote a read replica.

> **Note:** The current Terraform configuration does not include read replicas by default. These steps are for reference if cross-region read replicas are added.

### Step 1: Create Cross-Region Read Replica (Pre-requisite)

```bash
#!/bin/bash
# Create cross-region read replica (run before DR event)

SOURCE_DB="mw-prod-postgres"
DR_REGION="us-west-2"
REPLICA_ID="mw-dr-postgres-replica"

aws rds create-db-instance-read-replica \
    --db-instance-identifier "${REPLICA_ID}" \
    --source-db-instance-identifier "arn:aws:rds:us-east-1:$(aws sts get-caller-identity --query Account --output text):db:${SOURCE_DB}" \
    --region "${DR_REGION}" \
    --db-instance-class db.t3.micro \
    --publicly-accessible false \
    --storage-type gp3

echo "Cross-region replica creation initiated in ${DR_REGION}"
```

### Step 2: Verify Replica Status

```bash
#!/bin/bash
# Check replica replication status

DR_REGION="us-west-2"
REPLICA_ID="mw-dr-postgres-replica"

aws rds describe-db-instances \
    --region "${DR_REGION}" \
    --db-instance-identifier "${REPLICA_ID}" \
    --query 'DBInstances[0].{
        Status: DBInstanceStatus,
        ReplicaLag: StatusInfos[?StatusType==`read replication`].Normal,
        SourceDBInstance: ReadReplicaSourceDBInstanceIdentifier
    }' \
    --output table
```

### Step 3: Promote Read Replica

**WARNING: This operation is irreversible. The replica becomes a standalone instance.**

```bash
#!/bin/bash
# Promote read replica to standalone instance

DR_REGION="us-west-2"
REPLICA_ID="mw-dr-postgres-replica"

echo "WARNING: Promoting replica will break replication permanently."
echo "This should only be done when primary is unrecoverable."
read -p "Proceed with promotion? (yes/no): " confirm

if [ "${confirm}" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo "Promoting replica..."
aws rds promote-read-replica \
    --region "${DR_REGION}" \
    --db-instance-identifier "${REPLICA_ID}" \
    --backup-retention-period 7

echo "Promotion initiated. Monitor status:"
echo "aws rds describe-db-instances --region ${DR_REGION} --db-instance-identifier ${REPLICA_ID} --query 'DBInstances[0].DBInstanceStatus'"
```

### Step 4: Update Application Configuration

After promoting the replica, update the application to use the new endpoint:

```bash
#!/bin/bash
# Update Secrets Manager with new database endpoint

DR_REGION="us-west-2"
REPLICA_ID="mw-dr-postgres-replica"

# Get new endpoint
NEW_ENDPOINT=$(aws rds describe-db-instances \
    --region "${DR_REGION}" \
    --db-instance-identifier "${REPLICA_ID}" \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text)

echo "New database endpoint: ${NEW_ENDPOINT}"

# Get current secret
SECRET_ARN=$(aws secretsmanager list-secrets \
    --query 'SecretList[?contains(Name, `database/credentials`)].ARN' \
    --output text)

CURRENT_SECRET=$(aws secretsmanager get-secret-value \
    --secret-id "${SECRET_ARN}" \
    --query 'SecretString' \
    --output text)

# Update host in secret
UPDATED_SECRET=$(echo "${CURRENT_SECRET}" | jq --arg host "${NEW_ENDPOINT}" '.host = $host')

echo "Updating Secrets Manager..."
aws secretsmanager put-secret-value \
    --secret-id "${SECRET_ARN}" \
    --secret-string "${UPDATED_SECRET}"

echo "Secret updated. Force ECS deployment to pick up changes:"
echo "aws ecs update-service --cluster mw-prod-cluster --service mw-prod-liberty --force-new-deployment"
```

---

## Route53 Failover Verification

> **Note:** The current Terraform configuration uses ALB DNS directly. These procedures are for environments with Route53 failover routing.

### Verify Route53 Health Checks

```bash
#!/bin/bash
# List Route53 health checks

aws route53 list-health-checks \
    --query 'HealthChecks[*].{
        Id: Id,
        Type: HealthCheckConfig.Type,
        FQDN: HealthCheckConfig.FullyQualifiedDomainName,
        ResourcePath: HealthCheckConfig.ResourcePath
    }' \
    --output table
```

### Test Route53 Failover

```bash
#!/bin/bash
# Test Route53 DNS resolution

DOMAIN_NAME="app.example.com"

echo "Current DNS resolution:"
dig +short "${DOMAIN_NAME}"

echo ""
echo "Testing from multiple regions (requires DNS testing tool):"
# nslookup "${DOMAIN_NAME}" - from different regions
```

### Simulate Primary Failure

```bash
#!/bin/bash
# Manually set Route53 health check to unhealthy (for testing)

HEALTH_CHECK_ID="your-health-check-id"

# Update health check to a non-existent path (will fail)
aws route53 update-health-check \
    --health-check-id "${HEALTH_CHECK_ID}" \
    --resource-path "/nonexistent-path-for-dr-test"

echo "Health check updated to fail. Monitor DNS propagation..."
echo "Revert with correct path after testing."
```

---

## Recovery Time and Point Objectives

### RTO (Recovery Time Objective)

| Scenario | Target RTO | Steps | Estimated Time |
|----------|------------|-------|----------------|
| Single ECS task failure | 2 min | Auto-recovery | 1-2 min |
| Full ECS service failure | 15 min | Force new deployment | 5-10 min |
| RDS Multi-AZ failover | 2 min | Automatic | 60-120 sec |
| RDS snapshot restore | 4 hours | Manual restore | 1-4 hours |
| Complete infrastructure rebuild | 2 hours | Terraform apply | 30-120 min |

### RPO (Recovery Point Objective)

| Component | Target RPO | Mechanism | Current Configuration |
|-----------|------------|-----------|----------------------|
| RDS PostgreSQL | 5 min | PITR with transaction logs | `backup_retention_period = 7` |
| ElastiCache Redis | 1 day | Daily snapshots | `snapshot_retention_limit = 7` |
| Terraform State | Real-time | S3 versioning | Versioning enabled |
| Application Config | Last commit | Git repository | GitHub/GitLab |
| Container Images | Last push | ECR | 10 tagged images retained |

### Validation Commands

```bash
#!/bin/bash
# Validate RTO/RPO capabilities

echo "=== RPO Validation ==="

echo ""
echo "RDS PITR Window:"
aws rds describe-db-instances \
    --db-instance-identifier mw-prod-postgres \
    --query 'DBInstances[0].{
        BackupRetention: BackupRetentionPeriod,
        LatestRestorableTime: LatestRestorableTime,
        EarliestRestorableTime: LatestRestorableTime
    }' \
    --output table

echo ""
echo "Terraform State Versions (last 24h):"
aws s3api list-object-versions \
    --bucket middleware-platform-terraform-state \
    --prefix prod-aws/terraform.tfstate \
    --query "Versions[?LastModified>='$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)'].{
        Modified: LastModified,
        VersionId: VersionId
    }" \
    --output table

echo ""
echo "ECR Image Retention:"
aws ecr describe-images \
    --repository-name mw-prod-liberty \
    --query 'imageDetails | length(@)'
echo "images available"
```

---

## Post-Test Validation Checklist

After completing DR tests, validate all systems are functioning correctly.

### Automated Validation Script

```bash
#!/bin/bash
# Post-DR test validation script

echo "============================================="
echo "Post-DR Test Validation"
echo "============================================="
echo ""

ERRORS=0

# 1. ECS Service Health
echo "[1/7] Checking ECS service health..."
ECS_STATUS=$(aws ecs describe-services \
    --cluster mw-prod-cluster \
    --services mw-prod-liberty \
    --query 'services[0].{Running:runningCount,Desired:desiredCount}' \
    --output text)

RUNNING=$(echo "${ECS_STATUS}" | awk '{print $1}')
DESIRED=$(echo "${ECS_STATUS}" | awk '{print $2}')

if [ "${RUNNING}" -ge "${DESIRED}" ] && [ "${RUNNING}" -gt 0 ]; then
    echo "  PASS: ECS tasks healthy (${RUNNING}/${DESIRED})"
else
    echo "  FAIL: ECS tasks not healthy (${RUNNING}/${DESIRED})"
    ERRORS=$((ERRORS + 1))
fi

# 2. ALB Target Health
echo "[2/7] Checking ALB target health..."
TG_ARN=$(aws elbv2 describe-target-groups \
    --names mw-prod-liberty-ecs-tg \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text 2>/dev/null)

if [ -n "${TG_ARN}" ] && [ "${TG_ARN}" != "None" ]; then
    HEALTHY=$(aws elbv2 describe-target-health \
        --target-group-arn "${TG_ARN}" \
        --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`] | length(@)' \
        --output text)

    if [ "${HEALTHY}" -gt 0 ]; then
        echo "  PASS: ${HEALTHY} healthy targets in ALB"
    else
        echo "  FAIL: No healthy targets in ALB"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo "  SKIP: ECS target group not found (EC2 mode?)"
fi

# 3. RDS Database Status
echo "[3/7] Checking RDS database status..."
DB_STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier mw-prod-postgres \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text)

if [ "${DB_STATUS}" == "available" ]; then
    echo "  PASS: RDS database available"
else
    echo "  FAIL: RDS database status: ${DB_STATUS}"
    ERRORS=$((ERRORS + 1))
fi

# 4. ElastiCache Status
echo "[4/7] Checking ElastiCache status..."
CACHE_STATUS=$(aws elasticache describe-replication-groups \
    --replication-group-id mw-prod-redis \
    --query 'ReplicationGroups[0].Status' \
    --output text 2>/dev/null)

if [ "${CACHE_STATUS}" == "available" ]; then
    echo "  PASS: ElastiCache available"
else
    echo "  FAIL: ElastiCache status: ${CACHE_STATUS}"
    ERRORS=$((ERRORS + 1))
fi

# 5. Application Health Endpoints
echo "[5/7] Checking application health endpoints..."
ALB_DNS=$(aws elbv2 describe-load-balancers \
    --names mw-prod-alb \
    --query 'LoadBalancers[0].DNSName' \
    --output text)

for endpoint in "health/ready" "health/live" "health/started"; do
    if curl -sf "http://${ALB_DNS}/${endpoint}" > /dev/null 2>&1; then
        echo "  PASS: /${endpoint} responding"
    else
        echo "  FAIL: /${endpoint} not responding"
        ERRORS=$((ERRORS + 1))
    fi
done

# 6. Metrics Endpoint (internal)
echo "[6/7] Checking metrics endpoint..."
if curl -sf "http://${ALB_DNS}/metrics" 2>&1 | grep -q "Forbidden"; then
    echo "  PASS: /metrics correctly blocked from public"
else
    echo "  INFO: /metrics endpoint status unclear"
fi

# 7. Recent CloudWatch Errors
echo "[7/7] Checking recent CloudWatch errors..."
ERROR_COUNT=$(aws logs filter-log-events \
    --log-group-name "/ecs/mw-prod-liberty" \
    --filter-pattern "ERROR" \
    --start-time $(date -d '15 minutes ago' +%s000) \
    --query 'events | length(@)' \
    --output text 2>/dev/null || echo "0")

if [ "${ERROR_COUNT}" -lt 10 ]; then
    echo "  PASS: ${ERROR_COUNT} errors in last 15 minutes"
else
    echo "  WARN: ${ERROR_COUNT} errors in last 15 minutes (review logs)"
fi

echo ""
echo "============================================="
if [ ${ERRORS} -eq 0 ]; then
    echo "VALIDATION COMPLETE: All checks passed"
else
    echo "VALIDATION COMPLETE: ${ERRORS} check(s) failed"
fi
echo "============================================="

exit ${ERRORS}
```

### Manual Validation Checklist

- [ ] ECS service running with desired task count
- [ ] All ALB targets healthy
- [ ] RDS database in "available" state
- [ ] ElastiCache in "available" state
- [ ] Application /health/ready returns 200
- [ ] Application /health/live returns 200
- [ ] Prometheus scraping metrics successfully
- [ ] Grafana dashboards showing data
- [ ] No critical CloudWatch alarms active
- [ ] Terraform state accessible and not corrupted

---

## Rollback Procedures

### Emergency ECS Rollback

```bash
#!/bin/bash
# Emergency rollback to last known good ECS configuration

CLUSTER="mw-prod-cluster"
SERVICE="mw-prod-liberty"

echo "=== Emergency ECS Rollback ==="

# List recent task definitions
echo "Recent task definitions:"
aws ecs list-task-definitions \
    --family-prefix mw-prod-liberty \
    --sort DESC \
    --max-items 5 \
    --query 'taskDefinitionArns' \
    --output table

# Get the second-to-last (previous) task definition
PREVIOUS_TASK_DEF=$(aws ecs list-task-definitions \
    --family-prefix mw-prod-liberty \
    --sort DESC \
    --max-items 2 \
    --query 'taskDefinitionArns[1]' \
    --output text)

echo ""
echo "Rolling back to: ${PREVIOUS_TASK_DEF}"
read -p "Confirm rollback? (yes/no): " confirm

if [ "${confirm}" == "yes" ]; then
    aws ecs update-service \
        --cluster "${CLUSTER}" \
        --service "${SERVICE}" \
        --task-definition "${PREVIOUS_TASK_DEF}"

    echo "Rollback initiated. Monitoring..."
    aws ecs wait services-stable \
        --cluster "${CLUSTER}" \
        --services "${SERVICE}"

    echo "Rollback complete."
else
    echo "Rollback aborted."
fi
```

### Emergency Database Restore

```bash
#!/bin/bash
# Emergency database restore from snapshot

echo "=== Emergency Database Restore ==="

# List available snapshots
echo "Available snapshots:"
aws rds describe-db-snapshots \
    --db-instance-identifier mw-prod-postgres \
    --query 'DBSnapshots | sort_by(@, &SnapshotCreateTime) | [-5:].{
        ID: DBSnapshotIdentifier,
        Created: SnapshotCreateTime,
        Status: Status
    }' \
    --output table

echo ""
read -p "Enter snapshot ID to restore from: " SNAPSHOT_ID

if [ -z "${SNAPSHOT_ID}" ]; then
    echo "No snapshot specified. Aborted."
    exit 1
fi

RESTORED_ID="mw-prod-postgres-emergency-$(date +%Y%m%d-%H%M%S)"

echo "Restoring to new instance: ${RESTORED_ID}"

# Get current security group
SG_ID=$(aws rds describe-db-instances \
    --db-instance-identifier mw-prod-postgres \
    --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
    --output text)

# Restore from snapshot
aws rds restore-db-instance-from-db-snapshot \
    --db-instance-identifier "${RESTORED_ID}" \
    --db-snapshot-identifier "${SNAPSHOT_ID}" \
    --db-subnet-group-name mw-prod-db-subnet \
    --vpc-security-group-ids "${SG_ID}" \
    --multi-az \
    --deletion-protection

echo "Restore initiated. Waiting for availability..."
aws rds wait db-instance-available \
    --db-instance-identifier "${RESTORED_ID}"

NEW_ENDPOINT=$(aws rds describe-db-instances \
    --db-instance-identifier "${RESTORED_ID}" \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text)

echo ""
echo "Restored instance available: ${RESTORED_ID}"
echo "Endpoint: ${NEW_ENDPOINT}"
echo ""
echo "Next steps:"
echo "1. Verify data integrity on restored instance"
echo "2. Update Secrets Manager with new endpoint"
echo "3. Force ECS deployment to use new endpoint"
echo "4. Delete old instance after verification period"
```

### Terraform State Rollback

```bash
#!/bin/bash
# Rollback Terraform state to previous version

BUCKET="middleware-platform-terraform-state"
KEY="prod-aws/terraform.tfstate"

echo "=== Terraform State Rollback ==="

# List versions
echo "Available versions:"
aws s3api list-object-versions \
    --bucket "${BUCKET}" \
    --prefix "${KEY}" \
    --max-keys 10 \
    --query 'Versions[*].{
        VersionId: VersionId,
        Modified: LastModified,
        IsLatest: IsLatest
    }' \
    --output table

echo ""
read -p "Enter version ID to restore: " VERSION_ID

if [ -z "${VERSION_ID}" ]; then
    echo "No version specified. Aborted."
    exit 1
fi

# Download the version locally first
echo "Downloading version ${VERSION_ID}..."
aws s3api get-object \
    --bucket "${BUCKET}" \
    --key "${KEY}" \
    --version-id "${VERSION_ID}" \
    terraform.tfstate.restored

echo "Downloaded to: terraform.tfstate.restored"
echo ""
echo "Review the state file, then run:"
echo "aws s3 cp terraform.tfstate.restored s3://${BUCKET}/${KEY}"
echo ""
echo "After restoring, reinitialize Terraform:"
echo "cd automated/terraform/environments/prod-aws && terraform init -reconfigure"
```

---

## Troubleshooting

### ECS Tasks Not Starting

**Symptoms:** Tasks stay in PENDING state or continuously restart.

```bash
#!/bin/bash
# Diagnose ECS task failures

CLUSTER="mw-prod-cluster"
SERVICE="mw-prod-liberty"

echo "=== ECS Task Diagnostics ==="

# Check stopped tasks
echo "Recently stopped tasks:"
STOPPED_TASKS=$(aws ecs list-tasks \
    --cluster "${CLUSTER}" \
    --service-name "${SERVICE}" \
    --desired-status STOPPED \
    --query 'taskArns[0:3]' \
    --output text)

if [ -n "${STOPPED_TASKS}" ] && [ "${STOPPED_TASKS}" != "None" ]; then
    for task in ${STOPPED_TASKS}; do
        echo "---"
        aws ecs describe-tasks \
            --cluster "${CLUSTER}" \
            --tasks "${task}" \
            --query 'tasks[0].{
                StopCode: stopCode,
                StoppedReason: stoppedReason,
                ContainerReason: containers[0].reason
            }' \
            --output table
    done
fi

echo ""
echo "Service events:"
aws ecs describe-services \
    --cluster "${CLUSTER}" \
    --services "${SERVICE}" \
    --query 'services[0].events[0:5].{Time:createdAt,Message:message}' \
    --output table

echo ""
echo "Recent CloudWatch errors:"
aws logs filter-log-events \
    --log-group-name "/ecs/mw-prod-liberty" \
    --filter-pattern "ERROR" \
    --start-time $(date -d '30 minutes ago' +%s000) \
    --limit 10 \
    --query 'events[*].message' \
    --output text
```

**Common causes and solutions:**

| Cause | Solution |
|-------|----------|
| ECR image pull failure | Verify ECR permissions, check image exists |
| Secrets Manager access denied | Check ECS task execution role permissions |
| Database connection timeout | Verify security groups, check DB status |
| Health check failure | Review application logs, check health endpoint |
| Resource constraints | Increase CPU/memory in task definition |

### Database Connection Issues

**Symptoms:** Application reports database connection errors.

```bash
#!/bin/bash
# Diagnose database connectivity

echo "=== Database Connectivity Diagnostics ==="

# Check RDS status
echo "RDS Status:"
aws rds describe-db-instances \
    --db-instance-identifier mw-prod-postgres \
    --query 'DBInstances[0].{
        Status: DBInstanceStatus,
        Endpoint: Endpoint.Address,
        Port: Endpoint.Port,
        AvailabilityZone: AvailabilityZone
    }' \
    --output table

# Check security group rules
echo ""
echo "Database security group ingress rules:"
SG_ID=$(aws rds describe-db-instances \
    --db-instance-identifier mw-prod-postgres \
    --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
    --output text)

aws ec2 describe-security-groups \
    --group-ids "${SG_ID}" \
    --query 'SecurityGroups[0].IpPermissions[*].{
        Port: FromPort,
        Protocol: IpProtocol,
        Source: UserIdGroupPairs[0].GroupId
    }' \
    --output table

# Check Secrets Manager
echo ""
echo "Database credentials secret:"
aws secretsmanager describe-secret \
    --secret-id "mw-prod/database/credentials" \
    --query '{
        Name: Name,
        LastChanged: LastChangedDate,
        VersionIds: VersionIdsToStages
    }' \
    --output table
```

### ALB Target Unhealthy

**Symptoms:** 503 errors, targets showing unhealthy in target group.

```bash
#!/bin/bash
# Diagnose ALB target health issues

echo "=== ALB Target Health Diagnostics ==="

# Get target group ARN
TG_ARN=$(aws elbv2 describe-target-groups \
    --names mw-prod-liberty-ecs-tg \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text 2>/dev/null)

if [ -z "${TG_ARN}" ] || [ "${TG_ARN}" == "None" ]; then
    TG_ARN=$(aws elbv2 describe-target-groups \
        --names mw-prod-liberty-tg \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text)
fi

echo "Target Group: ${TG_ARN}"
echo ""

# Get target health details
aws elbv2 describe-target-health \
    --target-group-arn "${TG_ARN}" \
    --query 'TargetHealthDescriptions[*].{
        Target: Target.Id,
        Port: Target.Port,
        State: TargetHealth.State,
        Reason: TargetHealth.Reason,
        Description: TargetHealth.Description
    }' \
    --output table

# Get health check config
echo ""
echo "Health Check Configuration:"
aws elbv2 describe-target-groups \
    --target-group-arns "${TG_ARN}" \
    --query 'TargetGroups[0].{
        Path: HealthCheckPath,
        Port: HealthCheckPort,
        Protocol: HealthCheckProtocol,
        Interval: HealthCheckIntervalSeconds,
        Timeout: HealthCheckTimeoutSeconds,
        HealthyThreshold: HealthyThresholdCount,
        UnhealthyThreshold: UnhealthyThresholdCount
    }' \
    --output table
```

### Terraform State Issues

**Symptoms:** Terraform shows unexpected changes or state conflicts.

```bash
#!/bin/bash
# Diagnose Terraform state issues

cd /home/justin/Projects/middleware-automation-platform/automated/terraform/environments/prod-aws

echo "=== Terraform State Diagnostics ==="

# Check for state lock
echo "Checking DynamoDB lock table..."
aws dynamodb scan \
    --table-name middleware-platform-terraform-locks \
    --query 'Items[*].{LockID:LockID.S,Info:Info.S}' \
    --output table 2>/dev/null || echo "No active locks or table not found"

# Verify S3 state accessibility
echo ""
echo "Checking S3 state file..."
aws s3api head-object \
    --bucket middleware-platform-terraform-state \
    --key prod-aws/terraform.tfstate \
    --query '{
        LastModified: LastModified,
        ContentLength: ContentLength,
        VersionId: VersionId
    }' \
    --output table

# Run terraform refresh
echo ""
echo "Running terraform refresh (dry-run)..."
terraform plan -refresh-only 2>&1 | head -50
```

---

## Terraform Resource Reference

### Key Resources by Component

| Component | Terraform Resource | File |
|-----------|-------------------|------|
| ECS Cluster | `aws_ecs_cluster.main` | `ecs.tf` |
| ECS Service | `aws_ecs_service.liberty` | `ecs.tf` |
| ECS Task Definition | `aws_ecs_task_definition.liberty` | `ecs.tf` |
| RDS PostgreSQL | `aws_db_instance.main` | `database.tf` |
| ElastiCache Redis | `aws_elasticache_replication_group.main` | `database.tf` |
| ALB | `aws_lb.main` | `loadbalancer.tf` |
| Target Group (ECS) | `aws_lb_target_group.liberty_ecs` | `ecs.tf` |
| Target Group (EC2) | `aws_lb_target_group.liberty` | `loadbalancer.tf` |
| ECR Repository | `aws_ecr_repository.liberty` | `ecr.tf` |
| VPC | `module.networking` | `networking.tf` |
| DB Credentials | `aws_secretsmanager_secret.db_credentials` | `database.tf` |

### Configuration Variables

| Variable | Default | Description | File |
|----------|---------|-------------|------|
| `ecs_enabled` | `true` | Enable ECS Fargate | `variables.tf` |
| `ecs_min_capacity` | `2` | Minimum ECS tasks | `variables.tf` |
| `ecs_max_capacity` | `6` | Maximum ECS tasks | `variables.tf` |
| `db_backup_retention_period` | `7` | RDS backup retention (days) | `variables.tf` |
| `cache_multi_az` | `true` | ElastiCache Multi-AZ | `variables.tf` |
| `enable_blue_green` | `false` | Blue-Green deployments | `variables.tf` |

### Important Outputs

```bash
# Get all Terraform outputs
cd /home/justin/Projects/middleware-automation-platform/automated/terraform/environments/prod-aws
terraform output

# Key outputs for DR
terraform output alb_dns_name
terraform output db_endpoint
terraform output redis_endpoint
terraform output ecr_repository_url
terraform output ecs_cluster_name
terraform output ecs_service_name
```

---

## Related Documentation

- [Disaster Recovery Guide](DISASTER_RECOVERY.md) - Comprehensive DR procedures
- [Credential Setup Guide](CREDENTIAL_SETUP.md) - Initial credential configuration
- [End-to-End Testing](END_TO_END_TESTING.md) - Comprehensive testing procedures
- [AWS Deployment Guide](AWS_DEPLOYMENT.md) - AWS deployment instructions
- [CI/CD Guide](CI_CD_GUIDE.md) - Pipeline configuration

---

## DR Test Results Template

Document test results using this template:

```markdown
# DR Test Results - YYYY-MM-DD

## Test Summary
- **Test Type:** [Monthly/Quarterly/Annual]
- **Date:** YYYY-MM-DD
- **Duration:** X hours
- **Performed By:** [Name]
- **Environment:** Production

## Tests Conducted

### ECS Service Failover
- **Status:** PASS/FAIL
- **Recovery Time:** X minutes
- **Issues:** None / [Description]

### Database Failover
- **Status:** PASS/FAIL
- **Recovery Time:** X minutes
- **Data Loss:** None / X minutes
- **Issues:** None / [Description]

### ElastiCache Failover
- **Status:** PASS/FAIL
- **Recovery Time:** X minutes
- **Issues:** None / [Description]

## RTO/RPO Validation
| Component | Target RTO | Actual RTO | Target RPO | Actual RPO |
|-----------|------------|------------|------------|------------|
| ECS | 15 min | X min | N/A | N/A |
| RDS | 2 min | X min | 5 min | X min |
| ElastiCache | 5 min | X min | 1 day | X min |

## Action Items
1. [Action item from test]
2. [Action item from test]

## Next Test Date
YYYY-MM-DD
```

Store results in: `docs/dr-test-results/YYYY-MM-DD.md`

---

## Revision History

| Date | Author | Changes |
|------|--------|---------|
| 2026-01-05 | [Author] | Initial DR Testing Runbook creation |
