# Monitoring Role

Ansible role for deploying a complete monitoring stack with Prometheus, Grafana, and Node Exporter.

## Description

This role installs and configures a production-ready monitoring infrastructure:

- **Prometheus**: Time-series database for metrics collection and alerting
- **Grafana**: Visualization and dashboarding platform
- **Node Exporter**: Host-level metrics collection (CPU, memory, disk, network)

The stack is configured to monitor Open Liberty application servers and integrates with the broader enterprise middleware platform.

## Requirements

### Target System

- **Operating System**: Debian/Ubuntu Linux (APT-based package management)
- **Architecture**: x86_64 (amd64)
- **Privileges**: Root or sudo access required
- **Network**: Internet access for package downloads
- **Memory**: Minimum 2GB RAM recommended

### Control Node

- Ansible 2.12 or higher
- Python 3.8 or higher

## Role Variables

### Required Variables (Security-Critical)

| Variable | Description | Requirements |
|----------|-------------|--------------|
| `grafana_admin_password` | Grafana admin console password | Minimum 12 characters |

The password can be set via:
- Environment variable: `GRAFANA_ADMIN_PASSWORD`
- Extra vars: `-e "grafana_admin_password=YourPassword"`
- Ansible Vault

### Prometheus Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `prometheus_version` | `2.47.0` | Prometheus version to install |
| `prometheus_user` | `prometheus` | System user for Prometheus |
| `prometheus_install_dir` | `/opt/prometheus` | Binary installation directory |
| `prometheus_config_dir` | `/etc/prometheus` | Configuration file directory |
| `prometheus_data_dir` | `/var/lib/prometheus` | Time-series data storage |
| `prometheus_port` | `9090` | Web UI and API port |

### Grafana Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `grafana_version` | `10.1.0` | Grafana version to install |
| `grafana_port` | `3000` | Web UI port |
| `grafana_admin_user` | `admin` | Admin username |
| `grafana_admin_password` | (required) | Admin password (from env or vault) |

### Node Exporter Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `node_exporter_version` | `1.6.1` | Node Exporter version |
| `node_exporter_port` | `9100` | Metrics endpoint port |

### Alertmanager Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `alertmanager_version` | `0.26.0` | Alertmanager version |
| `alertmanager_port` | `9093` | Web UI and API port |

## Dependencies

This role has no dependencies on other Ansible Galaxy roles.

The role expects the following files to exist:

- `monitoring/prometheus/prometheus.yml` - Prometheus configuration
- `monitoring/prometheus/rules/` - Alert rule files (optional)

## Example Playbook

### Basic Installation

```yaml
---
- name: Deploy Monitoring Stack
  hosts: monitoring_servers
  become: true
  vars:
    grafana_admin_password: "{{ lookup('env', 'GRAFANA_ADMIN_PASSWORD') }}"
  roles:
    - common
    - monitoring
```

### Production with Custom Configuration

```yaml
---
- name: Deploy Monitoring Stack (Production)
  hosts: monitoring_servers
  become: true
  vars:
    prometheus_version: "2.47.0"
    prometheus_data_dir: /data/prometheus
    grafana_admin_password: !vault |
      $ANSIBLE_VAULT;1.1;AES256
      ...
    grafana_port: 3000
  roles:
    - common
    - monitoring
```

### Running the Playbook

```bash
# Using environment variable
export GRAFANA_ADMIN_PASSWORD='YourSecureP@ssw0rd123'
ansible-playbook -i inventory/prod.yml playbooks/site.yml --tags monitoring

# Using extra vars
ansible-playbook -i inventory/prod.yml playbooks/site.yml \
  -e "grafana_admin_password=YourSecureP@ssw0rd123" \
  --tags monitoring

# Using vault
ansible-playbook -i inventory/prod.yml playbooks/site.yml \
  --ask-vault-pass \
  --tags monitoring
```

## Grafana Access

### Default Credentials

- **URL**: `http://<server-ip>:3000`
- **Username**: `admin`
- **Password**: Set via `grafana_admin_password` variable

### First Login

