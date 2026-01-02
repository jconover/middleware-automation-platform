# Liberty High Heap Usage Runbook

## Overview

This runbook covers the investigation and resolution of high JVM heap usage alerts for Open Liberty application servers across all deployment environments.

### Related Alerts

| Alert Name | Severity | Threshold | Duration |
|------------|----------|-----------|----------|
| LibertyHighHeapUsage | Warning | > 85% | 5 minutes |
| LibertyCriticalHeapUsage | Critical | > 95% | 2 minutes |
| ECSLibertyHighHeapUsage | Warning | > 85% | 5 minutes |

### Alert Expressions

**Kubernetes (LibertyHighHeapUsage / LibertyCriticalHeapUsage)**
```promql
100 * memory_usedHeap_bytes{job="liberty", mp_scope="base"}
  / memory_maxHeap_bytes{job="liberty", mp_scope="base"} > 85
```

**ECS (ECSLibertyHighHeapUsage)**
```promql
memory_usedHeap_bytes{job="ecs-liberty", mp_scope="base"}
  / memory_maxHeap_bytes{job="ecs-liberty", mp_scope="base"} > 0.85
```

---

## Impact Assessment

### Warning Level (85% threshold)

- Application may experience increased garbage collection pauses
- Response times may increase due to GC overhead
- Risk of escalation to critical if load continues

### Critical Level (95% threshold)

- Imminent risk of OutOfMemoryError (OOM)
- Application may become unresponsive
- Container/pod may be OOM-killed by orchestrator
- Potential service disruption if multiple instances affected

---

## Investigation Steps

### 1. Check Current Heap Usage via Metrics Endpoint

**Kubernetes**
```bash
# Get pod name
kubectl get pods -l app=liberty -o name

# Query metrics endpoint directly
kubectl exec -it <pod-name> -- curl -s http://localhost:9080/metrics | grep -E "memory_(used|max)Heap"

# Or via port-forward
kubectl port-forward <pod-name> 9080:9080
curl -s http://localhost:9080/metrics | grep -E "memory_(used|max)Heap"
```

**ECS**
```bash
# Get task IPs from ECS
CLUSTER="mw-prod-cluster"
SERVICE="mw-prod-liberty"

# List running tasks
aws ecs list-tasks --cluster $CLUSTER --service-name $SERVICE --query 'taskArns[]' --output text

# Get task details (includes private IP)
TASK_ARN=$(aws ecs list-tasks --cluster $CLUSTER --service-name $SERVICE --query 'taskArns[0]' --output text)
aws ecs describe-tasks --cluster $CLUSTER --tasks $TASK_ARN --query 'tasks[0].attachments[0].details[?name==`privateIPv4Address`].value' --output text

# Query metrics from monitoring server (or via ALB)
curl -s http://<task-ip>:9080/metrics | grep -E "memory_(used|max)Heap"
```

**Local Podman**
```bash
# Direct container query
podman exec liberty curl -s http://localhost:9080/metrics | grep -E "memory_(used|max)Heap"

# Or via exposed port
curl -s http://localhost:9080/metrics | grep -E "memory_(used|max)Heap"
```

### 2. JVM Heap Analysis Commands

**Kubernetes**
```bash
# Get heap summary (OpenJ9)
kubectl exec -it <pod-name> -- /opt/java/openjdk/bin/jcmd 1 GC.heap_info

# Trigger verbose GC output
kubectl exec -it <pod-name> -- /opt/java/openjdk/bin/jcmd 1 GC.run_verbose

# View heap histogram (top consumers)
kubectl exec -it <pod-name> -- /opt/java/openjdk/bin/jcmd 1 GC.class_histogram | head -50

# Check OpenJ9 specific heap stats
kubectl exec -it <pod-name> -- /opt/java/openjdk/bin/jcmd 1 Dump.heap
```

**ECS**
```bash
# ECS Exec into running container
aws ecs execute-command \
  --cluster $CLUSTER \
  --task $TASK_ARN \
  --container liberty \
  --interactive \
  --command "/bin/bash"

# Then run inside container:
/opt/java/openjdk/bin/jcmd 1 GC.heap_info
/opt/java/openjdk/bin/jcmd 1 GC.class_histogram | head -50
```

Note: ECS Exec requires the task role to have SSM permissions and the service must be configured with `enableExecuteCommand: true`.

**Local Podman**
```bash
# Heap summary
podman exec liberty /opt/java/openjdk/bin/jcmd 1 GC.heap_info

# Heap histogram
podman exec liberty /opt/java/openjdk/bin/jcmd 1 GC.class_histogram | head -50
```

### 3. Thread Dump Commands

Thread dumps help identify threads that may be holding references and preventing garbage collection.

