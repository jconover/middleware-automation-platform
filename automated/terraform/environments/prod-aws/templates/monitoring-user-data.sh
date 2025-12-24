#!/bin/bash
set -e
exec > >(tee /var/log/user-data.log) 2>&1

echo "=== Starting Monitoring Server Setup ==="

# Update system
apt-get update
apt-get upgrade -y

# Install prerequisites
apt-get install -y \
  python3 python3-pip \
  curl wget unzip \
  apt-transport-https ca-certificates \
  gnupg lsb-release

# Create prometheus user
useradd --no-create-home --shell /bin/false prometheus

# Create directories
mkdir -p /etc/prometheus /var/lib/prometheus
chown prometheus:prometheus /var/lib/prometheus

# Download and install Prometheus
PROM_VERSION="2.48.0"
cd /tmp
wget -q https://github.com/prometheus/prometheus/releases/download/v$${PROM_VERSION}/prometheus-$${PROM_VERSION}.linux-amd64.tar.gz
tar xzf prometheus-$${PROM_VERSION}.linux-amd64.tar.gz
cd prometheus-$${PROM_VERSION}.linux-amd64

cp prometheus promtool /usr/local/bin/
cp -r consoles console_libraries /etc/prometheus/
chown -R prometheus:prometheus /etc/prometheus

# Create Prometheus config
%{ if ecs_enabled }
cat <<'PROMEOF' > /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: []

rule_files:
  - /etc/prometheus/rules/*.yml

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # ECS Liberty containers (dynamic discovery)
  - job_name: 'ecs-liberty'
    metrics_path: '/metrics'
    ecs_sd_configs:
      - region: '${aws_region}'
        cluster: '${ecs_cluster_name}'
        port: 9080
        refresh_interval: 30s
    relabel_configs:
      # Only keep running tasks
      - source_labels: [__meta_ecs_task_desired_status]
        regex: RUNNING
        action: keep
      # Add task ID as label
      - source_labels: [__meta_ecs_task_arn]
        regex: '.*/(.+)$'
        target_label: ecs_task_id
      # Add container name
      - source_labels: [__meta_ecs_container_name]
        target_label: container_name
      # Add cluster name
      - source_labels: [__meta_ecs_cluster_name]
        target_label: ecs_cluster
      # Add service name
      - source_labels: [__meta_ecs_service_name]
        target_label: ecs_service
      # Set environment label
      - target_label: environment
        replacement: 'production'
      # Set deployment type
      - target_label: deployment_type
        replacement: 'ecs'

  # EC2 Liberty instances (kept for rollback/comparison)
  - job_name: 'ec2-liberty'
    metrics_path: '/metrics'
    static_configs:
      - targets: ['${liberty1_ip}:9080', '${liberty2_ip}:9080']
        labels:
          environment: 'production'
          deployment_type: 'ec2'

  # Node exporter on EC2 instances
  - job_name: 'node'
    static_configs:
      - targets: ['${liberty1_ip}:9100', '${liberty2_ip}:9100']
        labels:
          environment: 'production'
PROMEOF
%{ else }
cat <<'PROMEOF' > /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: []

rule_files: []

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'liberty'
    metrics_path: '/metrics'
    static_configs:
      - targets: ['${liberty1_ip}:9080', '${liberty2_ip}:9080']
        labels:
          environment: 'production'

  - job_name: 'node'
    static_configs:
      - targets: ['${liberty1_ip}:9100', '${liberty2_ip}:9100']
        labels:
          environment: 'production'
PROMEOF
%{ endif }

chown prometheus:prometheus /etc/prometheus/prometheus.yml

%{ if ecs_enabled }
# Create alert rules directory and ECS-specific rules
mkdir -p /etc/prometheus/rules

