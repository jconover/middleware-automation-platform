# Jenkins Standalone with Podman

Run Jenkins locally using Podman (or Docker) for development and testing.

## Prerequisites

- Podman or Docker installed
- podman-compose or docker-compose
- 4GB+ RAM available

## Quick Start

```bash
cd ci-cd/jenkins/podman

# Start Jenkins
podman-compose up -d

# Or with Docker
docker-compose up -d

# View logs
podman-compose logs -f jenkins
```

## Access Jenkins

- **URL**: http://localhost:8080
- **Username**: admin
- **Password**: JenkinsAdmin2024!

Wait 2-3 minutes for Jenkins to fully start and install plugins.

## Configuration

### Container Builds

The compose file mounts the Podman socket for container builds:

```yaml
volumes:
  - /run/user/1000/podman/podman.sock:/var/run/docker.sock
```

Adjust the path based on your system:
- **Rootless Podman**: `/run/user/$(id -u)/podman/podman.sock`
- **Root Podman**: `/run/podman/podman.sock`
- **Docker**: `/var/run/docker.sock`

### Environment Variables

Set these before starting:

```bash
export JENKINS_ADMIN_PASSWORD="YourSecurePassword"
export GITHUB_USERNAME="your-username"
export GITHUB_TOKEN="your-token"
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
```

### Persistence

Data is stored in a named volume `jenkins_home`. To backup:

```bash
podman volume export jenkins_home > jenkins_backup.tar
```

To restore:

```bash
podman volume import jenkins_home < jenkins_backup.tar
```

## Limitations

This standalone deployment has some limitations compared to Kubernetes:

| Feature | Standalone | Kubernetes |
|---------|------------|------------|
| Dynamic agents | No (fixed executors) | Yes (pod templates) |
| Scalability | Single node | Multi-node |
| Isolation | Shared executors | Container per build |
| Resource limits | Host-limited | Configurable per pod |

For production workloads or the full Jenkinsfile experience, use the Kubernetes deployment.

## Post-Installation Setup

### 1. Install Required Plugins

Navigate to **Manage Jenkins > Plugins > Available plugins**

Install:
- Pipeline
- Git
- Credentials Binding
- AWS Credentials (if using AWS)

### 2. Configure AWS Credentials

Go to **Manage Jenkins > Credentials > System > Global credentials**

Add:
- **Kind**: AWS Credentials
- **ID**: `aws-prod`
- **Access Key**: Your AWS access key
- **Secret Key**: Your AWS secret key

### 3. Create a Pipeline Job

1. Click **New Item**
2. Enter name: `middleware-platform`
3. Select **Pipeline**
4. Under **Pipeline**, select **Pipeline script from SCM**
5. Configure Git repository URL
6. Set **Script Path**: `ci-cd/Jenkinsfile`

## Running Builds

For standalone mode, modify the Jenkinsfile agent to use local executors:

```groovy
// Instead of:
agent {
    kubernetes { ... }
}

// Use:
agent any
```

Or create a simplified pipeline for local testing.

## Troubleshooting

### Jenkins not starting

Check logs:
```bash
podman-compose logs jenkins
```

### Container builds failing

Verify socket is accessible:
```bash
podman-compose exec jenkins ls -la /var/run/docker.sock
```

### Plugin installation issues

Access Jenkins at http://localhost:8080 and check **Manage Jenkins > System Log**.

### Permission denied

Ensure the socket has correct permissions:
```bash
# For rootless podman
systemctl --user enable --now podman.socket

# Check socket
ls -la /run/user/$(id -u)/podman/podman.sock
```

## Stop and Remove

```bash
# Stop containers
podman-compose down

# Stop and remove volumes (data loss!)
podman-compose down -v
```

## Upgrading

```bash
# Pull latest image
podman-compose pull

# Restart
podman-compose up -d
```