**Kubernetes**
```bash
# Generate thread dump
kubectl exec -it <pod-name> -- /opt/java/openjdk/bin/jcmd 1 Thread.print > thread-dump-$(date +%Y%m%d-%H%M%S).txt

# Generate 3 thread dumps 10 seconds apart for analysis
for i in 1 2 3; do
  kubectl exec -it <pod-name> -- /opt/java/openjdk/bin/jcmd 1 Thread.print > thread-dump-$i.txt
  sleep 10
done
```

**ECS**
```bash
# Via ECS Exec
aws ecs execute-command \
  --cluster $CLUSTER \
  --task $TASK_ARN \
  --container liberty \
  --interactive \
  --command "/opt/java/openjdk/bin/jcmd 1 Thread.print"
```

**Local Podman**
```bash
podman exec liberty /opt/java/openjdk/bin/jcmd 1 Thread.print > thread-dump-$(date +%Y%m%d-%H%M%S).txt
```

### 4. Check Garbage Collection Metrics

Query Prometheus or the metrics endpoint for GC behavior:

```promql
# GC time rate (should be < 0.1 seconds per second)
rate(gc_time_total_seconds{job="liberty", mp_scope="base"}[5m])

# GC count rate
rate(gc_total{job="liberty", mp_scope="base"}[5m])
```

```bash
# From metrics endpoint
curl -s http://localhost:9080/metrics | grep -E "gc_(time|total)"
```

---

## Common Causes

### 1. Memory Leaks

**Symptoms:**
- Heap usage grows steadily over time without recovery after GC
- Increasing GC frequency with diminishing returns
- Eventually leads to OOM regardless of traffic patterns

**Common Sources:**
- Unclosed resources (database connections, file handles, HTTP clients)
- Static collections that accumulate entries
- Event listeners not properly deregistered
- ThreadLocal variables not cleaned up
- Caching without eviction policies

### 2. Undersized Heap

**Symptoms:**
- High heap usage correlates directly with request volume
- GC recovers memory successfully but threshold is too low
- Problem appears during peak traffic

**Indicators:**
- Current max heap: 512MB (from jvm.options: `-Xmx512m`)
- If application legitimately needs more memory under load

### 3. Large Request Payloads

**Symptoms:**
- Heap spikes correlate with specific request types
- Large JSON/XML parsing, file uploads, or batch operations

**Investigation:**
```bash
# Check request sizes in access logs
kubectl logs <pod-name> | grep -E "POST|PUT" | tail -100

# Check for large response generation
curl -s http://localhost:9080/metrics | grep servlet_request
```

### 4. Session State Accumulation

**Symptoms:**
- Heap grows with number of active users
- Memory not released even when request rate decreases

**Investigation:**
- Check session count and size in Liberty metrics
- Review session timeout configuration in server.xml

### 5. Connection Pool Resource Leaks

**Symptoms:**
- Heap usage correlates with database activity
- Connection objects and associated buffers accumulate

```promql
# Check connection pool health
connectionpool_freeConnections{job="liberty", mp_scope="vendor"}
connectionpool_managedConnections{job="liberty", mp_scope="vendor"}
```

---

## Resolution Steps

### Short-Term: Immediate Relief

#### Option A: Pod/Container Restart

**Kubernetes**
```bash
# Rolling restart (zero downtime if multiple replicas)
kubectl rollout restart deployment/liberty-app

# Delete specific pod (will be recreated by deployment)
kubectl delete pod <pod-name>

# Verify new pod is healthy
kubectl get pods -l app=liberty -w
```

**ECS**
```bash
# Force new deployment (rolling update)
aws ecs update-service \
  --cluster mw-prod-cluster \
  --service mw-prod-liberty \
  --force-new-deployment

# Monitor deployment
aws ecs describe-services \
  --cluster mw-prod-cluster \
  --services mw-prod-liberty \
  --query 'services[0].deployments'
```

**Local Podman**
```bash
# Restart container
podman restart liberty

# Or stop and start fresh
podman stop liberty && podman start liberty
```

#### Option B: Horizontal Scaling

Distribute load across more instances to reduce per-instance memory pressure.

**Kubernetes**
```bash
# Scale up replicas
kubectl scale deployment/liberty-app --replicas=4

# Or use HPA if configured
kubectl get hpa
```

**ECS**
```bash
# Update desired count
aws ecs update-service \
  --cluster mw-prod-cluster \
  --service mw-prod-liberty \
  --desired-count 4

# ECS auto-scaling will also trigger if configured (CPU/memory/request thresholds)
```

#### Option C: Trigger Manual GC (Last Resort)

Only use if you need time to investigate without restarting:

```bash
# Kubernetes
kubectl exec -it <pod-name> -- /opt/java/openjdk/bin/jcmd 1 GC.run

# ECS (via ECS Exec)
# /opt/java/openjdk/bin/jcmd 1 GC.run

# Podman
podman exec liberty /opt/java/openjdk/bin/jcmd 1 GC.run
```