cat <<'RULESEOF' > /etc/prometheus/rules/ecs-alerts.yml
groups:
  - name: ecs-liberty
    rules:
      - alert: ECSLibertyTaskDown
        expr: up{job="ecs-liberty"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "ECS Liberty task {{ $labels.ecs_task_id }} is down"

      - alert: ECSLibertyNoTasks
        expr: count(up{job="ecs-liberty"}) == 0 or absent(up{job="ecs-liberty"})
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "No ECS Liberty tasks are running"

      - alert: ECSLibertyHighHeapUsage
        expr: base_memory_usedHeap_bytes{job="ecs-liberty"} / base_memory_maxHeap_bytes{job="ecs-liberty"} > 0.85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High heap usage on ECS task {{ $labels.ecs_task_id }}"

      - alert: ECSLibertyHighErrorRate
        expr: |
          sum(rate(base_servlet_request_total{job="ecs-liberty", status=~"5.."}[5m]))
          /
          sum(rate(base_servlet_request_total{job="ecs-liberty"}[5m])) > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High 5xx error rate on ECS Liberty tasks"
RULESEOF

chown -R prometheus:prometheus /etc/prometheus/rules
%{ endif }

# Create Prometheus systemd service
cat <<'SVCEOF' > /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus/ \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries \
  --web.listen-address=0.0.0.0:9090 \
  --storage.tsdb.retention.time=15d

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable prometheus
systemctl start prometheus

# Install Grafana
apt-get install -y software-properties-common
wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list
apt-get update
apt-get install -y grafana

# Configure Grafana
cat <<'GRAFEOF' >> /etc/grafana/grafana.ini

[server]
http_addr = 0.0.0.0
http_port = 3000

[security]
admin_user = admin
admin_password = admin

[users]
allow_sign_up = false
GRAFEOF

# Add Prometheus as default datasource
mkdir -p /etc/grafana/provisioning/datasources
cat <<'DSEOF' > /etc/grafana/provisioning/datasources/prometheus.yml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
    editable: false
    uid: prometheus
DSEOF

%{ if ecs_enabled }
# Provision ECS Liberty dashboard
mkdir -p /etc/grafana/provisioning/dashboards
mkdir -p /var/lib/grafana/dashboards

cat <<'DBPROVEOF' > /etc/grafana/provisioning/dashboards/default.yml
apiVersion: 1
providers:
  - name: 'default'
    orgId: 1
    folder: 'ECS Monitoring'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    options:
      path: /var/lib/grafana/dashboards
DBPROVEOF

# Create ECS Liberty dashboard
cat <<'DASHEOF' > /var/lib/grafana/dashboards/ecs-liberty.json
{
  "annotations": {"list": []},
  "editable": true,
  "fiscalYearStartMonth": 0,
  "graphTooltip": 0,
  "id": null,
  "links": [],
  "liveNow": false,
  "panels": [
    {"collapsed": false, "gridPos": {"h": 1, "w": 24, "x": 0, "y": 0}, "id": 1, "panels": [], "title": "ECS Service Health", "type": "row"},
    {"datasource": {"type": "prometheus", "uid": "prometheus"}, "fieldConfig": {"defaults": {"color": {"mode": "thresholds"}, "mappings": [], "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": null}, {"color": "green", "value": 1}]}}, "overrides": []}, "gridPos": {"h": 4, "w": 6, "x": 0, "y": 1}, "id": 2, "options": {"colorMode": "value", "graphMode": "none", "justifyMode": "auto", "orientation": "auto", "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": false}, "textMode": "auto"}, "targets": [{"expr": "count(up{job=\"ecs-liberty\"} == 1)", "legendFormat": "Healthy Tasks", "refId": "A"}], "title": "Healthy ECS Tasks", "type": "stat"},
    {"datasource": {"type": "prometheus", "uid": "prometheus"}, "fieldConfig": {"defaults": {"color": {"mode": "thresholds"}, "mappings": [], "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "red", "value": 1}]}}, "overrides": []}, "gridPos": {"h": 4, "w": 6, "x": 6, "y": 1}, "id": 3, "options": {"colorMode": "value", "graphMode": "none", "justifyMode": "auto", "orientation": "auto", "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": false}, "textMode": "auto"}, "targets": [{"expr": "count(up{job=\"ecs-liberty\"} == 0) or vector(0)", "legendFormat": "Unhealthy", "refId": "A"}], "title": "Unhealthy ECS Tasks", "type": "stat"},
    {"datasource": {"type": "prometheus", "uid": "prometheus"}, "fieldConfig": {"defaults": {"color": {"mode": "palette-classic"}, "custom": {"axisCenteredZero": false, "axisColorMode": "text", "axisLabel": "", "axisPlacement": "auto", "barAlignment": 0, "drawStyle": "line", "fillOpacity": 10, "gradientMode": "none", "hideFrom": {"legend": false, "tooltip": false, "viz": false}, "lineInterpolation": "linear", "lineWidth": 1, "pointSize": 5, "scaleDistribution": {"type": "linear"}, "showPoints": "auto", "spanNulls": false, "stacking": {"group": "A", "mode": "none"}, "thresholdsStyle": {"mode": "off"}}, "mappings": [], "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}]}, "unit": "short"}, "overrides": []}, "gridPos": {"h": 8, "w": 12, "x": 12, "y": 1}, "id": 4, "options": {"legend": {"calcs": [], "displayMode": "list", "placement": "bottom", "showLegend": true}, "tooltip": {"mode": "single", "sort": "none"}}, "targets": [{"expr": "up{job=\"ecs-liberty\"}", "legendFormat": "{{ ecs_task_id }}", "refId": "A"}], "title": "ECS Task Status", "type": "timeseries"},
    {"collapsed": false, "gridPos": {"h": 1, "w": 24, "x": 0, "y": 9}, "id": 5, "panels": [], "title": "Request Metrics", "type": "row"},
    {"datasource": {"type": "prometheus", "uid": "prometheus"}, "fieldConfig": {"defaults": {"color": {"mode": "palette-classic"}, "custom": {"axisCenteredZero": false, "axisColorMode": "text", "axisLabel": "req/s", "axisPlacement": "auto", "barAlignment": 0, "drawStyle": "line", "fillOpacity": 10, "gradientMode": "none", "hideFrom": {"legend": false, "tooltip": false, "viz": false}, "lineInterpolation": "linear", "lineWidth": 1, "pointSize": 5, "scaleDistribution": {"type": "linear"}, "showPoints": "auto", "spanNulls": false, "stacking": {"group": "A", "mode": "none"}, "thresholdsStyle": {"mode": "off"}}, "mappings": [], "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}]}, "unit": "reqps"}, "overrides": []}, "gridPos": {"h": 8, "w": 12, "x": 0, "y": 10}, "id": 6, "options": {"legend": {"calcs": ["mean", "max"], "displayMode": "table", "placement": "bottom", "showLegend": true}, "tooltip": {"mode": "single", "sort": "none"}}, "targets": [{"expr": "sum(rate(base_servlet_request_total{job=\"ecs-liberty\"}[5m]))", "legendFormat": "Total Request Rate", "refId": "A"}], "title": "Request Rate (ECS)", "type": "timeseries"},
    {"datasource": {"type": "prometheus", "uid": "prometheus"}, "fieldConfig": {"defaults": {"color": {"mode": "palette-classic"}, "custom": {"axisCenteredZero": false, "axisColorMode": "text", "axisLabel": "%", "axisPlacement": "auto", "barAlignment": 0, "drawStyle": "line", "fillOpacity": 10, "gradientMode": "none", "hideFrom": {"legend": false, "tooltip": false, "viz": false}, "lineInterpolation": "linear", "lineWidth": 1, "pointSize": 5, "scaleDistribution": {"type": "linear"}, "showPoints": "auto", "spanNulls": false, "stacking": {"group": "A", "mode": "none"}, "thresholdsStyle": {"mode": "line+area"}}, "mappings": [], "max": 100, "min": 0, "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "red", "value": 5}]}, "unit": "percent"}, "overrides": []}, "gridPos": {"h": 8, "w": 12, "x": 12, "y": 10}, "id": 7, "options": {"legend": {"calcs": ["mean", "max"], "displayMode": "table", "placement": "bottom", "showLegend": true}, "tooltip": {"mode": "single", "sort": "none"}}, "targets": [{"expr": "100 * sum(rate(base_servlet_request_total{job=\"ecs-liberty\", status=~\"5..\"}[5m])) / sum(rate(base_servlet_request_total{job=\"ecs-liberty\"}[5m]))", "legendFormat": "5xx Error Rate", "refId": "A"}], "title": "Error Rate (ECS)", "type": "timeseries"},
    {"collapsed": false, "gridPos": {"h": 1, "w": 24, "x": 0, "y": 18}, "id": 8, "panels": [], "title": "JVM Metrics", "type": "row"},
    {"datasource": {"type": "prometheus", "uid": "prometheus"}, "fieldConfig": {"defaults": {"color": {"mode": "palette-classic"}, "custom": {"axisCenteredZero": false, "axisColorMode": "text", "axisLabel": "", "axisPlacement": "auto", "barAlignment": 0, "drawStyle": "line", "fillOpacity": 10, "gradientMode": "none", "hideFrom": {"legend": false, "tooltip": false, "viz": false}, "lineInterpolation": "linear", "lineWidth": 1, "pointSize": 5, "scaleDistribution": {"type": "linear"}, "showPoints": "auto", "spanNulls": false, "stacking": {"group": "A", "mode": "none"}, "thresholdsStyle": {"mode": "line+area"}}, "mappings": [], "max": 100, "min": 0, "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "yellow", "value": 70}, {"color": "red", "value": 85}]}, "unit": "percent"}, "overrides": []}, "gridPos": {"h": 8, "w": 12, "x": 0, "y": 19}, "id": 9, "options": {"legend": {"calcs": ["mean", "max"], "displayMode": "table", "placement": "bottom", "showLegend": true}, "tooltip": {"mode": "single", "sort": "none"}}, "targets": [{"expr": "100 * base_memory_usedHeap_bytes{job=\"ecs-liberty\"} / base_memory_maxHeap_bytes{job=\"ecs-liberty\"}", "legendFormat": "{{ ecs_task_id }}", "refId": "A"}], "title": "Heap Usage % (ECS Tasks)", "type": "timeseries"},
    {"datasource": {"type": "prometheus", "uid": "prometheus"}, "fieldConfig": {"defaults": {"color": {"mode": "palette-classic"}, "custom": {"axisCenteredZero": false, "axisColorMode": "text", "axisLabel": "", "axisPlacement": "auto", "barAlignment": 0, "drawStyle": "line", "fillOpacity": 10, "gradientMode": "none", "hideFrom": {"legend": false, "tooltip": false, "viz": false}, "lineInterpolation": "linear", "lineWidth": 1, "pointSize": 5, "scaleDistribution": {"type": "linear"}, "showPoints": "auto", "spanNulls": false, "stacking": {"group": "A", "mode": "none"}, "thresholdsStyle": {"mode": "off"}}, "mappings": [], "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}]}, "unit": "bytes"}, "overrides": []}, "gridPos": {"h": 8, "w": 12, "x": 12, "y": 19}, "id": 10, "options": {"legend": {"calcs": ["mean", "max"], "displayMode": "table", "placement": "bottom", "showLegend": true}, "tooltip": {"mode": "single", "sort": "none"}}, "targets": [{"expr": "base_memory_usedHeap_bytes{job=\"ecs-liberty\"}", "legendFormat": "Used - {{ ecs_task_id }}", "refId": "A"}, {"expr": "base_memory_maxHeap_bytes{job=\"ecs-liberty\"}", "legendFormat": "Max - {{ ecs_task_id }}", "refId": "B"}], "title": "Heap Memory (ECS)", "type": "timeseries"}
  ],
  "refresh": "30s",
  "schemaVersion": 38,
  "style": "dark",
  "tags": ["ecs", "liberty", "production"],
  "templating": {"list": []},
  "time": {"from": "now-1h", "to": "now"},
  "timepicker": {},
  "timezone": "browser",
  "title": "ECS Liberty Monitoring",
  "uid": "ecs-liberty-monitoring",
  "version": 1,
  "weekStart": ""
}
DASHEOF

chown -R grafana:grafana /var/lib/grafana/dashboards
%{ endif }

systemctl daemon-reload
systemctl enable grafana-server
systemctl start grafana-server

# Create ansible user
useradd -m -s /bin/bash ansible
mkdir -p /home/ansible/.ssh
cp /home/ubuntu/.ssh/authorized_keys /home/ansible/.ssh/
chown -R ansible:ansible /home/ansible/.ssh
chmod 700 /home/ansible/.ssh
chmod 600 /home/ansible/.ssh/authorized_keys
echo "ansible ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible

echo "=== Monitoring Server Setup Complete ==="
echo "Prometheus: http://<public-ip>:9090"
echo "Grafana: http://<public-ip>:3000 (admin/admin)"
echo ""
echo "NOTE: Update /etc/prometheus/prometheus.yml with Liberty server IPs"
