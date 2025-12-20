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

chown prometheus:prometheus /etc/prometheus/prometheus.yml

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
DSEOF

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
