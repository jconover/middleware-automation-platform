# Liberty Database Connection Pool Runbook

This runbook covers alerts related to Open Liberty database connection pool issues. Use this guide to investigate and resolve connection pool problems affecting the mw-prod environment.

## Table of Contents

- [Alert Reference](#alert-reference)
- [Impact Assessment](#impact-assessment)
- [Investigation Steps](#investigation-steps)
- [Common Causes](#common-causes)
- [Resolution Steps](#resolution-steps)
- [Connection Pool Configuration Reference](#connection-pool-configuration-reference)
- [Escalation Criteria](#escalation-criteria)

---

## Alert Reference

### LibertyDatabaseConnectionPoolLow

| Attribute | Value |
|-----------|-------|
| **Severity** | Warning |
| **Threshold** | Free connections < 10% of pool size |
| **Duration** | 5 minutes |
| **Description** | Connection pool is running low on available connections. Requests may start queuing soon. |

**PromQL Expression:**
```promql
connectionpool_freeConnections{job="liberty", mp_scope="vendor"}
  / connectionpool_managedConnections{job="liberty", mp_scope="vendor"} < 0.1
```

---

### LibertyDatabaseConnectionPoolExhausted

| Attribute | Value |
|-----------|-------|
| **Severity** | Critical |
| **Threshold** | Free connections = 0 |
| **Duration** | 2 minutes |
| **Description** | All database connections are in use. New requests will queue and may timeout. |

**PromQL Expression:**
```promql
connectionpool_freeConnections{job="liberty", mp_scope="vendor"} == 0
and connectionpool_managedConnections{job="liberty", mp_scope="vendor"} > 0
```

---

### LibertyDatabaseConnectionFailure

| Attribute | Value |
|-----------|-------|
| **Severity** | Critical |
| **Threshold** | Destroy/create ratio > 0.5 with destroy rate > 0.1/sec |
| **Duration** | 5 minutes |
| **Description** | Database connections are failing and being destroyed at a high rate. Indicates database or network issues. |

**PromQL Expression:**
```promql
(
  rate(connectionpool_destroy_total{job="liberty", mp_scope="vendor"}[5m])
  / (rate(connectionpool_create_total{job="liberty", mp_scope="vendor"}[5m]) + 0.001)
) > 0.5
and rate(connectionpool_destroy_total{job="liberty", mp_scope="vendor"}[5m]) > 0.1
```

---

### LibertyDatabaseQueuedRequestsHigh

| Attribute | Value |
|-----------|-------|
| **Severity** | Warning |
| **Threshold** | Queued requests > 5 |
| **Duration** | 2 minutes |
| **Description** | Requests are waiting for database connections. Indicates pool saturation. |

**PromQL Expression:**
```promql
connectionpool_queuedRequests{job="liberty", mp_scope="vendor"} > 5
```

---

### LibertyDatabaseConnectionChurn

| Attribute | Value |
|-----------|-------|
| **Severity** | Warning |
| **Threshold** | Connection creation rate > 1/sec |
| **Duration** | 10 minutes |
| **Description** | High rate of new connection creation. May indicate timeout issues or database restarts. |

**PromQL Expression:**
```promql
rate(connectionpool_create_total{job="liberty", mp_scope="vendor"}[5m]) > 1
```

---

### LibertyConnectionPoolWaitTime

| Attribute | Value |
|-----------|-------|
| **Severity** | Warning |
| **Threshold** | Wait time rate > 1 second |
| **Duration** | 5 minutes |
| **Description** | Applications are waiting too long for database connections. |

**PromQL Expression:**
```promql
rate(connectionpool_waitTime_total_seconds{job="liberty", mp_scope="vendor"}[5m]) > 1
```

---

## Impact Assessment

### User-Facing Impact

| Severity | Symptoms | User Experience |
|----------|----------|-----------------|
| **Low** (Pool Low) | Slightly increased response times | Minor latency increase, usually imperceptible |
| **Medium** (Queued Requests) | Requests queuing for connections | Noticeable delays (1-5 seconds) |
| **High** (Pool Exhausted) | All connections in use | Requests timeout, 503/504 errors returned |
| **Critical** (Connection Failure) | Connections failing repeatedly | Complete database unavailability |

### System Impact

- **Request Blocking**: When pool is exhausted, new requests queue waiting for a connection
- **Timeout Cascades**: Queued requests may timeout, causing downstream service failures
- **Thread Starvation**: Blocked threads waiting for connections can exhaust the thread pool
- **Health Check Failures**: Readiness probes may fail, triggering pod restarts
- **Load Balancer Drain**: ALB may mark instances as unhealthy, reducing capacity

### Business Impact

- Failed transactions and potential data inconsistency
- Customer-facing errors and degraded user experience
- SLA violations and potential revenue impact
- Increased support ticket volume

---

## Investigation Steps

### Step 1: Check Connection Pool Metrics via /metrics

**For ECS Tasks:**

```bash
# Get running task IPs from ECS service discovery
aws ecs list-tasks --cluster mw-prod-cluster --service-name mw-prod-liberty --query 'taskArns[]' --output text | \
  xargs -I {} aws ecs describe-tasks --cluster mw-prod-cluster --tasks {} --query 'tasks[].attachments[].details[?name==`privateIPv4Address`].value' --output text

# Query metrics from a specific task (replace IP)
curl -s http://<TASK_IP>:9080/metrics | grep connectionpool
```

**For EC2 Instances:**

```bash
# Query metrics from Liberty instances
curl -s http://<LIBERTY_INSTANCE_IP>:9080/metrics | grep connectionpool
```

**For Kubernetes (Local):**

```bash
# Port-forward to a Liberty pod
kubectl port-forward pod/<liberty-pod-name> 9080:9080 -n default

# Query metrics
curl -s http://localhost:9080/metrics | grep connectionpool
```

**Key Metrics to Check:**

| Metric | Description | Healthy Value |
|--------|-------------|---------------|
| `connectionpool_freeConnections` | Available connections | > 20% of managedConnections |
| `connectionpool_managedConnections` | Total pool size | Matches maxPoolSize config |
| `connectionpool_inUseConnections` | Connections currently in use | < 80% of managedConnections |
| `connectionpool_queuedRequests` | Requests waiting for connection | 0 |
| `connectionpool_waitTime_total_seconds` | Cumulative wait time | Low rate of increase |
| `connectionpool_create_total` | Total connections created | Low rate |
| `connectionpool_destroy_total` | Total connections destroyed | Low rate, close to create |

---

### Step 2: Check RDS Connection Count

**Via AWS Console:**
1. Navigate to RDS > Databases > mw-prod-postgres
2. Select Monitoring tab
3. Check "Database connections" metric

**Via AWS CLI:**

```bash
# Get current connection count
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=mw-prod-postgres \
  --start-time $(date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Average,Maximum

# Check max connections parameter
aws rds describe-db-instances \
  --db-instance-identifier mw-prod-postgres \
  --query 'DBInstances[0].DBInstanceClass'
```

**PostgreSQL Direct Query (if accessible):**

```sql
-- Current connections
SELECT count(*) FROM pg_stat_activity;

-- Connections by state
SELECT state, count(*)
FROM pg_stat_activity
GROUP BY state;

-- Connections by application/client
SELECT application_name, client_addr, count(*)
FROM pg_stat_activity
GROUP BY application_name, client_addr;

-- Max connections setting
SHOW max_connections;
```

**RDS Connection Limits by Instance Class:**

| Instance Class | Max Connections (approx) |
|----------------|-------------------------|
| db.t3.micro | 87 |
| db.t3.small | 143 |
| db.t3.medium | 293 |
| db.r5.large | 1,364 |
| db.r5.xlarge | 2,728 |

---

### Step 3: Check for Slow Queries

**Via RDS Performance Insights:**
1. Navigate to RDS > Performance Insights > mw-prod-postgres
2. Review "Top SQL" for queries consuming high DB time
3. Check "Top waits" for lock contention or I/O waits

**Via AWS CLI:**

```bash
# Enable slow query logging if not already enabled
aws rds modify-db-parameter-group \
  --db-parameter-group-name <your-parameter-group> \
  --parameters "ParameterName=log_min_duration_statement,ParameterValue=1000,ApplyMethod=immediate"

# View recent slow queries in CloudWatch Logs
aws logs filter-log-events \
  --log-group-name /aws/rds/instance/mw-prod-postgres/postgresql \
  --filter-pattern "duration:" \
  --start-time $(date -u -d '30 minutes ago' +%s)000
```

**PostgreSQL Direct Query:**

```sql
-- Currently running queries
SELECT pid, now() - pg_stat_activity.query_start AS duration, query, state
FROM pg_stat_activity
WHERE (now() - pg_stat_activity.query_start) > interval '5 seconds'
ORDER BY duration DESC;

-- Most time-consuming queries (requires pg_stat_statements extension)
SELECT query, calls, total_time, mean_time, rows
FROM pg_stat_statements
ORDER BY total_time DESC
LIMIT 10;

-- Queries waiting for locks
SELECT blocked_locks.pid AS blocked_pid,
       blocked_activity.usename AS blocked_user,
       blocking_locks.pid AS blocking_pid,
       blocking_activity.usename AS blocking_user,
       blocked_activity.query AS blocked_statement
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks
    ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
    AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;
```

---

### Step 4: Check Network Connectivity to RDS

**From ECS Task:**

```bash
# Exec into a running task (requires ECS Exec enabled)
aws ecs execute-command \
  --cluster mw-prod-cluster \
  --task <task-id> \
  --container liberty \
  --interactive \
  --command "/bin/bash"

# Test connectivity
nc -zv <rds-endpoint> 5432
```

**From EC2 Instance:**

```bash
# SSH to Liberty instance
ssh -i ~/.ssh/mw-prod-deployer.pem ec2-user@<instance-ip>

# Test TCP connectivity
nc -zv mw-prod-postgres.<region>.rds.amazonaws.com 5432

# Test DNS resolution
nslookup mw-prod-postgres.<region>.rds.amazonaws.com

# Trace route (if ICMP allowed)
traceroute mw-prod-postgres.<region>.rds.amazonaws.com
```

**Check Security Groups:**

```bash
# Get RDS security group
aws rds describe-db-instances \
  --db-instance-identifier mw-prod-postgres \
  --query 'DBInstances[0].VpcSecurityGroups[].VpcSecurityGroupId'

# Check security group rules
aws ec2 describe-security-groups \
  --group-ids <sg-id> \
  --query 'SecurityGroups[0].IpPermissions'
```

---

## Common Causes

### 1. Slow Queries

**Symptoms:**
- High `connectionpool_inUseTime_total_seconds` rate
- Low connection churn
- Pool exhaustion despite normal request volume

**Indicators:**
- Long-running queries in `pg_stat_activity`
- High DB time in Performance Insights
- Specific endpoints showing high latency

---

### 2. Connection Leaks

**Symptoms:**
- `connectionpool_managedConnections` steadily increasing
- `connectionpool_freeConnections` decreasing over time
- Problem resolves temporarily after pod restart

**Indicators:**
- Connections not returned to pool (held by application code)
- Missing `try-finally` or `try-with-resources` blocks
- Exceptions preventing connection close

---

### 3. Database Overload

**Symptoms:**
- High RDS CPU or memory utilization
- High `DatabaseConnections` metric on RDS
- All Liberty pools reporting similar issues

**Indicators:**
- RDS CloudWatch metrics show resource exhaustion
- Multiple applications competing for connections
- Database approaching `max_connections` limit

---

### 4. Network Issues

**Symptoms:**
- High `connectionpool_destroy_total` rate
- Connection failures with timeout errors
- Intermittent connectivity

**Indicators:**
- VPC flow logs show rejected traffic
- Security group changes
- NAT gateway issues
- DNS resolution failures

---

### 5. Pool Misconfiguration

**Symptoms:**
- Pool size too small for workload
- Timeouts too aggressive
- Connection validation issues

**Indicators:**
- `maxPoolSize` lower than concurrent request count
- `connectionTimeout` causing premature failures
- Stale connections not being purged

---

## Resolution Steps

### Immediate Mitigation

#### Option 1: Restart Pods to Reset Connections (ECS)

```bash
# Force new deployment to replace all tasks
aws ecs update-service \
  --cluster mw-prod-cluster \
  --service mw-prod-liberty \
  --force-new-deployment

# Monitor deployment progress
aws ecs describe-services \
  --cluster mw-prod-cluster \
  --services mw-prod-liberty \
  --query 'services[0].deployments'
```

#### Option 2: Restart Pods to Reset Connections (Kubernetes)

```bash
# Rolling restart
kubectl rollout restart deployment/liberty-app -n default

# Monitor rollout
kubectl rollout status deployment/liberty-app -n default
```

#### Option 3: Scale Up Temporarily

```bash
# ECS - increase desired count
aws ecs update-service \
  --cluster mw-prod-cluster \
  --service mw-prod-liberty \
  --desired-count 4

# Kubernetes - scale deployment
kubectl scale deployment/liberty-app --replicas=4 -n default
```

---

### Resolution: Increase Pool Size in server.xml

**Step 1: Update server.xml configuration**

Add or modify the `connectionManager` element within your `dataSource`:

```xml
<dataSource id="DefaultDataSource" jndiName="jdbc/defaultDS">
    <jdbcDriver libraryRef="postgresLib"/>
    <properties.postgresql
        serverName="${env.DB_HOST}"
        portNumber="${env.DB_PORT}"
        databaseName="${env.DB_NAME}"
        user="${env.DB_USER}"
        password="${env.DB_PASSWORD}"/>
    <connectionManager
        maxPoolSize="50"
        minPoolSize="10"
        connectionTimeout="30s"
        maxIdleTime="10m"
        reapTime="3m"
        purgePolicy="EntirePool"/>
</dataSource>
```

**Step 2: Deploy the updated configuration**

For ECS:
```bash
# Build and push new image
podman build -t liberty-app:1.0.1 -f containers/liberty/Containerfile .
podman push <ecr-uri>/mw-prod-liberty:1.0.1

# Update ECS service
aws ecs update-service \
  --cluster mw-prod-cluster \
  --service mw-prod-liberty \
  --force-new-deployment
```

For Kubernetes:
```bash
# Build and push image
podman build -t docker.io/jconover/liberty-app:1.0.1 -f containers/liberty/Containerfile .
podman push docker.io/jconover/liberty-app:1.0.1

# Update deployment
kubectl set image deployment/liberty-app liberty=docker.io/jconover/liberty-app:1.0.1
```

---

### Resolution: RDS Scaling or Parameter Tuning

#### Scale RDS Instance

```bash
# Check current instance class
aws rds describe-db-instances \
  --db-instance-identifier mw-prod-postgres \
  --query 'DBInstances[0].DBInstanceClass'

# Modify instance class (causes downtime unless Multi-AZ)
aws rds modify-db-instance \
  --db-instance-identifier mw-prod-postgres \
  --db-instance-class db.r5.large \
  --apply-immediately

# Monitor modification progress
aws rds describe-db-instances \
  --db-instance-identifier mw-prod-postgres \
  --query 'DBInstances[0].DBInstanceStatus'
```

#### Increase max_connections Parameter

```bash
# Create or modify parameter group
aws rds create-db-parameter-group \
  --db-parameter-group-name mw-prod-postgres-params \
  --db-parameter-group-family postgres15 \
  --description "Custom parameters for mw-prod-postgres"

# Modify max_connections (requires reboot)
aws rds modify-db-parameter-group \
  --db-parameter-group-name mw-prod-postgres-params \
  --parameters "ParameterName=max_connections,ParameterValue=500,ApplyMethod=pending-reboot"

# Apply parameter group to instance
aws rds modify-db-instance \
  --db-instance-identifier mw-prod-postgres \
  --db-parameter-group-name mw-prod-postgres-params

# Reboot to apply
aws rds reboot-db-instance \
  --db-instance-identifier mw-prod-postgres
```

---

### Resolution: Query Optimization

**Step 1: Identify problematic queries**

Use Performance Insights or direct SQL queries from Step 3 above.

**Step 2: Add indexes for slow queries**

```sql
-- Example: Add index for frequently queried column
CREATE INDEX CONCURRENTLY idx_orders_customer_id ON orders(customer_id);

-- Analyze query plan
EXPLAIN ANALYZE SELECT * FROM orders WHERE customer_id = 123;
```

**Step 3: Terminate long-running queries if needed**

```sql
-- Find long-running queries
SELECT pid, now() - pg_stat_activity.query_start AS duration, query
FROM pg_stat_activity
WHERE (now() - pg_stat_activity.query_start) > interval '5 minutes';

-- Terminate a specific query
SELECT pg_terminate_backend(<pid>);
```

---

## Connection Pool Configuration Reference

### Liberty dataSource Settings

```xml
<dataSource id="DefaultDataSource" jndiName="jdbc/defaultDS">
    <jdbcDriver libraryRef="postgresLib"/>
    <properties.postgresql
        serverName="${env.DB_HOST}"
        portNumber="5432"
        databaseName="${env.DB_NAME}"
        user="${env.DB_USER}"
        password="${env.DB_PASSWORD}"/>

    <connectionManager
        maxPoolSize="50"
        minPoolSize="10"
        connectionTimeout="30s"
        maxIdleTime="10m"
        reapTime="3m"
        agedTimeout="30m"
        purgePolicy="EntirePool"
        numConnectionsPerThreadLocal="2"/>
</dataSource>

<library id="postgresLib">
    <fileset dir="${server.config.dir}/lib" includes="postgresql-*.jar"/>
</library>
```

### Configuration Parameters Explained

| Parameter | Default | Recommended | Description |
|-----------|---------|-------------|-------------|
| `maxPoolSize` | 50 | Workload-dependent | Maximum connections in pool. Set based on: (concurrent requests) x (avg connections per request) + buffer |
| `minPoolSize` | 0 | 5-10 | Minimum connections maintained. Reduces connection creation latency |
| `connectionTimeout` | 30s | 30s | Time to wait for available connection before failing |
| `maxIdleTime` | 30m | 10m | Time before idle connections are closed |
| `reapTime` | 3m | 3m | Interval for checking idle connections |
| `agedTimeout` | -1 (disabled) | 30m | Maximum lifetime of a connection. Helps prevent stale connections |
| `purgePolicy` | EntirePool | EntirePool | How to handle validation failures. `EntirePool` purges all on failure |
| `numConnectionsPerThreadLocal` | 0 | 2 | Thread-local connection cache. Reduces pool contention |

### Sizing Guidelines

**Calculate maxPoolSize:**

```
maxPoolSize = (peak_concurrent_requests / number_of_instances) * connections_per_request * 1.2

Example:
- Peak concurrent requests: 100
- Number of Liberty instances: 4
- Connections per request: 1 (typical for simple CRUD)
- Buffer: 20%

maxPoolSize = (100 / 4) * 1 * 1.2 = 30
```

**Verify against RDS limits:**

```
Total application connections = maxPoolSize * number_of_instances
This must be < RDS max_connections - reserved_connections_for_admin
```

### Environment Variable Override

Configure pool size via environment variables for flexibility:

```xml
<connectionManager
    maxPoolSize="${env.DB_POOL_MAX_SIZE}"
    minPoolSize="${env.DB_POOL_MIN_SIZE}"
    connectionTimeout="${env.DB_CONNECTION_TIMEOUT}"/>
```

---

## Escalation Criteria

### Escalate to Database Team When:

- [ ] RDS CPU consistently > 80%
- [ ] RDS storage IOPS exhausted
- [ ] Replication lag (if using read replicas) > 30 seconds
- [ ] Need to modify RDS instance class
- [ ] Need to adjust PostgreSQL parameters
- [ ] Suspected database corruption or data issues

### Escalate to Platform/SRE Team When:

- [ ] Network connectivity issues between Liberty and RDS
- [ ] Security group or VPC configuration changes needed
- [ ] Need to scale ECS service beyond auto-scaling limits
- [ ] Persistent issues after standard remediation
- [ ] Multiple services affected simultaneously

### Escalate to Development Team When:

- [ ] Connection leak suspected (requires code review)
- [ ] Specific queries identified as root cause (requires optimization)
- [ ] Application-level changes needed
- [ ] New features causing increased database load

### Escalation Contact Information

| Team | Contact Method | SLA |
|------|----------------|-----|
| Database Team | #db-support Slack channel | 30 min response |
| Platform/SRE | PagerDuty `platform-oncall` | 15 min response |
| Development | #dev-support Slack channel | 1 hour response |

### Information to Include in Escalation

1. Alert name and severity
2. Time issue started
3. Current metric values (screenshots from Grafana/Prometheus)
4. Actions already taken
5. Number of affected instances/pods
6. User impact assessment
7. Relevant log snippets

---

## Related Runbooks

- Liberty Server Down Runbook
- Liberty High Latency Runbook
- RDS Performance Troubleshooting
- Network Connectivity Troubleshooting

---

## Revision History

| Date | Version | Author | Changes |
|------|---------|--------|---------|
| 2026-01-02 | 1.0 | Platform Team | Initial version |
