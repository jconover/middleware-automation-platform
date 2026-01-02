# Liberty High Error Rate Runbook

## Overview

This runbook covers investigation and resolution procedures for Liberty application 5xx error rate alerts.

### Alerts Covered

| Alert Name | Severity | Threshold | Duration |
|------------|----------|-----------|----------|
| LibertyHighErrorRate | Warning | >5% 5xx errors | 5 minutes |
| LibertyCriticalErrorRate | Critical | >10% 5xx errors | 2 minutes |
| ECSLibertyHighErrorRate | Warning | >5% 5xx errors (ECS) | 5 minutes |

### Alert Definitions

**LibertyHighErrorRate / LibertyCriticalErrorRate** (Kubernetes):
```promql
sum(rate(servlet_request_total{job="liberty", mp_scope="base", status=~"5.."}[5m]))
  / sum(rate(servlet_request_total{job="liberty", mp_scope="base"}[5m])) > 0.05
```

**ECSLibertyHighErrorRate** (AWS ECS):
```promql
sum(rate(servlet_request_total{job="ecs-liberty", status=~"5.."}[5m]))
  / sum(rate(servlet_request_total{job="ecs-liberty"}[5m])) > 0.05
```

---

## Impact Assessment

### User Impact
- **Warning (5-10%)**: Degraded user experience; approximately 1 in 20 requests failing
- **Critical (>10%)**: Significant service degradation; 1 in 10 or more requests failing

### Business Impact
- Failed transactions and potential data inconsistency
- Customer-facing errors leading to support tickets
- SLA violations if sustained

### Urgency Matrix

| Error Rate | Business Hours | Off-Hours |
|------------|----------------|-----------|
| 5-10% | Investigate within 15 minutes | Investigate within 30 minutes |
| >10% | Immediate response required | Page on-call engineer |

---

## Investigation Steps

### Step 1: Verify Alert and Current State

#### Kubernetes (Local Development)

```bash
# Check current error rate in Prometheus
kubectl exec -n monitoring prometheus-0 -- promtool query instant \
  'sum(rate(servlet_request_total{job="liberty", mp_scope="base", status=~"5.."}[5m])) / sum(rate(servlet_request_total{job="liberty", mp_scope="base"}[5m]))'

# Check pod status
kubectl get pods -l app=liberty -o wide

# Check recent events
kubectl get events --sort-by='.lastTimestamp' | grep -i liberty | tail -20
```

#### AWS ECS

```bash
# Check ECS service status
aws ecs describe-services \
  --cluster mw-prod-cluster \
  --services mw-prod-liberty \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount,Pending:pendingCount}'

# Check task health
aws ecs list-tasks --cluster mw-prod-cluster --service-name mw-prod-liberty | \
  xargs -I {} aws ecs describe-tasks --cluster mw-prod-cluster --tasks {}

# Check ALB target health
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
    --names mw-prod-liberty-ecs-tg \
    --query 'TargetGroups[0].TargetGroupArn' --output text)
```

### Step 2: Check Application Logs

#### Kubernetes

```bash
# View recent logs from all Liberty pods
kubectl logs -l app=liberty --since=10m --all-containers

# Stream logs with error filtering (JSON format)
kubectl logs -l app=liberty -f | jq 'select(.loglevel == "ERROR" or .loglevel == "SEVERE")'

# Check specific pod logs
kubectl logs liberty-app-<pod-id> --since=10m

# View previous container logs (if restarted)
kubectl logs liberty-app-<pod-id> --previous
```

#### AWS ECS (CloudWatch Logs)

```bash
# Get recent error logs from ECS tasks
aws logs filter-log-events \
  --log-group-name /ecs/mw-prod-liberty \
  --filter-pattern "ERROR" \
  --start-time $(date -d '10 minutes ago' +%s000) \
  --limit 50

# Stream live logs
aws logs tail /ecs/mw-prod-liberty --follow --filter-pattern "ERROR"

# Get all recent logs from a specific task
aws logs get-log-events \
  --log-group-name /ecs/mw-prod-liberty \
  --log-stream-name "liberty/<task-id>" \
  --start-time $(date -d '10 minutes ago' +%s000)
```