1. Navigate to `http://<server-ip>:3000`
2. Log in with admin credentials
3. Prometheus datasource is pre-configured automatically
4. Import dashboards from `monitoring/grafana/dashboards/`

### Pre-configured Datasource

The role automatically provisions a Prometheus datasource:

- **Name**: Prometheus
- **Type**: Prometheus
- **URL**: `http://localhost:9090`
- **Access**: Server (default)

### Recommended Dashboards

Import these dashboard IDs from grafana.com:

| Dashboard ID | Name | Description |
|--------------|------|-------------|
| 1860 | Node Exporter Full | Comprehensive host metrics |
| 11074 | Node Exporter | Simplified node metrics |

For Liberty metrics, import: `monitoring/grafana/dashboards/ecs-liberty.json`

## Security Notes

### Password Validation

The role enforces password security at runtime:

1. Password must be defined (not empty)
2. Minimum length: 12 characters
3. Cannot be common defaults: `admin`, `password`, `changeme`, `grafana`

If requirements are not met, the playbook will fail with a clear error message.

### Setting a Secure Password

```bash
# Generate a secure password
openssl rand -base64 24

# Set as environment variable
export GRAFANA_ADMIN_PASSWORD='YourGeneratedSecurePassword'

# Or encrypt with Ansible Vault
ansible-vault encrypt_string 'YourSecureP@ssw0rd123' \
  --name 'grafana_admin_password' >> group_vars/all/vault.yml
```

### Network Security

- Grafana default port: 3000 (consider reverse proxy with HTTPS)
- Prometheus: 9090 (should not be exposed publicly)
- Node Exporter: 9100 (metrics endpoint, internal only)

For production, deploy behind a reverse proxy (nginx, ALB) with TLS termination.

## Handlers

| Handler | Description |
|---------|-------------|
| `Reload systemd` | Reloads systemd daemon after service file changes |
| `Restart Prometheus` | Restarts Prometheus service |
| `Restart Node Exporter` | Restarts Node Exporter service |
| `Restart Grafana` | Restarts Grafana server service |

## Directory Structure

After installation:

```
/opt/prometheus/             # Prometheus binaries
/etc/prometheus/             # Prometheus configuration
/etc/prometheus/rules/       # Alert rules
/var/lib/prometheus/         # Time-series data
/usr/local/bin/node_exporter # Node Exporter binary
/etc/grafana/                # Grafana configuration
/var/lib/grafana/            # Grafana data (dashboards, users)
```

## Service Management

```bash
# Prometheus
systemctl status prometheus
systemctl restart prometheus
journalctl -u prometheus -f

# Grafana
systemctl status grafana-server
systemctl restart grafana-server
journalctl -u grafana-server -f

# Node Exporter
systemctl status node_exporter
systemctl restart node_exporter
```

## Health Checks

The role verifies services are running:

| Service | Endpoint | Expected |
|---------|----------|----------|
| Prometheus | `http://localhost:9090/-/ready` | HTTP 200 |
| Grafana | `http://localhost:3000/api/health` | HTTP 200 |

Each check retries 6 times with 10-second intervals (1-minute timeout).

## Troubleshooting

### Common Issues

1. **Password validation fails**
   - Ensure password is at least 12 characters
   - Set via environment variable or extra vars

2. **Grafana fails to start**
   - Check: `journalctl -u grafana-server -n 50`
   - Verify port 3000 is not in use

3. **Prometheus data directory permissions**
   - Ensure prometheus user owns `/var/lib/prometheus`

4. **GPG key errors during installation**
   - The role uses modern signed-by repository format
   - Clear apt cache: `apt clean && apt update`

### Useful Commands

```bash
# Check Prometheus configuration
/opt/prometheus/promtool check config /etc/prometheus/prometheus.yml

# Query Prometheus directly
curl http://localhost:9090/api/v1/query?query=up

# Test Node Exporter
curl http://localhost:9100/metrics

# Check Grafana health
curl http://localhost:3000/api/health
```

## License

MIT

## Author

Enterprise Middleware Team
