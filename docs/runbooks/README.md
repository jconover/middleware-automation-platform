# Runbooks

Operational runbooks for responding to alerts from the middleware automation platform.

## Available Runbooks

| Runbook | Alerts Covered | Severity |
|---------|----------------|----------|
| [liberty-server-down.md](liberty-server-down.md) | LibertyServerDown, ECSLibertyTaskDown, ECSLibertyNoTasks, LibertyHighRestartCount, LibertyReadinessFailure, LibertyNoRequests, ECSLibertyTaskRestarts | Critical/Warning |
| [liberty-high-heap.md](liberty-high-heap.md) | LibertyHighHeapUsage, LibertyCriticalHeapUsage, ECSLibertyHighHeapUsage, LibertyHighGCTime, LibertyHighMemoryUsage | Critical/Warning |
| [liberty-high-error-rate.md](liberty-high-error-rate.md) | LibertyHighErrorRate, LibertyCriticalErrorRate, ECSLibertyHighErrorRate | Critical/Warning |
| [liberty-slow-responses.md](liberty-slow-responses.md) | LibertyHighLatency, ECSLibertySlowResponses, LibertyThreadPoolExhaustion, LibertyHighCPUUsage | Warning |
| [liberty-connection-pool.md](liberty-connection-pool.md) | LibertyDatabaseConnectionPoolLow, LibertyDatabaseConnectionPoolExhausted, LibertyDatabaseConnectionFailure, LibertyDatabaseQueuedRequestsHigh, LibertyDatabaseConnectionChurn, LibertyConnectionPoolWaitTime | Critical/Warning |

## Quick Reference

### By Severity

**Critical Alerts** (Immediate Response Required):
- LibertyServerDown / ECSLibertyTaskDown - [liberty-server-down.md](liberty-server-down.md)
- LibertyCriticalHeapUsage - [liberty-high-heap.md](liberty-high-heap.md)
- LibertyCriticalErrorRate - [liberty-high-error-rate.md](liberty-high-error-rate.md)
- LibertyDatabaseConnectionPoolExhausted - [liberty-connection-pool.md](liberty-connection-pool.md)
- LibertyDatabaseConnectionFailure - [liberty-connection-pool.md](liberty-connection-pool.md)

**Warning Alerts** (Investigate Within 15 Minutes):
- All other alerts in the table above

### By Symptom

| Symptom | Start With |
|---------|------------|
| Application unreachable | [liberty-server-down.md](liberty-server-down.md) |
| Slow response times | [liberty-slow-responses.md](liberty-slow-responses.md) |
| High error rates (5xx) | [liberty-high-error-rate.md](liberty-high-error-rate.md) |
| Memory issues / OOM | [liberty-high-heap.md](liberty-high-heap.md) |
| Database timeouts | [liberty-connection-pool.md](liberty-connection-pool.md) |

## Using These Runbooks

1. When an alert fires, find the corresponding runbook from the table above
2. Follow the investigation steps in order
3. Apply the resolution steps for your identified cause
4. Document what you found and how you resolved it
5. If escalation is needed, follow the criteria in each runbook

## Alert Configuration

Alert rules are defined in:
- **Kubernetes**: `kubernetes/base/monitoring/liberty-prometheusrule.yaml`
- **AWS ECS**: `monitoring/prometheus/rules/ecs-alerts.yml`
- **EC2/General**: `monitoring/prometheus/rules/liberty-alerts.yml`

## Related Documentation

- [AlertManager Configuration](../ALERTMANAGER_CONFIGURATION.md)
- [Disaster Recovery](../DISASTER_RECOVERY.md)
- [Monitoring README](../../monitoring/README.md)