#### AWS EC2 Liberty Instances

```bash
# SSH to Liberty server and check logs
ssh -i ~/.ssh/ansible_ed25519 ubuntu@<liberty-ip>

# View Liberty messages log
sudo tail -100 /opt/ol/wlp/output/defaultServer/logs/messages.log

# Search for errors
sudo grep -i "error\|exception\|severe" /opt/ol/wlp/output/defaultServer/logs/messages.log | tail -50
```

### Step 3: Check ALB Access Logs

#### AWS (S3 Access Logs)

```bash
# List recent ALB log files
aws s3 ls s3://mw-prod-alb-logs-<account-id>/alb/ --recursive | tail -20

# Download and analyze recent logs
aws s3 cp s3://mw-prod-alb-logs-<account-id>/alb/$(date +%Y/%m/%d)/ /tmp/alb-logs/ --recursive

# Parse for 5xx errors
zcat /tmp/alb-logs/*.gz | awk '$9 ~ /^5/ {print $0}' | head -50

# Count errors by target
zcat /tmp/alb-logs/*.gz | awk '$9 ~ /^5/ {print $5}' | sort | uniq -c | sort -rn
```

### Step 4: Check Downstream Dependencies

#### Database (RDS PostgreSQL)

```bash
# Check RDS instance status
aws rds describe-db-instances \
  --db-instance-identifier mw-prod-postgres \
  --query 'DBInstances[0].{Status:DBInstanceStatus,CPU:PerformanceInsightsEnabled}'

# Check connection count (via CloudWatch)
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=mw-prod-postgres \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Average

# Check CPU utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=mw-prod-postgres \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Average
```

#### Cache (ElastiCache Redis)

```bash
# Check Redis cluster status
aws elasticache describe-cache-clusters \
  --cache-cluster-id mw-prod-redis \
  --show-cache-node-info

# Check cache hit ratio
aws cloudwatch get-metric-statistics \
  --namespace AWS/ElastiCache \
  --metric-name CacheHitRate \
  --dimensions Name=CacheClusterId,Value=mw-prod-redis \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Average
```

#### Liberty Connection Pool Metrics

Check Prometheus for connection pool issues:

```promql
# Free connections (should be > 0)
connectionpool_freeConnections{job="liberty", mp_scope="vendor"}

# Queued requests (should be 0 or low)
connectionpool_queuedRequests{job="liberty", mp_scope="vendor"}

# Connection wait time
rate(connectionpool_waitTime_total_seconds{job="liberty", mp_scope="vendor"}[5m])
```

---

## Common Causes and Resolution

### Cause 1: Database Issues

#### Symptoms
- High connection pool wait times
- Zero free database connections
- Database CPU/memory exhaustion
- Slow query logs showing long-running queries

#### Investigation

```bash
# Check Liberty connection pool metrics in Prometheus
# Query: connectionpool_freeConnections{mp_scope="vendor"} == 0

# Check RDS Performance Insights for slow queries
aws pi get-resource-metrics \
  --service-type RDS \
  --identifier db-<instance-id> \
  --metric-queries '[{"Metric":"db.load.avg"}]' \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ)
```

#### Resolution

1. **Immediate**: Restart affected Liberty pods/tasks to reset connection pools
   ```bash
   # Kubernetes
   kubectl rollout restart deployment/liberty-app

   # ECS
   aws ecs update-service --cluster mw-prod-cluster --service mw-prod-liberty --force-new-deployment
   ```

2. **Short-term**: Increase connection pool size in `server.xml`:
   ```xml
   <connectionManager maxPoolSize="50" minPoolSize="10"/>
   ```

3. **Long-term**: Optimize slow queries, add database indexes, consider read replicas

### Cause 2: External Service Failures

#### Symptoms
- Timeout errors in application logs
- Specific API endpoints failing
- Network connectivity issues

#### Investigation

```bash
# Check for timeout patterns in logs
kubectl logs -l app=liberty --since=10m | grep -i "timeout\|connection refused\|unreachable"

# Test external service connectivity from pod
kubectl exec -it liberty-app-<pod-id> -- curl -v https://external-service.example.com/health
```

#### Resolution

