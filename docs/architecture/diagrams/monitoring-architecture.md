# Monitoring Architecture

This diagram shows the observability stack: Prometheus for metrics collection, Grafana for visualization, and Alertmanager for notifications.

## Monitoring Stack Overview

```mermaid
flowchart TB
    subgraph TARGETS["Metrics Sources"]
        subgraph ECS_TARGETS["ECS Fargate"]
            ECS1["Task 1<br/>/metrics :9080"]
            ECS2["Task 2<br/>/metrics :9080"]
            ECS3["Task N<br/>/metrics :9080"]
        end

        subgraph EC2_TARGETS["EC2 Instances"]
            EC2_1["Liberty #1<br/>/metrics :9080"]
            EC2_2["Liberty #2<br/>/metrics :9080"]
            NODE1["Node Exporter<br/>:9100"]
            NODE2["Node Exporter<br/>:9100"]
        end
    end

    subgraph MONITORING["Monitoring EC2 Instance"]
        PROM["Prometheus<br/>:9090"]
        GRAFANA["Grafana<br/>:3000"]
        ALERT["Alertmanager<br/>:9093"]
        DISCOVERY["ECS Discovery<br/>Script (cron)"]
    end

    subgraph NOTIFICATIONS["Notification Channels"]
        SLACK["Slack"]
        EMAIL["Email"]
    end

    DISCOVERY -->|"Update targets.json"| PROM
    PROM -->|"Scrape every 15s"| ECS1
    PROM -->|"Scrape every 15s"| ECS2
    PROM -->|"Scrape every 15s"| ECS3
    PROM -->|"Scrape every 15s"| EC2_1
    PROM -->|"Scrape every 15s"| EC2_2
    PROM -->|"Scrape every 15s"| NODE1
    PROM -->|"Scrape every 15s"| NODE2

    GRAFANA -->|"Query"| PROM
    PROM -->|"Fire alerts"| ALERT
    ALERT --> SLACK
    ALERT --> EMAIL

    style MONITORING fill:#fff3e0
    style TARGETS fill:#e3f2fd
```

## ECS Service Discovery

Since standard Prometheus doesn't include ECS service discovery, we use a file-based approach:

```mermaid
sequenceDiagram
    participant Cron as Cron Job
    participant Script as ecs-discovery.sh
    participant AWS as AWS ECS API
    participant File as targets.json
    participant Prom as Prometheus

    loop Every 60 seconds
        Cron->>Script: Execute
        Script->>AWS: ecs list-tasks
        AWS-->>Script: Task ARNs
        Script->>AWS: ecs describe-tasks
        AWS-->>Script: Task details (IPs)
        Script->>File: Write /etc/prometheus/targets/ecs-liberty.json
        Prom->>File: Reload targets
    end
```

## Metrics Flow

```mermaid
flowchart LR
    subgraph APP["Liberty Application"]
        MP["MicroProfile<br/>Metrics 5.0"]
        JVM["JVM Metrics"]
        HTTP["HTTP Metrics"]
        CUSTOM["Custom Metrics"]
    end

    subgraph ENDPOINT["/metrics Endpoint"]
        PROM_FMT["Prometheus Format<br/>text/plain"]
    end

    subgraph PROMETHEUS["Prometheus"]
        TSDB["Time Series DB"]
        RULES["Recording Rules"]
        ALERTS["Alert Rules"]
    end

    subgraph GRAFANA["Grafana"]
        DASH["Dashboards"]
        PANELS["Panels"]
    end

    MP --> PROM_FMT
    JVM --> PROM_FMT
    HTTP --> PROM_FMT
    CUSTOM --> PROM_FMT

    PROM_FMT -->|"Scrape"| TSDB
    TSDB --> RULES
    TSDB --> ALERTS
    TSDB -->|"PromQL"| DASH
    DASH --> PANELS
```

## Key Metrics Collected

### Application Metrics (MicroProfile Metrics 5.0)

MicroProfile Metrics 5.0 uses `mp_scope` label instead of metric prefixes:

| Metric | Type | Description |
|--------|------|-------------|
| `servlet_request_total{mp_scope="base"}` | Counter | Total HTTP requests |
| `servlet_request_elapsedTime_seconds{mp_scope="base"}` | Histogram | Request duration |
| `memory_usedHeap_bytes{mp_scope="base"}` | Gauge | JVM heap usage |
| `cpu_processCpuLoad{mp_scope="base"}` | Gauge | CPU utilization |
| `thread_count{mp_scope="base"}` | Gauge | Active threads |

### Infrastructure Metrics (Node Exporter)
| Metric | Type | Description |
|--------|------|-------------|
| `node_cpu_seconds_total` | Counter | CPU time |
| `node_memory_MemAvailable_bytes` | Gauge | Available memory |
| `node_disk_io_time_seconds_total` | Counter | Disk I/O time |
| `node_network_receive_bytes_total` | Counter | Network RX |

## Alert Configuration

```mermaid
flowchart TB
    subgraph ALERTS["Alert Rules"]
        A1["LibertyServerDown<br/>up == 0 for 1m"]
        A2["HighMemoryUsage<br/>heap > 90% for 5m"]
        A3["HighErrorRate<br/>5xx > 5% for 5m"]
        A4["SlowResponses<br/>p95 > 2s for 5m"]
    end

    subgraph ALERTMGR["Alertmanager"]
        ROUTE["Routing Rules"]
        GROUP["Grouping"]
        INHIBIT["Inhibition"]
    end

    subgraph NOTIFY["Notifications"]
        CRITICAL["#critical<br/>PagerDuty"]
        WARNING["#middleware-alerts<br/>Slack"]
    end

    A1 -->|"severity: critical"| ROUTE
    A2 -->|"severity: warning"| ROUTE
    A3 -->|"severity: critical"| ROUTE
    A4 -->|"severity: warning"| ROUTE

    ROUTE --> GROUP
    GROUP --> INHIBIT
    INHIBIT --> CRITICAL
    INHIBIT --> WARNING

    style ALERTS fill:#ffcdd2
    style ALERTMGR fill:#fff3e0
```

## Grafana Dashboard Overview

### Liberty Overview Dashboard
- Request rate (req/sec)
- Error rate (%)
- Response time percentiles (p50, p95, p99)
- Active connections
- JVM heap usage
- Thread pool utilization

### Infrastructure Dashboard
- CPU utilization per instance
- Memory usage
- Disk I/O
- Network throughput
- ECS task count

## Access Information

| Component | URL | Default Port |
|-----------|-----|--------------|
| Prometheus | http://monitoring-ip:9090 | 9090 |
| Grafana | http://monitoring-ip:3000 | 3000 |
| Alertmanager | http://monitoring-ip:9093 | 9093 |

Grafana credentials are stored in AWS Secrets Manager and can be retrieved with:
```bash
aws secretsmanager get-secret-value \
    --secret-id mw-prod-grafana-credentials \
    --query SecretString --output text | jq -r .admin_password
```
