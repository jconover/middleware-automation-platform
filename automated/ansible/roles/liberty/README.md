# Liberty Role

Ansible role for installing and configuring IBM Open Liberty application server on Linux systems.

## Description

This role automates the deployment of Open Liberty with the following capabilities:

- Downloads and installs Open Liberty from IBM's public repository
- Creates a dedicated service account for running Liberty
- Configures server instances with customizable server.xml
- Sets up SSL/TLS certificates with secure keystore management
- Integrates with PostgreSQL databases via JDBC
- Configures Redis/ElastiCache session caching via JCache (Redisson)
- Creates systemd service for process management
- Supports MicroProfile Health endpoints for readiness checks

## Requirements

### Target System

- **Operating System**: Debian/Ubuntu Linux (APT-based package management)
- **Architecture**: x86_64 (amd64)
- **Privileges**: Root or sudo access required
- **Network**: Internet access to download Liberty and dependencies

### Control Node

- Ansible 2.12 or higher
- Python 3.8 or higher

## Role Variables

### Required Variables (Security-Critical)

These variables **must** be defined and meet security requirements. They should be stored in Ansible Vault.

| Variable | Description | Requirements |
|----------|-------------|--------------|
| `liberty_keystore_password` | Password for SSL keystore | Minimum 16 characters, stored in Vault |
| `liberty_admin_password` | Liberty admin console password | Minimum 12 characters, stored in Vault |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `liberty_version` | (required) | Open Liberty version to install (e.g., `24.0.0.1`) |
| `liberty_install_dir` | (required) | Installation directory (e.g., `/opt/liberty`) |
| `liberty_user` | `liberty` | Service account username |
| `liberty_server_name` | `defaultServer` | Liberty server instance name |
| `liberty_http_port` | `9080` | HTTP listener port |
| `liberty_https_port` | `9443` | HTTPS listener port |
| `liberty_java_version` | `17` | OpenJDK version to install |

### Database Configuration (Optional)

| Variable | Default | Description |
|----------|---------|-------------|
| `postgresql_host` | undefined | PostgreSQL server hostname |
| `postgresql_port` | `5432` | PostgreSQL port |
| `postgresql_database` | undefined | Database name |
| `postgresql_user` | undefined | Database username |
| `postgresql_password` | undefined | Database password (fetched from Secrets Manager in production) |
| `postgresql_jdbc_version` | `42.7.1` | PostgreSQL JDBC driver version |

### Cache Configuration (Optional)

| Variable | Default | Description |
|----------|---------|-------------|
| `redis_host` | undefined | Redis/ElastiCache endpoint |
| `redis_port` | `6379` | Redis port |
| `redisson_version` | `3.24.3` | Redisson JCache provider version |

### Environment Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `env_name` | undefined | Environment name (`development`, `production`) |
| `aws_region` | `us-east-1` | AWS region for Secrets Manager access |

## Dependencies

This role has no dependencies on other Ansible Galaxy roles.

For production deployments, the following infrastructure is typically required:

- PostgreSQL database (RDS or standalone)
- Redis/ElastiCache for session caching (optional)
- AWS Secrets Manager for credential storage (production only)

## Example Playbook

### Development Environment

```yaml
---
- name: Deploy Open Liberty (Development)
  hosts: liberty_servers
  become: true
  vars:
    liberty_version: "24.0.0.1"
    liberty_install_dir: /opt/liberty
    liberty_server_name: devServer
    liberty_keystore_password: !vault |
      $ANSIBLE_VAULT;1.1;AES256
      ...
    liberty_admin_password: !vault |
      $ANSIBLE_VAULT;1.1;AES256
      ...
  roles:
    - common
    - liberty
```

### Production Environment with Database

```yaml
---
- name: Deploy Open Liberty (Production)
  hosts: liberty_servers
  become: true
  vars:
    env_name: production
    liberty_version: "24.0.0.1"
    liberty_install_dir: /opt/liberty
    liberty_server_name: prodServer
    liberty_http_port: 9080
    liberty_https_port: 9443
    postgresql_host: "{{ lookup('aws_ssm', '/mw-prod/database/endpoint') }}"
    postgresql_database: middleware
    redis_host: "{{ lookup('aws_ssm', '/mw-prod/cache/endpoint') }}"
    liberty_keystore_password: !vault |
      $ANSIBLE_VAULT;1.1;AES256
      ...
    liberty_admin_password: !vault |
      $ANSIBLE_VAULT;1.1;AES256
      ...
  roles:
    - common
    - liberty
```

### Creating Vault-Encrypted Passwords

```bash
# Encrypt keystore password
ansible-vault encrypt_string 'YourStr0ng!K3yst0reP@ss#2024' \
  --name 'liberty_keystore_password' >> group_vars/all/vault.yml

# Encrypt admin password
ansible-vault encrypt_string 'SecureAdm1n#2024' \
  --name 'liberty_admin_password' >> group_vars/all/vault.yml
```

## Security Notes

### Credential Management

1. **Never hardcode passwords** in playbooks, inventory, or variable files
2. **Use Ansible Vault** for all sensitive variables
3. **AWS Secrets Manager** integration is available for production database credentials
4. All tasks handling secrets use `no_log: true` to prevent credential exposure in logs

### Password Requirements

| Credential | Minimum Length | Additional Requirements |
|------------|---------------|------------------------|
| `liberty_keystore_password` | 16 characters | Cannot be common defaults |
| `liberty_admin_password` | 12 characters | Cannot be common defaults |

The role will **fail immediately** if password requirements are not met.

### SSL/TLS Certificates

- Self-signed certificates are generated automatically for development
- For production, replace with CA-signed certificates
- Certificates are stored in `resources/security/key.p12`
- Keystore password is required for certificate generation

### File Permissions

- Server configuration files: `0640` (owner read/write, group read)
- Security directory: `0750` (owner full, group read/execute)
- Service files: `0644` (world readable, as required by systemd)

## Handlers

| Handler | Description |
|---------|-------------|
| `Reload systemd` | Reloads systemd daemon after service file changes |
| `Restart Liberty` | Restarts the Liberty server (async, 6-minute timeout) |

## Directory Structure

After installation, the following directories are created:

```
/opt/liberty/                    # Liberty installation
/opt/liberty/usr/servers/{name}/ # Server instance
/var/log/liberty/                # Log files
/var/liberty/apps/               # Application deployments
/var/liberty/config/             # Additional configuration
```

## Health Checks

The role waits for Liberty to be ready by checking the MicroProfile Health endpoint:

- **Endpoint**: `http://localhost:9080/health/ready`
- **Retries**: 12 attempts
- **Delay**: 10 seconds between attempts
- **Total timeout**: 2 minutes

## Troubleshooting

### Common Issues

1. **Password validation fails**: Ensure passwords meet minimum length requirements
2. **Liberty fails to start**: Check `/var/log/liberty/` for application logs
3. **Database connection fails**: Verify `postgresql_*` variables and network connectivity
4. **SSL certificate issues**: Regenerate certificates by removing `resources/security/key.p12`

### Useful Commands

```bash
# Check Liberty status
systemctl status liberty-{server_name}

# View Liberty logs
journalctl -u liberty-{server_name} -f

# Test health endpoint
curl http://localhost:9080/health/ready
```

## License

MIT

## Author

Enterprise Middleware Team