1. **Immediate**: Implement circuit breaker pattern if not present
2. **Short-term**: Increase timeout values for affected services
3. **Long-term**: Add retry logic with exponential backoff

### Cause 3: Application Bugs (Code Errors)

#### Symptoms
- NullPointerException or similar errors in logs
- Errors occurring on specific endpoints
- Errors started after a deployment

#### Investigation

```bash
# Check for exception patterns
kubectl logs -l app=liberty --since=30m | grep -i "exception\|error" | sort | uniq -c | sort -rn | head -20

# Check which endpoints are failing
# Parse ALB logs for 5xx by URL path
zcat /tmp/alb-logs/*.gz | awk '$9 ~ /^5/ {print $13}' | sort | uniq -c | sort -rn | head -20
```

#### Resolution

1. **Immediate**: If caused by recent deployment, rollback (see Rollback Procedures below)
2. **Short-term**: Deploy hotfix if root cause identified
3. **Long-term**: Improve test coverage, add integration tests

### Cause 4: Resource Exhaustion

#### Symptoms
- High heap usage (>85%)
- High GC time
- Thread pool exhaustion
- OOM kills

#### Investigation

```bash
# Check JVM metrics in Prometheus
# Heap usage
memory_usedHeap_bytes{job="liberty", mp_scope="base"} / memory_maxHeap_bytes{job="liberty", mp_scope="base"}

# GC time
rate(gc_time_total_seconds{job="liberty", mp_scope="base"}[5m])

# Kubernetes
kubectl top pods -l app=liberty

# ECS
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name MemoryUtilization \
  --dimensions Name=ClusterName,Value=mw-prod-cluster Name=ServiceName,Value=mw-prod-liberty \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Average
```

#### Resolution

1. **Immediate**: Scale up replicas to distribute load
   ```bash
   # Kubernetes
   kubectl scale deployment/liberty-app --replicas=5

   # ECS
   aws ecs update-service --cluster mw-prod-cluster --service mw-prod-liberty --desired-count 4
   ```

2. **Short-term**: Increase resource limits
   ```yaml
   # Kubernetes: Update deployment
   resources:
     limits:
       memory: "3Gi"
       cpu: "3000m"
   ```

3. **Long-term**: Profile application for memory leaks, optimize code

### Cause 5: Traffic Spike

#### Symptoms
- Sudden increase in request rate
- All pods/tasks showing high load
- Auto-scaling not keeping pace

#### Investigation

```bash
# Check request rate
# Prometheus query
rate(servlet_request_total{job="liberty", mp_scope="base"}[5m])

# Check HPA status (Kubernetes)
kubectl get hpa liberty-hpa

# Check ECS scaling activities
aws application-autoscaling describe-scaling-activities \
  --service-namespace ecs \
  --resource-id service/mw-prod-cluster/mw-prod-liberty \
  --max-results 10
```

#### Resolution

1. **Immediate**: Manually scale up
2. **Short-term**: Adjust auto-scaling thresholds
3. **Long-term**: Implement rate limiting, optimize application performance

---

## Rollback Procedures

### If Caused by Recent Deployment

#### Kubernetes Rollback

```bash
# Check deployment history
kubectl rollout history deployment/liberty-app

# Rollback to previous revision
kubectl rollout undo deployment/liberty-app

# Rollback to specific revision
kubectl rollout undo deployment/liberty-app --to-revision=<revision-number>

# Verify rollback
kubectl rollout status deployment/liberty-app
kubectl get pods -l app=liberty
```

#### ECS Rollback

```bash
# List recent task definitions
aws ecs list-task-definitions --family-prefix mw-prod-liberty --sort DESC --max-items 5

# Update service to previous task definition
aws ecs update-service \
  --cluster mw-prod-cluster \
  --service mw-prod-liberty \
  --task-definition mw-prod-liberty:<previous-revision>

# Monitor deployment
aws ecs describe-services \
  --cluster mw-prod-cluster \
  --services mw-prod-liberty \
  --query 'services[0].deployments'
```

#### ECR Image Rollback

