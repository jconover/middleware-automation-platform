# Monitoring Stack

Comprehensive observability stack for the Enterprise Middleware Automation Platform. Provides metrics collection, visualization, and alerting for Liberty application servers across AWS (ECS/EC2) and local Kubernetes deployments.

## Overview

This directory contains configuration files and dashboards for a complete monitoring solution built on three core components:

- **Prometheus**: Time-series database for metrics collection and alerting
- **Grafana**: Visualization platform for dashboards and analytics
- **Alertmanager**: Alert routing and notification management

The monitoring stack supports multiple deployment environments:
- **AWS Production**: ECS Fargate and EC2 instances with file-based service discovery
- **Local Kubernetes**: 3-node homelab cluster with Prometheus Operator
- **Local Development**: Podman containers with static configuration

## Architecture

```
Liberty Apps --> Prometheus --> Grafana
                    |
              Alertmanager --> Slack/Email
```

**Key Features:**
- 15-second scrape intervals for real-time metrics
- Pre-configured alert rules for Liberty health and performance
- Auto-discovery of ECS tasks via AWS API (file-based)
- Kubernetes ServiceMonitor for automatic target discovery
- Production-ready dashboards for Liberty and infrastructure metrics

For detailed architecture diagrams, see [docs/architecture/diagrams/monitoring-architecture.md](../docs/architecture/diagrams/monitoring-architecture.md)

## Directory Structure

```
monitoring/
├── README.md                           # This file
├── prometheus/                         # Prometheus configuration
│   ├── prometheus.yml                  # Main Prometheus config (static targets)
│   └── rules/                          # Alert rule definitions
│       ├── liberty-alerts.yml          # Liberty-specific alerts
│       └── ecs-alerts.yml              # ECS-specific alerts
├── alertmanager/                       # Alertmanager configuration
│   └── alertmanager.yml                # Routing and receiver config
└── grafana/                            # Grafana dashboards
    └── dashboards/                     # Pre-built dashboard JSON
        ├── ecs-liberty.json            # AWS ECS Liberty dashboard
        └── k8s-liberty.json            # Kubernetes Liberty dashboard
```

## Deployment

### 1. AWS Production (ECS/EC2)

The monitoring stack is deployed automatically via Terraform when `create_monitoring_server = true`.

```bash
cd automated/terraform/environments/prod-aws
terraform apply -var="create_monitoring_server=true"
```

**What Gets Deployed:**
- Dedicated EC2 instance for Prometheus and Grafana
- ECS service discovery script (`/usr/local/bin/ecs-discovery.sh`)
- Cron job updating ECS targets every 60 seconds
- Alert rules automatically loaded from `monitoring/prometheus/rules/`

**ECS Service Discovery:**

Since official Prometheus binaries don't include `ecs_sd_configs`, we use a file-based approach:
```
Cron (60s) --> ecs-discovery.sh --> AWS ECS API
                    |
        /etc/prometheus/targets/ecs-liberty.json
                    |
              Prometheus scrapes
```

**Access Information:**
```bash
# Get monitoring server IP
terraform output monitoring_server_public_ip

# Retrieve Grafana credentials
aws secretsmanager get-secret-value \
    --secret-id mw-prod-grafana-credentials \
    --query SecretString --output text | jq -r .admin_password

# URLs
# Prometheus: http://<monitoring-ip>:9090
# Grafana:    http://<monitoring-ip>:3000
```

### 2. Local Kubernetes (Homelab)

Uses Prometheus Operator for automatic service discovery.

```bash
# Install kube-prometheus-stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
    -n monitoring --create-namespace

# Apply Liberty monitoring
kubectl apply -f kubernetes/base/monitoring/liberty-servicemonitor.yaml
kubectl apply -f kubernetes/base/monitoring/liberty-prometheusrule.yaml
```

**Access (MetalLB IPs):**
| Service | IP | Port |
|---------|-----|------|
| Prometheus | 192.168.68.201 | 9090 |
| Grafana | 192.168.68.202 | 3000 |
| Alertmanager | 192.168.68.203 | 9093 |

