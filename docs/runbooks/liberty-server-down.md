# Liberty Server Down Runbook

## Alert Overview

| Alert Name | Severity | Threshold | Duration |
|------------|----------|-----------|----------|
| `LibertyServerDown` | Critical | `up{job="liberty"} == 0` | 1 minute |
| `ECSLibertyTaskDown` | Critical | `up{job="ecs-liberty"} == 0` | 1 minute |
| `ECSLibertyNoTasks` | Critical | No running ECS tasks detected | 2 minutes |

### Alert Descriptions

- **LibertyServerDown**: A Liberty server instance (Kubernetes pod or EC2) is not responding to health checks. Prometheus cannot scrape the `/metrics` endpoint.

- **ECSLibertyTaskDown**: A specific ECS Fargate task running Liberty is down or unresponsive. The task may be in a failed state, restarting, or experiencing network issues.

- **ECSLibertyNoTasks**: No Liberty tasks are running in the ECS cluster. This indicates a complete service outage - either all tasks have crashed, the service was scaled to zero, or there is a deployment failure.

---

## Impact Assessment

### Service Impact

| Scenario | User Impact | Business Impact |
|----------|-------------|-----------------|
| Single task/pod down | Minimal - load balancer routes around failed instance | None if replicas > 1 |
| Multiple tasks/pods down | Degraded performance, increased latency | Potential SLA breach |
| All tasks/pods down | **Complete service outage** | Revenue loss, customer impact |

### Affected Components

- **Application**: Sample application at `/` endpoint
- **Health Endpoints**: `/health/ready`, `/health/live`, `/health/started`
- **Metrics Endpoint**: `/metrics` (Prometheus scraping)
- **Load Balancer**: `mw-prod-alb` (ALB routes traffic to healthy instances)

---

## Investigation Steps

### Step 1: Verify Alert Status

Check current alerting state in Prometheus or Alertmanager:

```bash
# View active alerts (if Prometheus is accessible)
curl -s http://prometheus:9090/api/v1/alerts | jq '.data.alerts[] | select(.labels.alertname | contains("Liberty"))'
```

### Step 2: Determine Environment

Identify whether the issue is in Kubernetes or AWS ECS:

- **Kubernetes**: Alerts with `job="liberty"` and `namespace` labels
- **AWS ECS**: Alerts with `job="ecs-liberty"` and `ecs_cluster` labels

---

## Kubernetes Investigation

### Check Pod Status

```bash
# List all Liberty pods
kubectl get pods -n liberty -l app=liberty -o wide

# Check pod events for errors
kubectl describe pods -n liberty -l app=liberty

# Check for pending pods (scheduling issues)
kubectl get pods -n liberty -l app=liberty --field-selector=status.phase=Pending
```

### Check Pod Logs

```bash
# View logs from all Liberty pods
kubectl logs -n liberty -l app=liberty --tail=100

# View logs from a specific pod
kubectl logs -n liberty <pod-name> --tail=200

# View previous container logs (if restarted)
kubectl logs -n liberty <pod-name> --previous
```

### Check Resource Usage

```bash
# View current resource usage
kubectl top pods -n liberty -l app=liberty

# Check resource requests and limits
kubectl describe pods -n liberty -l app=liberty | grep -A5 "Limits:" | head -20
```

### Check Events

```bash
# View recent events in liberty namespace
kubectl get events -n liberty --sort-by='.lastTimestamp' | tail -30

# Filter for warning/error events
kubectl get events -n liberty --field-selector=type!=Normal
```

### Check Deployment Status

```bash
# View deployment status
kubectl get deployment liberty-app -n liberty -o wide

# View deployment conditions
kubectl describe deployment liberty-app -n liberty | grep -A10 "Conditions:"

# View rollout status
kubectl rollout status deployment/liberty-app -n liberty
```

### Check HPA Status (Auto-Scaling)

```bash
# View HPA status
kubectl get hpa liberty-hpa -n liberty

# Check HPA events
kubectl describe hpa liberty-hpa -n liberty
```

---

## AWS ECS Investigation

### Check ECS Service Status

