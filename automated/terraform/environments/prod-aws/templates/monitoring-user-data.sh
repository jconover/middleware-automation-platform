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
        - targets: []

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
TASK_ARNS=$(/usr/local/bin/aws ecs list-tasks --cluster $CLUSTER --service-name mw-prod-liberty --desired-status RUNNING --region $REGION --query "taskArns[]" --output text 2>/dev/null)

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
echo "Prometheus: http://<public-ip>:9090"
echo "Grafana: http://<public-ip>:3000 (credentials stored in Secrets Manager)"
echo "Retrieve password: aws secretsmanager get-secret-value --secret-id $GRAFANA_SECRET_ID --query SecretString --output text | jq -r .admin_password"
%{ if ecs_enabled }
echo "ECS Discovery: Running via cron every minute"
%{ endif }
