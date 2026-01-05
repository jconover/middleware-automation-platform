# Configuration Guide

This document explains how to configure the platform for your environment.

## Quick Links

| Environment       | Example File               | Your Config                           |
| ----------------- | -------------------------- | ------------------------------------- |
| Local Development | -                          | `automated/ansible/inventory/dev.yml` |
| AWS Terraform     | `terraform.tfvars.example` | `terraform.tfvars`                    |
| AWS Ansible       | `prod-aws.yml.example`     | `prod-aws.yml`                        |

### Setup Workflow

```bash
# Local Development - edit directly
vim automated/ansible/inventory/dev.yml

# AWS Production - copy examples first
cd automated/terraform/environments/prod-aws
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars

cd ../../ansible/inventory
cp prod-aws.yml.example prod-aws.yml
# After terraform apply, get values:
#   terraform output ansible_inventory
vim prod-aws.yml
```

---

## Local Development

### IP Address Configuration

All IP addresses are centralized in two files. Update these before deployment:

### 1. Ansible Inventory (`automated/ansible/inventory/dev.yml`)

This is the primary configuration file. Update these host IPs to match your servers:

```yaml
liberty_servers:
  hosts:
    liberty-dev-01:
      ansible_host: 192.168.68.86 # <-- Change to your Liberty server 1 IP
      liberty_server_name: appServer01
    liberty-dev-02:
      ansible_host: 192.168.68.88 # <-- Change to your Liberty server 2 IP
      liberty_server_name: appServer02

collective_controller:
  hosts:
    liberty-controller:
      ansible_host: 192.168.68.93 # <-- Change to your controller IP

database_servers:
  hosts:
    db-dev:
      ansible_host: 192.168.68.93 # <-- Change to your database server IP

load_balancers:
  hosts:
    lb-dev:
      ansible_host: 192.168.68.93 # <-- Change to your load balancer IP
      nginx_upstream_servers:
        - { host: "192.168.68.88", port: 9080 } # <-- Update to match Liberty IPs
        - { host: "192.168.68.86", port: 9080 }

monitoring_servers:
  hosts:
    monitoring-dev:
      ansible_host: 192.168.68.93 # <-- Change to your monitoring server IP
```

### 2. Prometheus Configuration (`monitoring/prometheus/prometheus.yml`)

Update the scrape targets to match your server IPs:

```yaml
scrape_configs:
  - job_name: "liberty"
    static_configs:
      - targets:
          - "192.168.68.88:9080" # <-- Liberty server 1
          - "192.168.68.86:9080" # <-- Liberty server 2

  - job_name: "node"
    static_configs:
      - targets:
          - "192.168.68.93:9100" # <-- Monitoring server
          - "192.168.68.88:9100" # <-- Liberty server 1
          - "192.168.68.86:9100" # <-- Liberty server 2

  - job_name: "jenkins"
    static_configs:
      - targets: ["192.168.68.206:8080"] # <-- Jenkins server (optional)
```

## Quick Setup Checklist

1. [ ] Update IPs in `automated/ansible/inventory/dev.yml`
2. [ ] Update IPs in `monitoring/prometheus/prometheus.yml`
3. [ ] Ensure SSH access: `ssh-copy-id ansible@<server-ip>`
4. [ ] Verify connectivity: `ansible -i automated/ansible/inventory/dev.yml all -m ping`
5. [ ] Run deployment: `./automated/scripts/deploy.sh --environment dev`

## Default Ports

| Service       | Port   | Protocol   |
| ------------- | ------ | ---------- |
| Liberty HTTP  | 9080   | HTTP       |
| Liberty HTTPS | 9443   | HTTPS      |
| Liberty Admin | 9060   | HTTPS      |
| Prometheus    | 9090   | HTTP       |
| Grafana       | 3000   | HTTP       |
| Node Exporter | 9100   | HTTP       |
| Alertmanager  | 9093   | HTTP       |
| NGINX         | 80/443 | HTTP/HTTPS |
| PostgreSQL    | 5432   | TCP        |
| Redis         | 6379   | TCP        |

## SSH Configuration

The inventory expects:

- SSH user: `ansible`
- SSH key: `~/.ssh/ansible_ed25519`

To change these, edit the `all.vars` section in the inventory file:

```yaml
all:
  vars:
    ansible_user: ansible # <-- SSH username
    ansible_ssh_private_key_file: ~/.ssh/ansible_ed25519 # <-- SSH key path
```

---

## AWS Production

### Terraform Configuration

Copy and edit the example file:

```bash
cd automated/terraform/environments/prod-aws
cp terraform.tfvars.example terraform.tfvars
```

### Key Variables (`terraform.tfvars`)

```hcl
# Region and naming
aws_region   = "us-east-1"
project_name = "middleware-platform"

# Compute - adjust instance size based on workload
liberty_instance_type  = "t3.small"   # 2 vCPU, 2GB (~$15/month)
liberty_instance_count = 2

# Database
db_instance_class = "db.t3.micro"     # (~$15/month)
db_name           = "appdb"
db_username       = "appuser"

# SSH key for EC2 access
ssh_public_key_path = "~/.ssh/ansible_ed25519.pub"

# HTTPS/TLS (optional)
# Option 1: No HTTPS
create_certificate = false

# Option 2: Create ACM certificate (requires DNS validation)
# create_certificate = true
# domain_name        = "app.example.com"

# Option 3: Use existing certificate
# certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc123"
```

### AWS Setup Checklist

1. [ ] AWS CLI configured: `aws configure`
2. [ ] Bootstrap state backend (one-time):
   ```bash
   cd automated/terraform/bootstrap
   terraform init && terraform apply
   ```
3. [ ] Copy and edit terraform.tfvars
4. [ ] Deploy infrastructure: `terraform init && terraform apply`
5. [ ] Note outputs: `terraform output`
6. [ ] Configure VPN or bastion access to private subnets
7. [ ] Run Ansible: `ansible-playbook -i inventory/prod-aws-ec2.yml playbooks/site.yml`

### Dynamic Inventory

AWS instances are auto-discovered using the `aws_ec2` plugin:

```bash
# List discovered hosts
ansible-inventory -i automated/ansible/inventory/prod-aws-ec2.yml --graph

# Ping all AWS hosts
ansible -i automated/ansible/inventory/prod-aws-ec2.yml all -m ping
```

**Requirements:**

- `pip install boto3 botocore`
- AWS credentials with EC2 read access

### Estimated Monthly Cost

| Resource                  | Type           | Cost          |
| ------------------------- | -------------- | ------------- |
| EC2 Instances (x2)        | t3.small       | ~$30          |
| RDS PostgreSQL            | db.t3.micro    | ~$15          |
| ElastiCache Redis         | cache.t3.micro | ~$12          |
| Application Load Balancer | -              | ~$20          |
| NAT Gateway               | -              | ~$35          |
| S3/CloudWatch             | -              | ~$10          |
| **TOTAL**                 |                | **~$122-137** |