```bash
# Get Grafana password
kubectl get secret -n monitoring prometheus-grafana \
    -o jsonpath='{.data.admin-password}' | base64 -d
```

### 3. Local Development (Podman)

```bash
# Run Prometheus
podman run -d --name prometheus \
    -p 9090:9090 \
    -v $(pwd)/monitoring/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:Z \
    -v $(pwd)/monitoring/prometheus/rules:/etc/prometheus/rules:Z \
    prom/prometheus:v2.54.1

# Run Grafana
podman run -d --name grafana \
    -p 3000:3000 \
    -e GF_SECURITY_ADMIN_PASSWORD=admin \
    grafana/grafana:10.1.0
```

## Key Metrics

### Liberty Application (MicroProfile Metrics 5.0)

| Metric | Type | Description |
|--------|------|-------------|
| `base_servlet_request_total` | Counter | Total HTTP requests |
| `base_servlet_request_elapsedTime_seconds` | Histogram | Request duration |
| `base_memory_usedHeap_bytes` | Gauge | JVM heap usage |
| `base_cpu_processCpuLoad` | Gauge | CPU utilization |
| `base_thread_count` | Gauge | Active threads |

### Infrastructure (Node Exporter)

| Metric | Type | Description |
|--------|------|-------------|
| `node_cpu_seconds_total` | Counter | CPU time per mode |
| `node_memory_MemAvailable_bytes` | Gauge | Available memory |
| `node_disk_io_time_seconds_total` | Counter | Disk I/O time |
| `node_network_receive_bytes_total` | Counter | Network RX |

## Pre-configured Alerts

| Alert | Condition | Severity |
|-------|-----------|----------|
| LibertyServerDown | `up == 0` for 1m | critical |
| LibertyHighHeapUsage | Heap > 85% for 5m | warning |
| LibertyHighErrorRate | 5xx > 5% for 5m | warning |
| ECSLibertyTaskDown | Task unreachable for 1m | critical |
| ECSLibertyNoTasks | No tasks for 2m | critical |
| ECSLibertySlowResponses | p95 > 2s for 5m | warning |

## Common Tasks

### Import Grafana Dashboard
1. Log in to Grafana
2. Dashboards > Import > Upload JSON file
3. Select `monitoring/grafana/dashboards/ecs-liberty.json` or `k8s-liberty.json`

### Query Metrics (Prometheus)
```promql
# Request rate
rate(base_servlet_request_total[5m])

# 95th percentile response time
histogram_quantile(0.95, rate(base_servlet_request_elapsedTime_seconds_bucket[5m]))

# Heap usage percentage
base_memory_usedHeap_bytes / base_memory_maxHeap_bytes * 100
```

### Validate Alert Rules
```bash
promtool check rules /etc/prometheus/rules/*.yml
```

### Reload Configuration
```bash
curl -X POST http://localhost:9090/-/reload
```

## Troubleshooting

### Prometheus Not Scraping Targets
```bash
# Check target status
curl http://prometheus-ip:9090/api/v1/targets | jq '.data.activeTargets[] | {job, health}'

# Test metrics endpoint
curl http://target-ip:9080/metrics
```

### Alerts Not Firing
```bash
# Check alert rules loaded
curl http://prometheus-ip:9090/api/v1/rules

# Verify Alertmanager connection
curl http://prometheus-ip:9090/api/v1/alertmanagers
```

### ECS Discovery Not Working (AWS)
```bash
# SSH to monitoring server
sudo -u prometheus /usr/local/bin/ecs-discovery.sh
cat /etc/prometheus/targets/ecs-liberty.json
```

## Related Documentation

- [Monitoring Architecture](../docs/architecture/diagrams/monitoring-architecture.md)
- [End-to-End Testing](../docs/END_TO_END_TESTING.md)
- [AWS Deployment](../docs/AWS_DEPLOYMENT.md)
- [Local Kubernetes Deployment](../docs/LOCAL_KUBERNETES_DEPLOYMENT.md)
- [AlertManager Configuration](../docs/ALERTMANAGER_CONFIGURATION.md)
