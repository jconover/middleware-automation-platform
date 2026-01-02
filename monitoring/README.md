# Monitoring Stack

Prometheus, Grafana, and AlertManager configuration for Open Liberty monitoring across AWS (ECS/EC2) and local Kubernetes deployments.

## Directory Structure

```
monitoring/
├── prometheus/
│   ├── prometheus.yml                # Main config with scrape targets
│   └── rules/
│       ├── liberty-alerts.yml        # Liberty and infrastructure alerts
│       └── ecs-alerts.yml            # ECS-specific alerts
├── alertmanager/
│   └── alertmanager.yml              # Alert routing and Slack receivers
└── grafana/
    └── dashboards/
        ├── ecs-liberty.json          # AWS ECS/EC2 dashboard
        └── k8s-liberty.json          # Kubernetes dashboard
```

**Kubernetes Monitoring Resources**: See `kubernetes/base/monitoring/` for ServiceMonitor and PrometheusRule definitions used with Prometheus Operator.

## Prometheus Configuration

### prometheus.yml

The main configuration file defines:

- **Global settings**: 15-second scrape and evaluation intervals
- **AlertManager connection**: Static target at `alertmanager:9093`
- **Rule files**: Loaded from `/etc/prometheus/rules/*.yml`
- **Scrape jobs**:
  - `prometheus` - Self-monitoring
  - `liberty` - Liberty application metrics from `/metrics`
  - `node` - Node Exporter for infrastructure metrics
  - `jenkins` - CI/CD metrics from `/prometheus`

**AWS ECS Note**: Since official Prometheus binaries lack `ecs_sd_configs`, AWS deployments use file-based service discovery. A cron job runs `ecs-discovery.sh` every 60 seconds to update `/etc/prometheus/targets/ecs-liberty.json`.

### Alert Rules

**liberty-alerts.yml** - Core application and infrastructure alerts:

| Alert | Condition | Severity | Duration |
|-------|-----------|----------|----------|
| LibertyServerDown | `up{job="liberty"} == 0` | critical | 1m |
| LibertyHighHeapUsage | Heap > 85% | warning | 5m |
| LibertyHighErrorRate | 5xx rate > 5% | warning | 5m |
| HighCPUUsage | CPU > 80% | warning | 10m |
| HighMemoryUsage | Memory > 85% | warning | 5m |

**ecs-alerts.yml** - ECS-specific alerts:

| Alert | Condition | Severity | Duration |
|-------|-----------|----------|----------|
| ECSLibertyTaskDown | `up{job="ecs-liberty"} == 0` | critical | 1m |
| ECSLibertyNoTasks | No tasks running | critical | 2m |
| ECSLibertyHighHeapUsage | Heap > 85% | warning | 5m |
| ECSLibertyHighErrorRate | 5xx rate > 5% | warning | 5m |
| ECSLibertySlowResponses | p95 > 2s | warning | 5m |
| ECSLibertyTaskRestarts | > 2 restarts in 10m | warning | 1m |

## AlertManager Configuration

The `alertmanager.yml` file routes alerts to Slack channels based on severity.

### Webhook Setup Required

Notifications will not work until you configure a webhook. The configuration uses file-based secrets:

```yaml
global:
  slack_api_url_file: '/etc/alertmanager/secrets/slack-webhook'
```

**Setup Methods**:

```bash
# Local/EC2: Create the secrets file
mkdir -p /etc/alertmanager/secrets
echo 'https://hooks.slack.com/services/T.../B.../xxx' > /etc/alertmanager/secrets/slack-webhook
chmod 600 /etc/alertmanager/secrets/slack-webhook

# Kubernetes: Create a secret
kubectl create secret generic alertmanager-secrets \
  --from-literal=slack-webhook='https://hooks.slack.com/services/T.../B.../xxx' \
  -n monitoring
```

For AWS production deployment with Secrets Manager, see [docs/ALERTMANAGER_CONFIGURATION.md](../docs/ALERTMANAGER_CONFIGURATION.md).

### Routing Configuration

| Receiver | Channel | Severity Match |
|----------|---------|----------------|
| critical | #middleware-critical | severity: critical |
| warning | #middleware-alerts | severity: warning |
| default | #middleware-alerts | Unmatched alerts |

### Inhibition Rules

Reduces alert noise by suppressing related alerts:

- `LibertyServerDown` suppresses all other Liberty alerts for the same instance
- `ECSLibertyNoTasks` suppresses individual `ECSLibertyTaskDown` alerts
- Critical severity suppresses warning severity for the same alert name

### Validation and Testing

```bash
# Validate configuration
amtool check-config /etc/alertmanager/alertmanager.yml

# Send test alert
curl -X POST http://alertmanager:9093/api/v1/alerts \
  -H "Content-Type: application/json" \
  -d '[{"labels":{"alertname":"TestAlert","severity":"warning"}}]'
```

## Grafana Dashboards

### Available Dashboards

| Dashboard | File | Use Case |
|-----------|------|----------|
| ECS Liberty Monitoring | `ecs-liberty.json` | AWS ECS and EC2 deployments |
| Kubernetes Liberty Monitoring | `k8s-liberty.json` | Local K8s homelab cluster |

