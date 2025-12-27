# Common Role

Ansible role for baseline system configuration and common package installation.

## Description

This role provides foundational system setup tasks that should be applied to all managed hosts:

- Updates package cache (APT)
- Installs essential system utilities
- Configures system timezone
- Sets hostname based on inventory

This role is designed to be applied before other application-specific roles (e.g., liberty, monitoring).

## Requirements

### Target System

- **Operating System**: Debian/Ubuntu Linux (APT-based package management)
- **Privileges**: Root or sudo access required
- **Network**: Internet access for package downloads

### Control Node

- Ansible 2.12 or higher

## Role Variables

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `timezone` | `UTC` | System timezone (e.g., `America/New_York`, `Europe/London`) |

The hostname is automatically set from `inventory_hostname`.

## Installed Packages

The role installs the following system utilities:

| Package | Purpose |
|---------|---------|
| `curl` | HTTP client for API testing and downloads |
| `wget` | File download utility |
| `unzip` | Archive extraction |
| `vim` | Text editor |
| `htop` | Interactive process viewer |
| `jq` | JSON processing |
| `net-tools` | Network utilities (netstat, ifconfig) |
| `acl` | Access control list utilities |

## Dependencies

This role has no dependencies on other Ansible Galaxy roles.

## Example Playbook

### Basic Usage

```yaml
---
- name: Configure baseline system settings
  hosts: all
  become: true
  roles:
    - common
```

### With Custom Timezone

```yaml
---
- name: Configure baseline system settings
  hosts: all
  become: true
  vars:
    timezone: America/New_York
  roles:
    - common
```

### As Prerequisite for Other Roles

```yaml
---
- name: Deploy Application Stack
  hosts: app_servers
  become: true
  vars:
    timezone: UTC
  roles:
    - common
    - liberty
```

## Tasks Performed

1. **Update APT Cache**
   - Refreshes package index
   - Uses 1-hour cache validity to avoid redundant updates

2. **Install Common Packages**
   - Installs essential utilities listed above
   - Uses package module for cross-distribution compatibility

3. **Configure Timezone**
   - Sets system timezone via timedatectl
   - Defaults to UTC if not specified

4. **Set Hostname**
   - Configures hostname from inventory_hostname
   - Ensures consistent naming across infrastructure

## Idempotency

All tasks in this role are idempotent:

- APT cache update uses `cache_valid_time` to avoid unnecessary updates
- Package installation checks current state before changes
- Hostname task only modifies if different from current

## Example Inventory

```yaml
all:
  hosts:
    liberty-01:
      ansible_host: 192.168.1.10
    liberty-02:
      ansible_host: 192.168.1.11
    monitoring-01:
      ansible_host: 192.168.1.20
  vars:
    timezone: America/New_York
```

## Troubleshooting

### Common Issues

1. **APT cache update fails**
   - Check internet connectivity
   - Verify APT sources are valid
   - Run: `apt update` manually to see detailed errors

2. **Package installation fails**
   - Ensure sufficient disk space
   - Check for package conflicts

3. **Timezone not recognized**
   - List valid timezones: `timedatectl list-timezones`
   - Use exact timezone name (case-sensitive)

### Verification Commands

```bash
# Verify installed packages
dpkg -l curl wget unzip vim htop jq net-tools acl

# Check timezone
timedatectl

# Verify hostname
hostname
hostnamectl
```

## License

MIT

## Author

Enterprise Middleware Team