```bash
# View service status
aws ecs describe-services \
  --cluster mw-prod-cluster \
  --services mw-prod-liberty \
  --query 'services[0].{status:status,runningCount:runningCount,desiredCount:desiredCount,deployments:deployments[*].{status:status,runningCount:runningCount,failedTasks:failedTasks}}'

# View service events (last 10)
aws ecs describe-services \
  --cluster mw-prod-cluster \
  --services mw-prod-liberty \
  --query 'services[0].events[:10]' \
  --output table
```

### Check Running Tasks

```bash
# List all tasks for the service
aws ecs list-tasks \
  --cluster mw-prod-cluster \
  --service-name mw-prod-liberty

# Get detailed task information
aws ecs describe-tasks \
  --cluster mw-prod-cluster \
  --tasks $(aws ecs list-tasks --cluster mw-prod-cluster --service-name mw-prod-liberty --query 'taskArns[]' --output text)
```

### Check Stopped Tasks (Recent Failures)

```bash
# List recently stopped tasks
aws ecs list-tasks \
  --cluster mw-prod-cluster \
  --service-name mw-prod-liberty \
  --desired-status STOPPED

# Get details on stopped tasks (shows stop reason)
STOPPED_TASKS=$(aws ecs list-tasks --cluster mw-prod-cluster --service-name mw-prod-liberty --desired-status STOPPED --query 'taskArns[]' --output text)
if [ -n "$STOPPED_TASKS" ]; then
  aws ecs describe-tasks \
    --cluster mw-prod-cluster \
    --tasks $STOPPED_TASKS \
    --query 'tasks[*].{taskArn:taskArn,lastStatus:lastStatus,stoppedReason:stoppedReason,stopCode:stopCode,containers:containers[*].{name:name,exitCode:exitCode,reason:reason}}'
fi
```

### Check CloudWatch Logs

```bash
# View recent Liberty container logs
aws logs tail /ecs/mw-prod-liberty --since 30m --follow

# Search for errors in logs
aws logs filter-log-events \
  --log-group-name /ecs/mw-prod-liberty \
  --start-time $(date -d '1 hour ago' +%s)000 \
  --filter-pattern "ERROR"
```

### Check Target Group Health

```bash
# Get target group ARN
TG_ARN=$(aws elbv2 describe-target-groups \
  --names mw-prod-liberty-ecs-tg \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

# Check target health
aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN
```

### Check ECS Task Definition

```bash
# View current task definition
aws ecs describe-task-definition \
  --task-definition mw-prod-liberty \
  --query 'taskDefinition.{cpu:cpu,memory:memory,containerDefinitions:containerDefinitions[*].{name:name,image:image,cpu:cpu,memory:memory}}'
```

---

## Common Causes and Resolutions

### 1. Out of Memory (OOM) Kill

**Symptoms:**
- Container exits with code 137 (SIGKILL)
- `stoppedReason: "OutOfMemory"` in ECS
- `OOMKilled: true` in Kubernetes pod status

**Investigation:**
```bash
# Kubernetes: Check OOM status
kubectl get pods -n liberty -l app=liberty -o jsonpath='{.items[*].status.containerStatuses[*].lastState.terminated.reason}'

# ECS: Check for OOM in stopped tasks
aws ecs describe-tasks --cluster mw-prod-cluster --tasks $STOPPED_TASKS --query 'tasks[*].stopCode'
```

**Resolution:**
```bash
# Kubernetes: Increase memory limits
kubectl patch deployment liberty-app -n liberty -p '{"spec":{"template":{"spec":{"containers":[{"name":"liberty","resources":{"limits":{"memory":"3Gi"}}}]}}}}'

# ECS: Update task definition with more memory
# Edit terraform.tfvars and set ecs_task_memory to higher value (e.g., 2048 -> 4096)
# Then apply changes:
cd /home/justin/Projects/middleware-automation-platform/automated/terraform/environments/prod-aws
terraform apply -var="ecs_task_memory=4096"

# Force new deployment
aws ecs update-service --cluster mw-prod-cluster --service mw-prod-liberty --force-new-deployment
```

### 2. Health Check Failures

**Symptoms:**
- Task starts but is terminated after health check timeout
- `stoppedReason: "Task failed ELB health checks"` in ECS
- Pod shows as `Running` but `READY: 0/1` in Kubernetes

