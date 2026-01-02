# Ansible Roles

This directory contains Ansible roles for the Middleware Automation Platform. The project uses an **AWS-first architecture** where managed services (RDS, ElastiCache, ALB) replace traditional on-premise components.

## Architecture Overview

```
AWS Production:
  Terraform provisions:
    - RDS PostgreSQL (replaces postgresql role)
    - ElastiCache Redis (replaces redis role)
    - Application Load Balancer (replaces nginx role)
    - EC2 instances for Liberty (when ecs_enabled=false)
    - EC2 instance for Prometheus/Grafana monitoring

  Ansible configures:
    - Liberty application servers (EC2 instances)
    - Prometheus, Grafana, Alertmanager (monitoring EC2)
    - Common system packages and configuration
```

## Active Roles

These roles contain production-ready code and are actively used:

| Role | Description |
|------|-------------|
| [common](#common) | Base system configuration applied to all managed hosts |
| [liberty](#liberty) | Open Liberty application server deployment and configuration |
| [monitoring](#monitoring) | Prometheus, Grafana, Alertmanager, and Node Exporter |

### common

Provides foundational system configuration for all managed hosts.

**Key tasks:**
- Install common system packages (curl, wget, jq, htop, etc.)
- Configure system timezone
- Set hostname

**Default variables:** See `common/defaults/main.yml`

### liberty

Deploys and configures Open Liberty application servers on EC2 instances.

**Key tasks:**
- Create Liberty service account and directories
- Install Java (OpenJDK 17 by default)
- Download and install Open Liberty
- Deploy server.xml configuration with security encoding
- Configure database connectivity (PostgreSQL JDBC)
- Configure session caching (Redisson for Redis/ElastiCache)
- Generate SSL certificates
- Deploy systemd service

**Security features:**
- Passwords validated for strength and common defaults rejected
- Keystore and admin passwords AES-encoded using Liberty's securityUtility
- Database credentials fetched from AWS Secrets Manager in production
- Sensitive tasks use `no_log: true`

**Required variables (via Ansible Vault):**
- `liberty_keystore_password` - Minimum 16 characters
- `liberty_admin_password` - Minimum 12 characters

**Default variables:** See `liberty/defaults/main.yml`

### monitoring

Deploys the complete monitoring stack for infrastructure observability.

**Components installed:**
- **Prometheus** - Metrics collection and storage
- **Grafana** - Visualization and dashboards
- **Alertmanager** - Alert routing and notifications (Slack, PagerDuty)
- **Node Exporter** - Host-level metrics

**Security features:**
- Grafana admin password validated for strength
- Webhook URLs stored in protected files with 0600 permissions
- Sensitive tasks use `no_log: true`

**Required variables:**
- `grafana_admin_password` - Minimum 12 characters (via `GRAFANA_ADMIN_PASSWORD` env var)

**Optional variables:**
- `alertmanager_slack_webhook_url` - For Slack notifications
- `alertmanager_pagerduty_key` - For PagerDuty integration

**Default variables:** See `monitoring/defaults/main.yml`

---

## Stub Roles (Not Executed)

> **WARNING:** These roles are placeholders that never execute. They exist for structural completeness and potential future on-premise support.

| Role | AWS Replacement | Terraform Resource |
|------|-----------------|-------------------|
| [postgresql](#postgresql-stub) | Amazon RDS | `database.tf` |
| [redis](#redis-stub) | Amazon ElastiCache | `database.tf` |
| [nginx](#nginx-stub) | Application Load Balancer | `loadbalancer.tf` |

### postgresql (STUB)

**Status:** Never executes (`when: false`)

PostgreSQL database functionality is provided by **Amazon RDS** in production. The RDS instance is provisioned via Terraform with:
- Automatic backups and point-in-time recovery
- Multi-AZ deployment option for high availability
- Credentials stored in AWS Secrets Manager

**See:** `automated/terraform/environments/prod-aws/database.tf`

### redis (STUB)

**Status:** Never executes (`when: false`)

Redis caching functionality is provided by **Amazon ElastiCache** in production. ElastiCache provides:
- Managed Redis cluster
- Automatic failover
- Integration with Liberty session caching via Redisson

**See:** `automated/terraform/environments/prod-aws/database.tf`

### nginx (STUB)

**Status:** Never executes (`when: false`)

Load balancing and reverse proxy functionality is provided by **AWS Application Load Balancer** in production. The ALB provides:
- SSL/TLS termination
- Health check routing
- Target group management for ECS and EC2
- Header-based routing for hybrid deployments

**See:** `automated/terraform/environments/prod-aws/loadbalancer.tf`

### Why Stubs Exist

1. **Role structure completeness** - Prevents errors when the role is referenced in playbooks
2. **Future on-premise support** - Provides extension points for non-AWS deployments
3. **Documentation** - Makes the AWS architecture decision explicit

---

## AWS Infrastructure (Terraform)

The managed services that replace the stub roles are defined in Terraform:

| Terraform File | Description |
|----------------|-------------|
| `database.tf` | RDS PostgreSQL and ElastiCache Redis |
| `loadbalancer.tf` | Application Load Balancer with target groups |
| `ecs.tf` | ECS Fargate cluster and service |
| `compute.tf` | EC2 instances for Liberty (when ECS disabled) |
| `monitoring.tf` | Prometheus/Grafana EC2 instance |

**Location:** `automated/terraform/environments/prod-aws/`

---

## Usage

### Running Playbooks

```bash
# Full site deployment (EC2 Liberty + Monitoring)
ansible-playbook -i automated/ansible/inventory/dev.yml \
  automated/ansible/playbooks/site.yml

# Specific role only
ansible-playbook -i automated/ansible/inventory/dev.yml \
  automated/ansible/playbooks/site.yml --tags liberty

# Dry run
ansible-playbook -i automated/ansible/inventory/dev.yml \
  automated/ansible/playbooks/site.yml --check
```

### Required Credentials

Before running playbooks, configure credentials as documented in `docs/CREDENTIAL_SETUP.md`:

```bash
# Grafana password (required for monitoring role)
export GRAFANA_ADMIN_PASSWORD='YourSecureP@ssw0rd'

# Slack notifications (optional)
export ALERTMANAGER_SLACK_WEBHOOK_URL='https://hooks.slack.com/services/...'

# Liberty passwords (via Ansible Vault)
ansible-vault encrypt_string 'YourStr0ng!P@ssw0rd#2024' --name 'liberty_keystore_password'
```

---

## Related Documentation

- [Credential Setup](../../../docs/CREDENTIAL_SETUP.md) - Required credential configuration
- [End-to-End Testing](../../../docs/END_TO_END_TESTING.md) - Testing guide for all environments
- [Terraform AWS Troubleshooting](../../../docs/troubleshooting/terraform-aws.md) - AWS deployment issues
