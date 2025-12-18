# Configuration Guide

This document explains how to configure the platform for your environment.

## IP Address Configuration

All IP addresses are centralized in two files. Update these before deployment:

### 1. Ansible Inventory (`automated/ansible/inventory/dev.yml`)

This is the primary configuration file. Update these host IPs to match your servers:

```yaml
liberty_servers:
  hosts:
    liberty-dev-01:
      ansible_host: 192.168.68.86    # <-- Change to your Liberty server 1 IP
      liberty_server_name: appServer01
    liberty-dev-02:
      ansible_host: 192.168.68.88    # <-- Change to your Liberty server 2 IP
      liberty_server_name: appServer02

collective_controller:
  hosts:
    liberty-controller:
      ansible_host: 192.168.68.82    # <-- Change to your controller IP

database_servers:
  hosts:
    db-dev:
      ansible_host: 192.168.68.82    # <-- Change to your database server IP

load_balancers:
  hosts:
    lb-dev:
      ansible_host: 192.168.68.82    # <-- Change to your load balancer IP
      nginx_upstream_servers:
        - { host: "192.168.68.88", port: 9080 }  # <-- Update to match Liberty IPs
        - { host: "192.168.68.86", port: 9080 }

monitoring_servers:
  hosts:
    monitoring-dev:
      ansible_host: 192.168.68.82    # <-- Change to your monitoring server IP
```

### 2. Prometheus Configuration (`monitoring/prometheus/prometheus.yml`)

Update the scrape targets to match your server IPs:

```yaml
scrape_configs:
  - job_name: 'liberty'
    static_configs:
      - targets:
          - '192.168.68.88:9080'    # <-- Liberty server 1
          - '192.168.68.86:9080'    # <-- Liberty server 2

  - job_name: 'node'
    static_configs:
      - targets:
          - '192.168.68.82:9100'    # <-- Monitoring server
          - '192.168.68.88:9100'    # <-- Liberty server 1
          - '192.168.68.86:9100'    # <-- Liberty server 2

  - job_name: 'jenkins'
    static_configs:
      - targets: ['192.168.68.206:8080']  # <-- Jenkins server (optional)
```

## Quick Setup Checklist

1. [ ] Update IPs in `automated/ansible/inventory/dev.yml`
2. [ ] Update IPs in `monitoring/prometheus/prometheus.yml`
3. [ ] Ensure SSH access: `ssh-copy-id ansible@<server-ip>`
4. [ ] Verify connectivity: `ansible -i automated/ansible/inventory/dev.yml all -m ping`
5. [ ] Run deployment: `./automated/scripts/deploy.sh --environment dev`

## Default Ports

| Service | Port | Protocol |
|---------|------|----------|
| Liberty HTTP | 9080 | HTTP |
| Liberty HTTPS | 9443 | HTTPS |
| Liberty Admin | 9060 | HTTPS |
| Prometheus | 9090 | HTTP |
| Grafana | 3000 | HTTP |
| Node Exporter | 9100 | HTTP |
| Alertmanager | 9093 | HTTP |
| NGINX | 80/443 | HTTP/HTTPS |
| PostgreSQL | 5432 | TCP |
| Redis | 6379 | TCP |

## SSH Configuration

The inventory expects:
- SSH user: `ansible`
- SSH key: `~/.ssh/ansible_ed25519`

To change these, edit the `all.vars` section in the inventory file:

```yaml
all:
  vars:
    ansible_user: ansible                              # <-- SSH username
    ansible_ssh_private_key_file: ~/.ssh/ansible_ed25519  # <-- SSH key path
```