### Dashboard Panels

Both dashboards include:

- **Service Health**: Healthy/unhealthy instance counts, up/down status timeline
- **Request Metrics**: Request rate, 2xx/4xx/5xx response rates
- **JVM Metrics**: Heap usage percentage, heap memory (used vs max)
- **ECS vs EC2 Comparison** (ECS dashboard only): Side-by-side request rate and heap usage

The Kubernetes dashboard adds:
- Namespace filtering variable
- Thread count by pod
- GC time rate
- Container CPU and memory vs limits

### Importing Dashboards

1. Log in to Grafana (default: admin/admin for local, see Secrets Manager for AWS)
2. Navigate to Dashboards > Import
3. Upload the JSON file or paste its contents
4. Select your Prometheus datasource
5. Click Import

## Metric Naming Conventions

MicroProfile Metrics 5.0 uses the `mp_scope` label instead of metric name prefixes.

### Liberty Application Metrics

| Metric | Scope | Type | Description |
|--------|-------|------|-------------|
| `servlet_request_total` | base | Counter | HTTP request count by status |
| `servlet_request_elapsedTime_seconds` | base | Histogram | Request duration |
| `memory_usedHeap_bytes` | base | Gauge | Current heap usage |
| `memory_maxHeap_bytes` | base | Gauge | Maximum heap size |
| `thread_count` | base | Gauge | Active thread count |
| `gc_time_total_seconds` | base | Counter | Cumulative GC time |
| `connectionpool_freeConnections` | vendor | Gauge | Available DB connections |
| `threadpool_activeThreads` | vendor | Gauge | Active threads in pool |

### Query Examples

```promql
# Request rate per second
rate(servlet_request_total{mp_scope="base"}[5m])

# Heap usage percentage
memory_usedHeap_bytes{mp_scope="base"} / memory_maxHeap_bytes{mp_scope="base"} * 100

# 95th percentile response time
histogram_quantile(0.95,
  rate(servlet_request_elapsedTime_seconds_bucket{mp_scope="base"}[5m]))

# Error rate percentage
sum(rate(servlet_request_total{mp_scope="base", status=~"5.."}[5m]))
/ sum(rate(servlet_request_total{mp_scope="base"}[5m])) * 100
```

### Job Labels by Environment

| Environment | Job Label |
|-------------|-----------|
| Local development | `liberty` |
| AWS ECS | `ecs-liberty` |
| AWS EC2 | `ec2-liberty` |
| Kubernetes | `liberty` (with namespace label) |

## Kubernetes Monitoring Resources

For Prometheus Operator deployments, additional resources are in `kubernetes/base/monitoring/`:

| Resource | File | Purpose |
|----------|------|---------|
| ServiceMonitor | `liberty-servicemonitor.yaml` | Auto-discovers Liberty services |
| PodMonitor | `liberty-servicemonitor.yaml` | Direct pod scraping alternative |
| PrometheusRule | `liberty-prometheusrule.yaml` | Alert rules for K8s deployments |
| AlertManager Config | `alertmanager-config.yaml` | K8s-specific routing |
| Secrets | `alertmanager-secrets.yaml` | Webhook secret template |

### ServiceMonitor Configuration

The ServiceMonitor matches Liberty services across namespaces (default, liberty, middleware) with the label `app: liberty`. It scrapes the `/metrics` endpoint on port `http` every 15 seconds and adds `pod`, `node`, and `namespace` labels to metrics.

### PrometheusRule Alerts

The Kubernetes PrometheusRule includes additional alerts beyond the base set:

- **Health**: LibertyHighRestartCount, LibertyReadinessFailure
- **JVM**: LibertyCriticalHeapUsage (>95%), LibertyHighGCTime, LibertyThreadPoolExhaustion
- **Requests**: LibertyCriticalErrorRate (>10%), LibertyHighLatency, LibertyNoRequests
- **Resources**: LibertyHighCPUUsage, LibertyHighMemoryUsage
- **Connections**: ConnectionPoolLow, ConnectionPoolWaitTime, ConnectionFailure, PoolExhausted

## Quick Reference

### Common Operations

```bash
# Reload Prometheus config
curl -X POST http://localhost:9090/-/reload

# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job, health}'

# Reload AlertManager config
curl -X POST http://localhost:9093/-/reload

# Query active alerts
curl http://localhost:9093/api/v1/alerts

# Validate alert rules
promtool check rules /etc/prometheus/rules/*.yml
```

### Default Ports

| Service | Port |
|---------|------|
| Prometheus | 9090 |
| AlertManager | 9093 |
| Grafana | 3000 |
| Liberty metrics | 9080 |
| Node Exporter | 9100 |

## Related Documentation

- [AlertManager Configuration Guide](../docs/ALERTMANAGER_CONFIGURATION.md) - Detailed webhook setup
- [Local Kubernetes Deployment](../docs/LOCAL_KUBERNETES_DEPLOYMENT.md) - K8s cluster setup
- [End-to-End Testing](../docs/END_TO_END_TESTING.md) - Monitoring verification steps