**Investigation:**
```bash
# Test health endpoint directly (from within cluster/VPC)
curl -v http://<pod-ip>:9080/health/ready
curl -v http://<pod-ip>:9080/health/live

# Kubernetes: Check probe configuration
kubectl get deployment liberty-app -n liberty -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}'

# ECS: Check task health check configuration
aws ecs describe-task-definition --task-definition mw-prod-liberty --query 'taskDefinition.containerDefinitions[0].healthCheck'
```

**Resolution:**

If application needs more startup time:
```bash
# Kubernetes: Increase startup probe failure threshold
kubectl patch deployment liberty-app -n liberty -p '{"spec":{"template":{"spec":{"containers":[{"name":"liberty","startupProbe":{"failureThreshold":60}}]}}}}'

# ECS: Increase health check start period in task definition
# Update terraform variable and apply
```

If application is crashing:
- Check application logs for startup errors
- Verify database connectivity
- Check for missing environment variables or secrets

### 3. Image Pull Failures

**Symptoms:**
- `ImagePullBackOff` or `ErrImagePull` in Kubernetes
- `CannotPullContainerError` in ECS

**Investigation:**
```bash
# Kubernetes: Check image pull status
kubectl describe pod -n liberty -l app=liberty | grep -A5 "Events:"

# ECS: Check for pull errors in service events
aws ecs describe-services --cluster mw-prod-cluster --services mw-prod-liberty --query 'services[0].events[:5]'

# Verify ECR image exists
aws ecr describe-images --repository-name mw-prod-liberty --query 'imageDetails[?imageTags[?contains(@,`latest`)]]'
```

**Resolution:**
```bash
# Verify ECR repository access
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com

# Rebuild and push image
cd /home/justin/Projects/middleware-automation-platform
podman build -t liberty-app:1.0.0 -f containers/liberty/Containerfile .
# Tag and push (get full commands from terraform output)
terraform -chdir=automated/terraform/environments/prod-aws output ecr_push_commands

# Force new deployment after pushing
aws ecs update-service --cluster mw-prod-cluster --service mw-prod-liberty --force-new-deployment
```

### 4. Resource Limits Exceeded

**Symptoms:**
- Pods stuck in `Pending` state (Kubernetes)
- Tasks fail to place with `RESOURCE:*` error (ECS)

**Investigation:**
```bash
# Kubernetes: Check node resources
kubectl describe nodes | grep -A10 "Allocated resources:"
kubectl get pods -n liberty -l app=liberty -o wide

# Kubernetes: Check resource quota
kubectl describe resourcequota -n liberty

# ECS: Check cluster capacity
aws ecs describe-clusters --clusters mw-prod-cluster --include STATISTICS
```

**Resolution:**
```bash
# Kubernetes: Add nodes or reduce resource requests
# Check if requests can be lowered while maintaining stability

# ECS Fargate: No capacity limits - check task CPU/memory configuration
# Reduce task size if hitting account service quotas
aws service-quotas get-service-quota --service-code fargate --quota-code L-3032A538
```

### 5. Database Connection Failure

**Symptoms:**
- Application starts but health checks fail after startup
- Connection timeout errors in logs
- `connectionpool_destroy_total` rate increasing

**Investigation:**
```bash
# Check RDS status
aws rds describe-db-instances --query 'DBInstances[*].{id:DBInstanceIdentifier,status:DBInstanceStatus,endpoint:Endpoint.Address}'

# Test database connectivity from within ECS task
aws ecs execute-command \
  --cluster mw-prod-cluster \
  --task <task-id> \
  --container liberty \
  --interactive \
  --command "/bin/sh -c 'nc -zv $DB_HOST 5432'"
```

**Resolution:**
- Verify database is running and accepting connections
- Check security group rules allow ECS to access RDS
- Verify database credentials in Secrets Manager

### 6. Secret/Configuration Issues

**Symptoms:**
- Container fails to start with environment variable errors
- Secrets Manager access denied errors in logs

**Investigation:**
```bash
# ECS: Check task execution role has Secrets Manager access
aws iam get-role-policy --role-name mw-prod-ecs-execution-role --policy-name secrets-access

# Verify secret exists
aws secretsmanager describe-secret --secret-id mw-prod-db-credentials

# Kubernetes: Check secrets exist
kubectl get secrets -n liberty
```

---

## Immediate Mitigation