```bash
# List image tags
aws ecr describe-images \
  --repository-name mw-prod-liberty \
  --query 'imageDetails[*].{Tag:imageTags[0],Pushed:imagePushedAt}' \
  --output table

# Tag previous image as latest
aws ecr batch-get-image \
  --repository-name mw-prod-liberty \
  --image-ids imageTag=<previous-tag> \
  --query 'images[0].imageManifest' --output text | \
aws ecr put-image \
  --repository-name mw-prod-liberty \
  --image-tag latest \
  --image-manifest -

# Force new deployment
aws ecs update-service \
  --cluster mw-prod-cluster \
  --service mw-prod-liberty \
  --force-new-deployment
```

#### Jenkins Pipeline Rollback

If the deployment was made via Jenkins:

1. Navigate to Jenkins: `http://<jenkins-url>:8080`
2. Go to the Liberty deployment job
3. Click "Build with Parameters"
4. Select the previous successful build artifact or specify previous image tag
5. Execute rollback deployment

---

## Escalation Criteria

### When to Escalate

| Condition | Escalation Action |
|-----------|-------------------|
| Error rate >10% for >15 minutes | Page on-call engineer |
| Error rate >25% | Declare incident, page team lead |
| Rollback unsuccessful | Escalate to platform team |
| Database unreachable | Escalate to DBA team |
| Multiple services affected | Declare major incident |

### Escalation Contacts

| Role | Contact Method |
|------|----------------|
| On-Call Engineer | PagerDuty / AlertManager |
| Platform Team Lead | Slack #platform-oncall |
| DBA Team | Slack #database-support |
| Incident Manager | PagerDuty escalation |

### Information to Include in Escalation

1. **Alert name and current error rate**
2. **Time alert started firing**
3. **Investigation steps already taken**
4. **Suspected root cause (if known)**
5. **Impact assessment (users affected)**
6. **Links to relevant dashboards and logs**

---

## Post-Incident Actions

### Immediate (Within 1 Hour)

- [ ] Verify error rate has returned to normal
- [ ] Confirm all pods/tasks are healthy
- [ ] Document timeline of events
- [ ] Notify stakeholders of resolution

### Short-Term (Within 24 Hours)

- [ ] Complete incident report
- [ ] Identify root cause
- [ ] Create tickets for follow-up work
- [ ] Review monitoring coverage

### Long-Term (Within 1 Week)

- [ ] Conduct post-incident review (blameless postmortem)
- [ ] Implement preventive measures
- [ ] Update runbook if needed
- [ ] Review and adjust alert thresholds if necessary

---

## Related Documentation

- [Prometheus Alert Rules](/kubernetes/base/monitoring/liberty-prometheusrule.yaml)
- [ECS Configuration](/automated/terraform/environments/prod-aws/ecs.tf)
- [Monitoring Configuration](/automated/terraform/environments/prod-aws/monitoring.tf)
- [Disaster Recovery Guide](/docs/DISASTER_RECOVERY.md)
- [Credential Setup](/docs/CREDENTIAL_SETUP.md)

---

## Appendix: Useful Prometheus Queries

### Error Rate by Status Code

```promql
sum by (status) (rate(servlet_request_total{job="liberty", mp_scope="base", status=~"5.."}[5m]))
```

### Error Rate by Pod

```promql
sum by (pod) (rate(servlet_request_total{job="liberty", mp_scope="base", status=~"5.."}[5m]))
  / sum by (pod) (rate(servlet_request_total{job="liberty", mp_scope="base"}[5m]))
```

### Request Latency (95th percentile)

```promql
histogram_quantile(0.95,
  sum(rate(servlet_request_elapsedTime_seconds_bucket{job="liberty", mp_scope="base"}[5m])) by (le)
)
```

### Connection Pool Health

```promql
# Available connections
connectionpool_freeConnections{job="liberty", mp_scope="vendor"}

# Pool utilization
1 - (connectionpool_freeConnections{job="liberty", mp_scope="vendor"}
  / connectionpool_managedConnections{job="liberty", mp_scope="vendor"})
```

### JVM Health

```promql
# Heap utilization
100 * memory_usedHeap_bytes{job="liberty", mp_scope="base"}
  / memory_maxHeap_bytes{job="liberty", mp_scope="base"}

# GC overhead
rate(gc_time_total_seconds{job="liberty", mp_scope="base"}[5m])
```
