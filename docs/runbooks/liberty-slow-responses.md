# Liberty Slow Responses Runbook

## Applicable Alerts

| Alert Name | Environment | Severity |
|------------|-------------|----------|
| LibertyHighLatency | Kubernetes | Warning |
| ECSLibertySlowResponses | AWS ECS | Warning |

## Alert Description

These alerts fire when the 95th percentile (p95) response time for Liberty application servers exceeds 2 seconds over a 5-minute window. This indicates that at least 5% of requests are experiencing response times greater than the acceptable threshold.

**Prometheus Query (Kubernetes):**
```promql
histogram_quantile(0.95,
  sum(rate(servlet_request_elapsedTime_seconds_bucket{job="liberty", mp_scope="base"}[5m])) by (le)
) > 2
```

**Prometheus Query (ECS):**
```promql
histogram_quantile(0.95,
  sum(rate(servlet_request_elapsedTime_seconds_bucket{job="ecs-liberty", mp_scope="base"}[5m])) by (le)
) > 2
```

## Impact Assessment

| Impact Level | Description |
|--------------|-------------|
| User Experience | Degraded - users experience noticeable delays |
| SLA | At risk - response time SLAs may be breached |
| Downstream Systems | Potential timeout cascades to calling services |
| Revenue | Direct impact if slow responses cause user abandonment |

### Severity Classification

- **Warning**: p95 latency 2-5 seconds - investigate during business hours
- **Critical (manual escalation)**: p95 latency > 5 seconds or affecting > 50% of traffic

---

## Investigation Steps

### 1. Identify Which Endpoints Are Slow

Determine if the latency is isolated to specific endpoints or affecting all requests.

#### Kubernetes

```bash
# Query Prometheus for per-endpoint latency
kubectl exec -n monitoring -it \
  $(kubectl get pod -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}') \
  -- promtool query instant http://localhost:9090 \
  'histogram_quantile(0.95, sum(rate(servlet_request_elapsedTime_seconds_bucket{job="liberty"}[5m])) by (le, servlet))'

# Check Liberty access logs for slow requests
kubectl logs -n liberty -l app=liberty --tail=500 | \
  jq -r 'select(.elapsed_ms > 2000) | "\(.timestamp) \(.method) \(.uri) \(.elapsed_ms)ms"'

# Get pod-level breakdown
kubectl top pods -n liberty --sort-by=cpu
```

#### ECS

```bash
# Query CloudWatch Logs Insights for slow requests
aws logs start-query \
  --log-group-name "/ecs/mw-prod-liberty" \
  --start-time $(date -d '15 minutes ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, @message
    | filter @message like /elapsed/
    | sort @timestamp desc
    | limit 100'

# Check ALB target response time metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name TargetResponseTime \
  --dimensions Name=LoadBalancer,Value=app/mw-prod-alb/XXXXXXXXXX \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Average,p95
```

### 2. Check Database Query Performance

Slow database queries are a common cause of high latency.

#### Kubernetes

```bash
# Check connection pool metrics in Prometheus
kubectl exec -n monitoring -it \
  $(kubectl get pod -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}') \
  -- promtool query instant http://localhost:9090 \
  'rate(connectionpool_waitTime_total_seconds{job="liberty"}[5m])'

# Connect to database pod and check slow queries (if PostgreSQL)
kubectl exec -n database -it \
  $(kubectl get pod -n database -l app=postgresql -o jsonpath='{.items[0].metadata.name}') \
  -- psql -U postgres -c "SELECT pid, now() - pg_stat_activity.query_start AS duration, query
     FROM pg_stat_activity
     WHERE state = 'active' AND now() - pg_stat_activity.query_start > interval '1 second'
     ORDER BY duration DESC;"
```

#### ECS / RDS

```bash
# Check RDS Performance Insights
aws pi get-resource-metrics \
  --service-type RDS \
  --identifier db-XXXXXXXXXX \
  --metric-queries '[{"Metric": "db.load.avg"}]' \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period-in-seconds 60

# Check active queries in RDS
aws rds-data execute-statement \
  --resource-arn arn:aws:rds:REGION:ACCOUNT:cluster:CLUSTER_NAME \
  --secret-arn arn:aws:secretsmanager:REGION:ACCOUNT:secret:SECRET_NAME \
  --sql "SELECT pid, now() - query_start AS duration, query FROM pg_stat_activity WHERE state = 'active' ORDER BY duration DESC LIMIT 10"

# Check CloudWatch for connection pool wait time (from Liberty metrics)
# Review in Grafana: Dashboard > ECS Liberty > Connection Pool panel
```

### 3. Check Thread Pool Utilization

Thread pool exhaustion causes requests to queue.

#### Kubernetes

```bash
# Check thread pool utilization via Prometheus
kubectl exec -n monitoring -it \
  $(kubectl get pod -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}') \
  -- promtool query instant http://localhost:9090 \
  'threadpool_activeThreads{job="liberty"} / threadpool_size{job="liberty"}'

# Check directly from Liberty metrics endpoint
kubectl exec -n liberty -it \
  $(kubectl get pod -n liberty -l app=liberty -o jsonpath='{.items[0].metadata.name}') \
  -- curl -s http://localhost:9080/metrics | grep -E "threadpool_(activeThreads|size)"
```