### Force New ECS Deployment

```bash
aws ecs update-service \
  --cluster mw-prod-cluster \
  --service mw-prod-liberty \
  --force-new-deployment
```

### Scale ECS Service

```bash
# Scale up
aws ecs update-service \
  --cluster mw-prod-cluster \
  --service mw-prod-liberty \
  --desired-count 4

# Scale down (if needed)
aws ecs update-service \
  --cluster mw-prod-cluster \
  --service mw-prod-liberty \
  --desired-count 2
```

### Kubernetes: Restart Deployment

```bash
kubectl rollout restart deployment/liberty-app -n liberty
```

### Kubernetes: Scale Deployment

```bash
# Scale up
kubectl scale deployment liberty-app -n liberty --replicas=5

# Scale down
kubectl scale deployment liberty-app -n liberty --replicas=3
```

### Rollback to Previous Version (Kubernetes)

```bash
# View rollout history
kubectl rollout history deployment/liberty-app -n liberty

# Rollback to previous revision
kubectl rollout undo deployment/liberty-app -n liberty

# Rollback to specific revision
kubectl rollout undo deployment/liberty-app -n liberty --to-revision=2
```

### Switch Traffic to EC2 (AWS - If ECS Failing)

If EC2 instances are running as backup, route traffic to EC2:

```bash
# Modify ALB listener default action to point to EC2 target group
# This requires Terraform change or manual ALB configuration

# Test EC2 target directly
curl -H "X-Target: ec2" http://<alb-dns-name>/health/ready
```

---

## Escalation Criteria

Escalate to the on-call engineer or team lead if:

| Condition | Escalation Level |
|-----------|------------------|
| Single pod/task down > 5 minutes | Inform team channel |
| Multiple pods/tasks down > 10 minutes | Page on-call engineer |
| Complete service outage (all tasks down) | **Immediate escalation** |
| Repeated failures after 2 restart attempts | Page senior engineer |
| Root cause involves infrastructure (AWS, network) | Engage platform team |
| Database-related issues | Engage DBA team |

### Escalation Contacts

- **On-Call Engineer**: Check PagerDuty/OpsGenie rotation
- **Platform Team**: For infrastructure issues (VPC, ALB, security groups)
- **DBA Team**: For database connectivity or performance issues
- **Security Team**: For Secrets Manager or IAM issues

---

## Post-Incident Steps

### 1. Verify Recovery

```bash
# ECS: Confirm all tasks healthy
aws ecs describe-services --cluster mw-prod-cluster --services mw-prod-liberty --query 'services[0].{running:runningCount,desired:desiredCount}'

# Kubernetes: Confirm all pods ready
kubectl get pods -n liberty -l app=liberty

# Test application health
curl http://<alb-dns-name>/health/ready
curl http://<alb-dns-name>/health/live
```

### 2. Verify Metrics Collection Resumed

```bash
# Check Prometheus target status
curl -s http://prometheus:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="liberty" or .labels.job=="ecs-liberty") | {instance:.labels.instance,health:.health}'
```

### 3. Document the Incident

Create an incident report including:

- **Timeline**: When alert fired, when acknowledged, when resolved
- **Impact**: Duration of outage, affected users/services
- **Root Cause**: What caused the failure
- **Resolution**: Steps taken to resolve
- **Prevention**: How to prevent recurrence

### 4. Update Monitoring (If Needed)

- Adjust alert thresholds if too sensitive/not sensitive enough
- Add new alerts if failure mode was not detected
- Update dashboards to surface relevant metrics

### 5. Review and Improve

- Schedule a post-incident review (blameless postmortem)
- Create action items for infrastructure improvements
- Update this runbook with any new findings

---

## Related Runbooks

| Runbook | Description |
|---------|-------------|
| `liberty-high-heap-usage.md` | JVM heap memory issues |
| `liberty-database-connection-failure.md` | Database connectivity problems |
| `liberty-connection-pool-exhausted.md` | Connection pool saturation |

---

## References

- [Open Liberty Health Check Documentation](https://openliberty.io/docs/latest/health-check-microservices.html)
- [ECS Troubleshooting Guide](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/troubleshooting.html)
- [Kubernetes Pod Debugging](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/)
- Project Documentation: `docs/END_TO_END_TESTING.md`