Note: This provides temporary relief only. If heap quickly returns to high levels, it indicates a memory leak or undersized heap.

### Long-Term: Root Cause Resolution

#### 1. Heap Size Tuning

Current configuration in `/containers/liberty/jvm.options`:
```
-Xmx512m
-Xms256m
```

**To increase heap size:**

1. Update jvm.options file:
   ```
   -Xmx1024m
   -Xms512m
   ```

2. Rebuild and redeploy container:
   ```bash
   # From repository root
   podman build -t liberty-app:1.0.1 -f containers/liberty/Containerfile .

   # Push to registry and deploy
   # (see README.md for ECR/Docker Hub push commands)
   ```

3. Update container resource limits to match:

   **Kubernetes** - Update deployment manifest:
   ```yaml
   resources:
     requests:
       memory: "768Mi"
     limits:
       memory: "1280Mi"  # ~25% buffer above Xmx
   ```

   **ECS** - Update task definition memory allocation in Terraform.

#### 2. Memory Leak Investigation

**Generate Heap Dump for Analysis:**

```bash
# Kubernetes
kubectl exec -it <pod-name> -- /opt/java/openjdk/bin/jcmd 1 GC.heap_dump /tmp/heap.hprof
kubectl cp <pod-name>:/tmp/heap.hprof ./heap-$(date +%Y%m%d-%H%M%S).hprof

# ECS (must copy out via S3 or other means)
aws ecs execute-command \
  --cluster $CLUSTER \
  --task $TASK_ARN \
  --container liberty \
  --interactive \
  --command "/opt/java/openjdk/bin/jcmd 1 GC.heap_dump /tmp/heap.hprof"

# Podman
podman exec liberty /opt/java/openjdk/bin/jcmd 1 GC.heap_dump /tmp/heap.hprof
podman cp liberty:/tmp/heap.hprof ./heap-$(date +%Y%m%d-%H%M%S).hprof
```

**Analyze heap dump:**
- Use Eclipse Memory Analyzer (MAT)
- Look for "Leak Suspects" report
- Check "Dominator Tree" for largest object retainers

#### 3. Enable GC Logging for Analysis

Add to jvm.options:
```
-Xverbosegclog:/logs/gc.log,5,10000
```

This creates rolling GC logs (5 files, 10000 cycles each) for detailed analysis.

---

## JVM Options Reference

Current production configuration (`containers/liberty/jvm.options`):

| Option | Current Value | Description |
|--------|---------------|-------------|
| `-Xmx` | 512m | Maximum heap size |
| `-Xms` | 256m | Initial heap size |
| `-Djava.security.egd` | file:/dev/urandom | Entropy source for faster startup |

### Recommended Tuning Options

For high-memory workloads, consider:

```
# Increased heap
-Xmx1024m
-Xms512m

# OpenJ9 Gencon GC tuning (default GC policy)
-Xgcpolicy:gencon
-Xmn256m                    # Nursery size (young generation)

# GC logging
-Xverbosegclog:/logs/gc.log,5,10000

# Heap dump on OOM
-Xdump:heap:events=systhrow,filter=java/lang/OutOfMemoryError

# Container awareness (OpenJ9 detects this automatically, but explicit is clearer)
-XX:+UseContainerSupport
```

### Memory Sizing Guidelines

| Workload | Recommended Xmx | Container Memory Limit |
|----------|-----------------|------------------------|
| Light (dev/test) | 256m - 512m | 384m - 768m |
| Medium (typical prod) | 512m - 1024m | 768m - 1536m |
| Heavy (large apps) | 1024m - 2048m | 1536m - 3072m |

Note: Container memory limit should be 1.25x to 1.5x the Xmx value to account for metaspace, native memory, and OS overhead.

---

## Escalation Criteria

### Escalate to Development Team When:

- Memory leak is suspected (heap does not recover after GC)
- Heap dump analysis reveals application code issues
- Problem requires code changes to fix

### Escalate to Platform/Infrastructure Team When:

- Multiple instances affected simultaneously
- Issue persists after restart and scaling
- Container orchestration issues suspected
- Resource limits need adjustment in infrastructure-as-code

### Escalate to On-Call Lead When:

- Critical alert (95% threshold) persists more than 10 minutes
- Service degradation affecting end users
- Multiple related alerts firing simultaneously
- Unable to restore service within 30 minutes

---

## Related Runbooks

- [Liberty Server Down](./liberty-server-down.md)
- [Liberty High Error Rate](./liberty-high-error-rate.md)
- [Liberty Database Connection Failure](./liberty-database-connection-failure.md)
- [Liberty Connection Pool Exhausted](./liberty-connection-pool-exhausted.md)

---

## Revision History

| Date | Author | Description |
|------|--------|-------------|
| 2026-01-02 | Platform Team | Initial version |