#### ECS

```bash
# Use ECS Exec to check metrics from running task
TASK_ARN=$(aws ecs list-tasks --cluster mw-prod-cluster --service-name mw-prod-liberty --query 'taskArns[0]' --output text)

aws ecs execute-command \
  --cluster mw-prod-cluster \
  --task $TASK_ARN \
  --container liberty \
  --interactive \
  --command "curl -s http://localhost:9080/metrics | grep -E 'threadpool_(activeThreads|size)'"

# Check in Prometheus/Grafana for historical data
# Thread pool utilization > 90% indicates saturation
```

### 4. Check Connection Pool Status

Database connection pool exhaustion blocks request processing.

#### Kubernetes

```bash
# Check connection pool metrics
kubectl exec -n monitoring -it \
  $(kubectl get pod -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}') \
  -- promtool query instant http://localhost:9090 \
  'connectionpool_freeConnections{job="liberty"} / connectionpool_managedConnections{job="liberty"}'

# Check for queued connection requests
kubectl exec -n monitoring -it \
  $(kubectl get pod -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}') \
  -- promtool query instant http://localhost:9090 \
  'connectionpool_queuedRequests{job="liberty"}'

# Direct metrics check
kubectl exec -n liberty -it \
  $(kubectl get pod -n liberty -l app=liberty -o jsonpath='{.items[0].metadata.name}') \
  -- curl -s http://localhost:9080/metrics | grep -E "connectionpool_(freeConnections|managedConnections|queuedRequests)"
```

#### ECS

```bash
# Check via ECS Exec
TASK_ARN=$(aws ecs list-tasks --cluster mw-prod-cluster --service-name mw-prod-liberty --query 'taskArns[0]' --output text)

aws ecs execute-command \
  --cluster mw-prod-cluster \
  --task $TASK_ARN \
  --container liberty \
  --interactive \
  --command "curl -s http://localhost:9080/metrics | grep -E 'connectionpool_(freeConnections|managedConnections|queuedRequests|waitTime)'"
```

---

## Common Causes

### 1. Slow Database Queries

**Symptoms:**
- High `connectionpool_waitTime_total_seconds` rate
- Low `connectionpool_freeConnections`
- Database CPU/IO metrics elevated

**Verification:**
```bash
# Check average connection hold time
curl -s http://localhost:9080/metrics | grep connectionpool_inUseTime
```

### 2. Thread Pool Exhaustion

**Symptoms:**
- `threadpool_activeThreads / threadpool_size > 0.9`
- Request queue building up
- Response times increase linearly with load

**Verification:**
```bash
# Check thread pool saturation
curl -s http://localhost:9080/metrics | grep -E "threadpool_(activeThreads|size|queueSize)"
```

### 3. Garbage Collection Pauses

**Symptoms:**
- Periodic latency spikes
- High `gc_time_total_seconds` rate
- Memory usage near maximum

**Verification:**
```bash
# Check GC time
curl -s http://localhost:9080/metrics | grep gc_time

# Check heap usage
curl -s http://localhost:9080/metrics | grep -E "memory_(usedHeap|maxHeap)"
```

### 4. Network Latency

**Symptoms:**
- Consistent latency increase across all endpoints
- External service calls timing out
- No correlation with internal resource metrics

**Verification:**
```bash
# Kubernetes: Check network policies and DNS resolution
kubectl exec -n liberty -it POD_NAME -- nslookup database-service.database.svc.cluster.local

# ECS: Check VPC flow logs and network connectivity
aws ec2 describe-network-interfaces --filters Name=group-id,Values=sg-XXXXXXXXXX
```

### 5. Insufficient Resources

**Symptoms:**
- CPU throttling (container CPU near limit)
- Memory pressure (OOM events)
- Pod evictions or task replacements

---

## Resolution Steps

### 1. Scale Horizontally (Add Replicas/Tasks)

Distribute load across more instances to reduce per-instance pressure.

#### Kubernetes

```bash
# Increase replica count immediately
kubectl scale deployment liberty-app -n liberty --replicas=5

# Verify new pods are running and ready
kubectl get pods -n liberty -l app=liberty -w

# Check HPA status (if HPA is managing replicas)
kubectl get hpa liberty-hpa -n liberty

# Temporarily adjust HPA minimum if needed
kubectl patch hpa liberty-hpa -n liberty -p '{"spec":{"minReplicas":5}}'
```

#### ECS

```bash
# Update ECS service desired count
aws ecs update-service \
  --cluster mw-prod-cluster \
  --service mw-prod-liberty \
  --desired-count 4

# Monitor scaling progress
aws ecs describe-services \
  --cluster mw-prod-cluster \
  --services mw-prod-liberty \
  --query 'services[0].{desired:desiredCount,running:runningCount,pending:pendingCount}'

# Adjust auto-scaling minimum capacity
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --resource-id service/mw-prod-cluster/mw-prod-liberty \
  --scalable-dimension ecs:service:DesiredCount \
  --min-capacity 4 \
  --max-capacity 6
```

