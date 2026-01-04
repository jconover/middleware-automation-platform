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
  gnupg lsb-release \
  jq

# Install AWS CLI v2 (required for ECS service discovery)
cd /tmp
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip -q awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Create prometheus user
useradd --no-create-home --shell /bin/false prometheus

# Create directories
mkdir -p /etc/prometheus /var/lib/prometheus /etc/prometheus/targets
chown prometheus:prometheus /var/lib/prometheus

# Download and install Prometheus
# Note: Using 2.54.1 - official binaries don't include ecs_sd_configs,
# so we use file_sd_configs with a discovery script instead
PROM_VERSION="2.54.1"
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
        - targets: ['localhost:9093']

rule_files:
  - /etc/prometheus/rules/*.yml

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # ECS Liberty containers (file-based service discovery)
  # Targets file updated by /usr/local/bin/ecs-discovery.sh via cron
  - job_name: 'ecs-liberty'
    metrics_path: '/metrics'
    file_sd_configs:
      - files:
          - /etc/prometheus/targets/ecs-liberty.json
        refresh_interval: 30s
%{ if length(liberty_targets) > 0 }

  # EC2 Liberty instances (static targets)
  - job_name: 'liberty'
    metrics_path: '/metrics'
    static_configs:
      - targets: [%{ for i, target in liberty_targets }'${contains(target, ":") ? target : "${target}:9080"}'%{ if i < length(liberty_targets) - 1 }, %{ endif }%{ endfor }]
        labels:
          environment: 'production'
          deployment_type: 'ec2'

  - job_name: 'node'
    static_configs:
      - targets: [%{ for i, target in liberty_targets }'${split(":", target)[0]}:9100'%{ if i < length(liberty_targets) - 1 }, %{ endif }%{ endfor }]
        labels:
          environment: 'production'
%{ endif }
PROMEOF

# Create ECS service discovery script
cat <<'DISCOVERYEOF' > /usr/local/bin/ecs-discovery.sh
#!/bin/bash
# ECS Service Discovery Script
# Queries ECS for running tasks and creates Prometheus file_sd target file

CLUSTER="${ecs_cluster_name}"
REGION="${aws_region}"
OUTPUT_FILE="/etc/prometheus/targets/ecs-liberty.json"

# Get list of running tasks
TASK_ARNS=$(/usr/local/bin/aws ecs list-tasks --cluster $CLUSTER --service-name ${name_prefix}-liberty --desired-status RUNNING --region $REGION --query "taskArns[]" --output text 2>/dev/null)

if [ -z "$TASK_ARNS" ]; then
    echo "[]" > $OUTPUT_FILE
    exit 0
fi

# Describe tasks to get network info
TASKS=$(/usr/local/bin/aws ecs describe-tasks --cluster $CLUSTER --tasks $TASK_ARNS --region $REGION 2>/dev/null)

# Extract private IPs and build targets JSON
TARGETS=$(echo "$TASKS" | jq '
[.tasks[] |
  select(.lastStatus == "RUNNING") |
  {
    targets: [(.containers[0].networkInterfaces[0].privateIpv4Address + ":9080")],
    labels: {
      job: "ecs-liberty",
      ecs_cluster: (.clusterArn | split("/")[-1]),
      ecs_task_id: (.taskArn | split("/")[-1]),
      container_name: .containers[0].name,
      environment: "production",
      deployment_type: "ecs"
    }
  }
]')

echo "$TARGETS" > $OUTPUT_FILE
DISCOVERYEOF
chmod +x /usr/local/bin/ecs-discovery.sh

# Run initial discovery
/usr/local/bin/ecs-discovery.sh || echo "[]" > /etc/prometheus/targets/ecs-liberty.json

# Set up cron job to run discovery every minute
echo "* * * * * root /usr/local/bin/ecs-discovery.sh" > /etc/cron.d/ecs-discovery
chmod 644 /etc/cron.d/ecs-discovery

%{ else }
cat <<'PROMEOF' > /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['localhost:9093']

rule_files:
  - /etc/prometheus/rules/*.yml

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
%{ if length(liberty_targets) > 0 }

  - job_name: 'liberty'
    metrics_path: '/metrics'
    static_configs:
      - targets: [%{ for i, target in liberty_targets }'${contains(target, ":") ? target : "${target}:9080"}'%{ if i < length(liberty_targets) - 1 }, %{ endif }%{ endfor }]
        labels:
          environment: 'production'

  - job_name: 'node'
    static_configs:
      - targets: [%{ for i, target in liberty_targets }'${split(":", target)[0]}:9100'%{ if i < length(liberty_targets) - 1 }, %{ endif }%{ endfor }]
        labels:
          environment: 'production'
%{ endif }
PROMEOF
%{ endif }

chown prometheus:prometheus /etc/prometheus/prometheus.yml

# Create alert rules directory
mkdir -p /etc/prometheus/rules

%{ if ecs_enabled }
# Create ECS-specific alert rules
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
        # MicroProfile Metrics 5.0 uses mp_scope label instead of prefix
        expr: memory_usedHeap_bytes{job="ecs-liberty", mp_scope="base"} / memory_maxHeap_bytes{job="ecs-liberty", mp_scope="base"} > 0.85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High heap usage on ECS task {{ $labels.ecs_task_id }}"

      - alert: ECSLibertyHighErrorRate
        # MicroProfile Metrics 5.0 uses mp_scope label instead of prefix
        expr: |
          sum(rate(servlet_request_total{job="ecs-liberty", mp_scope="base", status=~"5.."}[5m]))
          /
          sum(rate(servlet_request_total{job="ecs-liberty", mp_scope="base"}[5m])) > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High 5xx error rate on ECS Liberty tasks"
RULESEOF
%{ endif }

%{ if length(liberty_targets) > 0 }
# Create EC2-specific alert rules
cat <<'RULESEOF' > /etc/prometheus/rules/ec2-alerts.yml
groups:
  - name: ec2-liberty
    rules:
      - alert: LibertyServerDown
        expr: up{job="liberty"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Liberty server {{ $labels.instance }} is down"

      - alert: LibertyHighHeapUsage
        expr: memory_usedHeap_bytes{job="liberty", mp_scope="base"} / memory_maxHeap_bytes{job="liberty", mp_scope="base"} > 0.85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High heap usage on Liberty server {{ $labels.instance }}"

      - alert: LibertyHighCPU
        expr: rate(cpu_processCpuTime_seconds_total{job="liberty"}[5m]) > 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on Liberty server {{ $labels.instance }}"

      - alert: NodeHighCPU
        expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on node {{ $labels.instance }}"

      - alert: NodeLowDisk
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 20
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Low disk space on node {{ $labels.instance }}"
RULESEOF
%{ endif }

chown -R prometheus:prometheus /etc/prometheus/rules

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
  --storage.tsdb.retention.time=${prometheus_retention_days}d

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable prometheus
systemctl start prometheus

# =============================================================================
# Install and Configure Alertmanager
# =============================================================================
echo "=== Installing Alertmanager ==="

ALERTMANAGER_VERSION="0.27.0"
cd /tmp
wget -q https://github.com/prometheus/alertmanager/releases/download/v$${ALERTMANAGER_VERSION}/alertmanager-$${ALERTMANAGER_VERSION}.linux-amd64.tar.gz
tar xzf alertmanager-$${ALERTMANAGER_VERSION}.linux-amd64.tar.gz
cd alertmanager-$${ALERTMANAGER_VERSION}.linux-amd64

cp alertmanager amtool /usr/local/bin/

# Create Alertmanager directories
mkdir -p /etc/alertmanager /var/lib/alertmanager /etc/alertmanager/secrets
chown -R prometheus:prometheus /etc/alertmanager /var/lib/alertmanager
chmod 700 /etc/alertmanager/secrets

# =============================================================================
# Fetch Slack webhook URL from Secrets Manager (if configured)
# =============================================================================
# Security measures:
#   - Webhook file permissions: 0600 (owner read/write only)
#   - Webhook file ownership: prometheus:prometheus
#   - Directory permissions: 0700 on /etc/alertmanager/secrets
#   - Process substitution used to avoid storing secret in shell variable
#   - No secret values logged to user-data.log
# =============================================================================
echo "Checking for AlertManager Slack webhook in Secrets Manager..."
ALERTMANAGER_SECRET_ID="${alertmanager_slack_secret_id}"
SLACK_CONFIGURED="false"

if [ -n "$ALERTMANAGER_SECRET_ID" ] && [ "$ALERTMANAGER_SECRET_ID" != "null" ]; then
  # Use process substitution to write directly to file without storing in variable
  # This reduces the window where the secret exists in shell memory
  if /usr/local/bin/aws secretsmanager get-secret-value \
      --secret-id "$ALERTMANAGER_SECRET_ID" \
      --region "${aws_region}" \
      --query SecretString \
      --output text 2>/dev/null | jq -r '.slack_webhook_url // empty' > /tmp/slack-webhook-temp; then

    # Validate we got a non-empty webhook URL
    if [ -s /tmp/slack-webhook-temp ] && grep -q "^https://" /tmp/slack-webhook-temp; then
      # Move to final location with secure permissions
      # Set permissions BEFORE moving to avoid race condition
      install -o prometheus -g prometheus -m 0600 /tmp/slack-webhook-temp /etc/alertmanager/secrets/slack-webhook
      echo "Slack webhook configured from Secrets Manager"
      SLACK_CONFIGURED="true"
    else
      echo "WARNING: Slack webhook not found or invalid in Secrets Manager"
    fi
    # Securely remove temp file
    rm -f /tmp/slack-webhook-temp
  else
    echo "WARNING: Failed to retrieve AlertManager secret from Secrets Manager"
  fi
else
  echo "WARNING: No AlertManager Slack secret ID configured"
fi

# Create Alertmanager config
if [ "$SLACK_CONFIGURED" = "true" ]; then
cat <<'AMEOF' > /etc/alertmanager/alertmanager.yml
# =============================================================================
# AlertManager Configuration - Deployed via Terraform
# =============================================================================
# Slack webhook is loaded from: /etc/alertmanager/secrets/slack-webhook
# To update: Store new webhook in AWS Secrets Manager, then redeploy or manually update the file
# =============================================================================

global:
  resolve_timeout: 5m
  slack_api_url_file: '/etc/alertmanager/secrets/slack-webhook'

route:
  receiver: 'default'
  group_by: ['alertname', 'severity']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h

  routes:
    - receiver: 'critical'
      match:
        severity: critical
      continue: false

    - receiver: 'warning'
      match:
        severity: warning
      continue: false

receivers:
  - name: 'default'
    slack_configs:
      - channel: '${alertmanager_config.slack_channel}'
        send_resolved: true
        title: '{{ .Status | toUpper }}: {{ .CommonLabels.alertname }}'
        text: >-
          {{ range .Alerts }}
          *Alert:* {{ .Labels.alertname }}
          *Severity:* {{ .Labels.severity | default "info" }}
          *Instance:* {{ .Labels.instance | default "N/A" }}
          *Description:* {{ .Annotations.description | default .Annotations.summary | default "No description" }}
          {{ end }}

  - name: 'critical'
    slack_configs:
      - channel: '${alertmanager_config.critical_channel}'
        send_resolved: true
        color: '{{ if eq .Status "firing" }}danger{{ else }}good{{ end }}'
        title: 'CRITICAL: {{ .CommonLabels.alertname }}'
        text: >-
          {{ range .Alerts }}
          *Alert:* {{ .Labels.alertname }}
          *Instance:* {{ .Labels.instance | default "N/A" }}
          *Description:* {{ .Annotations.description | default .Annotations.summary | default "No description" }}
          {{ end }}

  - name: 'warning'
    slack_configs:
      - channel: '${alertmanager_config.slack_channel}'
        send_resolved: true
        color: 'warning'
        title: 'WARNING: {{ .CommonLabels.alertname }}'

  - name: 'null'

inhibit_rules:
  - source_match:
      alertname: 'LibertyServerDown'
    target_match_re:
      alertname: 'Liberty.*'
    equal: ['instance']

  - source_match:
      alertname: 'ECSLibertyNoTasks'
    target_match:
      alertname: 'ECSLibertyTaskDown'
    equal: ['job']

  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname']
AMEOF
else
# No Slack webhook - create minimal config that logs alerts but doesn't send notifications
cat <<'AMEOF' > /etc/alertmanager/alertmanager.yml
# =============================================================================
# AlertManager Configuration - NO WEBHOOK CONFIGURED
# =============================================================================
# WARNING: Notifications are DISABLED because no Slack webhook was found.
#
# To enable notifications:
#   1. Create a secret in AWS Secrets Manager with:
#      {"slack_webhook_url": "https://hooks.slack.com/services/..."}
#   2. Update terraform.tfvars with the secret ARN
#   3. Redeploy or manually create /etc/alertmanager/secrets/slack-webhook
#
# See docs/ALERTMANAGER_CONFIGURATION.md for detailed setup instructions.
# =============================================================================

global:
  resolve_timeout: 5m

route:
  receiver: 'null'
  group_by: ['alertname', 'severity']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h

receivers:
  # Null receiver - alerts are processed but no notifications sent
  - name: 'null'
AMEOF
echo "WARNING: AlertManager installed but notifications are DISABLED (no webhook configured)"
fi

chown prometheus:prometheus /etc/alertmanager/alertmanager.yml
chmod 644 /etc/alertmanager/alertmanager.yml

# Create Alertmanager systemd service
cat <<'AMSVCEOF' > /etc/systemd/system/alertmanager.service
[Unit]
Description=Alertmanager
Documentation=https://prometheus.io/docs/alerting/alertmanager/
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/alertmanager \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --storage.path=/var/lib/alertmanager \
  --web.listen-address=0.0.0.0:9093 \
  --log.level=info
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5

NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/var/lib/alertmanager
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
AMSVCEOF

systemctl daemon-reload
systemctl enable alertmanager
systemctl start alertmanager

echo "Alertmanager installed and started on port 9093"

# Install Grafana
apt-get install -y software-properties-common
wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list
apt-get update
%{ if grafana_version == "latest" }
apt-get install -y grafana
%{ else }
apt-get install -y grafana=${grafana_version}
%{ endif }

# Fetch Grafana admin credentials from Secrets Manager
echo "Fetching Grafana credentials from Secrets Manager..."
GRAFANA_SECRET_ID="${grafana_credentials_secret_id}"
GRAFANA_CREDENTIALS=$(/usr/local/bin/aws secretsmanager get-secret-value \
  --secret-id "$GRAFANA_SECRET_ID" \
  --region "${aws_region}" \
  --query SecretString \
  --output text)

GRAFANA_ADMIN_USER=$(echo "$GRAFANA_CREDENTIALS" | jq -r '.admin_user')
GRAFANA_ADMIN_PASSWORD=$(echo "$GRAFANA_CREDENTIALS" | jq -r '.admin_password')

if [ -z "$GRAFANA_ADMIN_PASSWORD" ] || [ "$GRAFANA_ADMIN_PASSWORD" = "null" ]; then
  echo "ERROR: Failed to retrieve Grafana admin password from Secrets Manager"
  exit 1
fi

echo "Successfully retrieved Grafana credentials from Secrets Manager"

# Configure Grafana with credentials from Secrets Manager
cat <<GRAFEOF >> /etc/grafana/grafana.ini

[server]
http_addr = 0.0.0.0
http_port = 3000

[security]
admin_user = $GRAFANA_ADMIN_USER
admin_password = $GRAFANA_ADMIN_PASSWORD

[users]
allow_sign_up = false
GRAFEOF

# Clear sensitive variables from environment
unset GRAFANA_CREDENTIALS GRAFANA_ADMIN_PASSWORD

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
# Note: Grafana ECS dashboard must be imported manually (exceeds 16KB user-data limit)
# Dashboard JSON: monitoring/grafana/dashboards/ecs-liberty.json
# Import instructions: docs/plans/ecs-migration-plan.md (Section 6.3)
echo "=== Manual Step Required ==="
echo "Import ECS Grafana dashboard from: monitoring/grafana/dashboards/ecs-liberty.json"
echo "See docs/plans/ecs-migration-plan.md Section 6.3 for instructions"
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
echo "Prometheus:    http://<public-ip>:9090"
echo "Alertmanager:  http://<public-ip>:9093"
echo "Grafana:       http://<public-ip>:3000 (credentials stored in Secrets Manager)"
echo ""
echo "Retrieve Grafana password:"
echo "  aws secretsmanager get-secret-value --secret-id $GRAFANA_SECRET_ID --query SecretString --output text | jq -r .admin_password"
echo ""
if [ "$SLACK_CONFIGURED" = "true" ]; then
  echo "AlertManager: Slack notifications ENABLED"
else
  echo "AlertManager: Slack notifications DISABLED (no webhook configured)"
  echo "  To enable: Create secret in AWS Secrets Manager with slack_webhook_url, then redeploy"
  echo "  See docs/ALERTMANAGER_CONFIGURATION.md for instructions"
fi
%{ if ecs_enabled }
echo ""
echo "ECS Discovery: Running via cron every minute"
%{ endif }