### 2. Scale Vertically (Increase Resources)

Increase CPU/memory allocation per instance.

#### Kubernetes

```bash
# Edit deployment to increase resources
kubectl patch deployment liberty-app -n liberty -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "liberty",
          "resources": {
            "requests": {"cpu": "1000m", "memory": "2Gi"},
            "limits": {"cpu": "4000m", "memory": "4Gi"}
          }
        }]
      }
    }
  }
}'

# Watch rollout
kubectl rollout status deployment/liberty-app -n liberty
```

#### ECS

```bash
# Update task definition with increased resources
# First, get current task definition
aws ecs describe-task-definition \
  --task-definition mw-prod-liberty \
  --query 'taskDefinition' > task-def.json

# Edit task-def.json to increase cpu/memory, then register new revision
# cpu: "1024" -> "2048", memory: "2048" -> "4096"
aws ecs register-task-definition --cli-input-json file://task-def.json

# Update service to use new task definition
aws ecs update-service \
  --cluster mw-prod-cluster \
  --service mw-prod-liberty \
  --task-definition mw-prod-liberty:NEW_REVISION \
  --force-new-deployment
```

### 3. Database Optimization

Address slow queries and connection pool issues.

#### Identify and Optimize Slow Queries

```sql
-- PostgreSQL: Find slow queries
SELECT pid, now() - query_start AS duration, query, state
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY duration DESC
LIMIT 20;

-- Check for missing indexes
SELECT schemaname, tablename, indexname, idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
WHERE idx_scan = 0
ORDER BY schemaname, tablename;

-- Analyze query plans for slow queries
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) SELECT ...;
```

#### Increase Connection Pool Size

Update Liberty server.xml or environment variables:

```xml
<!-- In server.xml -->
<dataSource id="DefaultDataSource" jndiName="jdbc/myDS">
    <connectionManager maxPoolSize="50" minPoolSize="10" connectionTimeout="30s"/>
    <properties.postgresql serverName="${DB_HOST}" portNumber="${DB_PORT}"
                           databaseName="${DB_NAME}" user="${DB_USERNAME}" password="${DB_PASSWORD}"/>
</dataSource>
```

### 4. Thread Pool Tuning

Increase thread pool capacity for high-concurrency workloads.

#### Liberty Server Configuration

Add or modify in server.xml:

```xml
<!-- Increase default executor thread pool -->
<executor id="Default" name="Default"
          coreThreads="20" maxThreads="100"
          keepAlive="60s" stealPolicy="LOCAL"/>
```

For immediate effect without restart, consider horizontal scaling first.

### 5. JVM Tuning for GC Issues

If garbage collection is causing latency spikes:

```bash
# Update JVM_ARGS environment variable
# Kubernetes
kubectl set env deployment/liberty-app -n liberty \
  JVM_ARGS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+UseG1GC -XX:MaxGCPauseMillis=200"

# ECS: Update task definition with new environment variable
```

---

## Escalation Criteria

Escalate to the on-call engineering team when:

| Condition | Action |
|-----------|--------|
| p95 latency > 5 seconds for > 10 minutes | Page on-call engineer |
| Horizontal scaling does not reduce latency | Escalate to senior engineer |
| Database connection pool exhausted | Engage DBA team |
| Multiple dependent services affected | Initiate incident bridge |
| GC pauses > 1 second occurring frequently | Escalate to JVM specialist |
| Network latency identified as root cause | Engage platform/network team |

### Escalation Contacts

| Team | Responsibility | Contact Method |
|------|---------------|----------------|
| Platform Engineering | Infrastructure, scaling | Slack: #platform-oncall |
| Database Team | RDS, query optimization | Slack: #dba-oncall |
| Application Team | Liberty configuration, code | Slack: #app-oncall |

---

## Post-Incident Tasks

1. **Document root cause** in incident ticket
2. **Create follow-up tickets** for permanent fixes (query optimization, capacity planning)
3. **Review monitoring thresholds** - adjust if alert was too sensitive or not sensitive enough
4. **Update runbook** with any new diagnostic steps or resolutions discovered
5. **Schedule capacity review** if scaling was required

---

## Related Alerts and Runbooks

| Alert | Relationship |
|-------|-------------|
| LibertyThreadPoolExhaustion | Often precedes slow responses |
| LibertyDatabaseConnectionPoolLow | Direct cause of latency |
| LibertyHighHeapUsage | GC pauses cause latency spikes |
| LibertyHighErrorRate | Slow responses may timeout and become errors |

---

## References

- [MicroProfile Metrics 5.0 Specification](https://download.eclipse.org/microprofile/microprofile-metrics-5.0/microprofile-metrics-spec-5.0.html)
- [Open Liberty Thread Pool Configuration](https://openliberty.io/docs/latest/reference/config/executor.html)
- [Open Liberty Connection Manager](https://openliberty.io/docs/latest/reference/config/connectionManager.html)
- [AWS ECS Service Auto Scaling](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-auto-scaling.html)
- [Kubernetes Horizontal Pod Autoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
