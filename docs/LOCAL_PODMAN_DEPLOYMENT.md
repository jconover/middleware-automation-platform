# Local Podman Deployment Guide

Run the Middleware Automation Platform locally using Podman containers on a single machine without Kubernetes orchestration. This guide provides a lightweight development and testing environment that mirrors the production container architecture.

> **Note:** For multi-node Kubernetes deployments (e.g., Beelink homelab cluster), see [LOCAL_KUBERNETES_DEPLOYMENT.md](LOCAL_KUBERNETES_DEPLOYMENT.md). For AWS production deployments, see the main [README.md](../README.md).

---

## When to Use This vs Kubernetes

| Criteria | Use Podman (This Guide) | Use Kubernetes |
|----------|-------------------------|----------------|
| **Scenario** | Development, testing, demos | Production, multi-node, HA |
| **Infrastructure** | Single machine | Cluster (3+ nodes) |
| **Complexity** | Simple | Complex |
| **Resource overhead** | Minimal | Moderate |
| **Scaling** | Manual (start more containers) | Automatic (HPA, replicas) |
| **Service discovery** | Manual/DNS | Built-in (CoreDNS) |
| **Load balancing** | External (NGINX container) | Ingress controller |
| **Orchestration** | podman-compose / scripts | kubectl, Helm |

**Choose Podman when you need:**
- Quick local development environment
- Testing container images before pushing to registry
- Running demos without cluster setup
- CI/CD pipeline container builds
- Resource-constrained environments

**Choose Kubernetes when you need:**
- High availability and failover
- Auto-scaling based on load
- Multi-node distributed workloads
- Production-grade service mesh and ingress

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Build Liberty Container](#build-liberty-container)
3. [Run Liberty Container](#run-liberty-container)
4. [Run with Podman Compose](#run-with-podman-compose)
5. [Monitoring Setup](#monitoring-setup)
6. [Development Workflow](#development-workflow)
7. [Troubleshooting](#troubleshooting)
8. [Quick Reference](#quick-reference)

---

## Architecture

```
Single Host (Your Machine)
===========================================================================

    +-----------------+     +-----------------+     +-----------------+
    |   NGINX         |     |    Liberty      |     |    Liberty      |
    |   Container     |---->|   Container 1   |     |   Container 2   |
    |   :80/:443      |---->|   :9080/:9443   |     |   :9081/:9444   |
    +-----------------+     +-----------------+     +-----------------+
           |                        |                       |
           |                        +----------+------------+
           |                                   |
           |                                   v
           |                        +-----------------+
           |                        |   PostgreSQL    |
           |                        |   Container     |
           |                        |   :5432         |
           |                        +-----------------+
           |
    +------+--------------------------------------------------------+
    |                     Podman Network (liberty-net)              |
    +---------------------------------------------------------------+
           |
           v
    +-----------------+     +-----------------+     +-----------------+
    |   Prometheus    |     |    Grafana      |     |  Alertmanager   |
    |   Container     |---->|   Container     |     |   Container     |
    |   :9090         |     |   :3000         |     |   :9093         |
    +-----------------+     +-----------------+     +-----------------+

    Exposed Ports (localhost):
    - 80/443  : NGINX reverse proxy (optional)
    - 9080    : Liberty HTTP
    - 9443    : Liberty HTTPS
    - 5432    : PostgreSQL
    - 9090    : Prometheus
    - 3000    : Grafana
    - 9093    : Alertmanager
```

---

## Target Environment

This documentation is for local development workstations running:
- Linux (tested on Ubuntu 22.04+, Fedora 38+, RHEL 9+)
- macOS with Podman Machine
- Windows with WSL2 and Podman

---

## Prerequisites

Before building and running the Liberty container, ensure you have the following tools installed:

### Required Software

| Tool | Minimum Version | Purpose | Verify Command |
|------|-----------------|---------|----------------|
| Podman | 4.0+ | Container runtime | `podman --version` |
| Java | 17+ | Build sample application | `java --version` |
| Maven | 3.8+ | Build WAR file | `mvn --version` |
| Git | 2.30+ | Clone repository | `git --version` |

### Installing Prerequisites

#### Ubuntu/Debian

```bash
# Install Podman
sudo apt update
sudo apt install -y podman

# Install Java 17 (OpenJDK)
sudo apt install -y openjdk-17-jdk

# Install Maven
sudo apt install -y maven

# Install Git (usually pre-installed)
sudo apt install -y git
```

#### Fedora/RHEL/CentOS

```bash
# Install Podman (usually pre-installed on Fedora)
sudo dnf install -y podman

# Install Java 17
sudo dnf install -y java-17-openjdk-devel

# Install Maven
sudo dnf install -y maven

# Install Git
sudo dnf install -y git
```

#### macOS (with Homebrew)

```bash
# Install Podman
brew install podman

# Initialize and start Podman machine (required for macOS)
podman machine init
podman machine start

# Install Java 17
brew install openjdk@17
echo 'export PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

# Install Maven
brew install maven

# Install Git (usually pre-installed with Xcode CLI tools)
brew install git
```

### Verify Prerequisites

Run these commands to confirm all prerequisites are installed correctly:

```bash
# Check Podman version (must be 4.0+)
podman --version
# Expected output: podman version 4.x.x

# Check Java version (must be 17+)
java --version
# Expected output: openjdk 17.x.x or higher

# Check Maven version (must be 3.8+)
mvn --version
# Expected output: Apache Maven 3.8.x or higher

# Check Git version
git --version
# Expected output: git version 2.30.x or higher

# Verify Podman can pull images
podman pull hello-world
podman run hello-world
```

## Clone the Repository

If you have not already cloned the repository:

```bash
# Clone via HTTPS
git clone https://github.com/your-org/middleware-automation-platform.git

# Or clone via SSH
git clone git@github.com:your-org/middleware-automation-platform.git

# Navigate to the project root
cd middleware-automation-platform
```

## Build Liberty Container

This section walks through building the Liberty container image with the sample application.

### Step 1: Build the Sample Application WAR File

The sample application is a Jakarta EE 10 REST API that demonstrates Liberty's MicroProfile capabilities.

```bash
# Navigate to project root
cd /home/justin/Projects/middleware-automation-platform

# Build the WAR file
mvn -f sample-app/pom.xml clean package

# Verify the WAR was created
ls -la sample-app/target/sample-app.war
```

**Expected output:**

```
-rw-r--r-- 1 user user 12345 Dec 26 12:00 sample-app/target/sample-app.war
```

The build produces `sample-app.war` containing:
- **Jakarta EE 10 Web Profile** - Modern enterprise Java APIs
- **MicroProfile 6.0** - Cloud-native features (Health, Metrics, Config)
- **Java 17** - Latest LTS Java version

### Step 2: Copy WAR to Container Build Directory

The Containerfile expects application WAR files in the `apps/` subdirectory:

```bash
# Copy the WAR file to the container build context
cp sample-app/target/sample-app.war containers/liberty/apps/
```

### Step 3: Build the Liberty Container Image

Navigate to the container build directory and build the image:

```bash
# Change to the Liberty container directory
cd /home/justin/Projects/middleware-automation-platform/containers/liberty

# Build the container image
podman build -t liberty-app:1.0.0 -f Containerfile .
```

**Expected output:**

```
STEP 1/9: FROM icr.io/appcafe/open-liberty:kernel-slim-java17-openj9-ubi
...
STEP 9/9: EXPOSE 9080 9443
COMMIT liberty-app:1.0.0
--> abc123def456
Successfully tagged localhost/liberty-app:1.0.0
```

### Step 4: Verify the Image Was Created

Confirm the image exists in your local Podman image store:

```bash
# List images matching "liberty-app"
podman images | grep liberty-app
```

**Expected output:**

```
localhost/liberty-app    1.0.0    abc123def456    1 minute ago    550 MB
```

You can also inspect the image for details:

```bash
# Show image metadata
podman inspect liberty-app:1.0.0 | head -50

# Show image layers
podman history liberty-app:1.0.0
```

## Understanding the Containerfile

The Containerfile at `containers/liberty/Containerfile` defines how the Liberty container is built. Here is what each section does:

### Base Image

```dockerfile
FROM icr.io/appcafe/open-liberty:kernel-slim-java17-openj9-ubi
```

- **icr.io/appcafe/open-liberty** - Official IBM Container Registry image
- **kernel-slim** - Minimal Liberty runtime (features installed on demand)
- **java17** - Java 17 LTS runtime
- **openj9** - Eclipse OpenJ9 JVM (optimized for containers, lower memory footprint)
- **ubi** - Red Hat Universal Base Image (security-hardened, enterprise-ready)

### Health Check Dependencies

```dockerfile
USER root
RUN yum install -y curl && yum clean all
USER 1001
```

Installs `curl` for container health checks, then switches back to the non-root Liberty user (UID 1001) for security.

### Server Configuration

```dockerfile
COPY --chown=1001:0 server.xml /config/server.xml
COPY --chown=1001:0 jvm.options /config/jvm.options
```

Copies the Liberty server configuration files with proper ownership:
- **server.xml** - Liberty server configuration (features, endpoints, logging)
- **jvm.options** - JVM tuning parameters

### Feature Installation

```dockerfile
RUN features.sh
```

Runs Liberty's feature installation script, which reads `server.xml` and downloads the required features:

| Feature | Version | Purpose |
|---------|---------|---------|
| restfulWS | 3.1 | JAX-RS REST API support |
| jsonb | 3.0 | JSON binding for Java objects |
| cdi | 4.0 | Contexts and Dependency Injection |
| mpHealth | 4.0 | MicroProfile Health endpoints |
| mpMetrics | 5.0 | Prometheus-compatible metrics |
| mpConfig | 3.0 | Externalized configuration |
| jdbc | 4.3 | Database connectivity |
| ssl | 1.0 | HTTPS/TLS support |

### Application Deployment

```dockerfile
COPY --chown=1001:0 apps/*.war /config/apps/
```

Copies all WAR files from the build context to Liberty's application directory. Liberty auto-deploys applications from this location.

### Health Check

```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:9080/health/ready || exit 1
```

Configures container health checking:
- **interval=30s** - Check every 30 seconds
- **timeout=10s** - Fail if check takes more than 10 seconds
- **start-period=60s** - Allow 60 seconds for application startup
- **retries=3** - Mark unhealthy after 3 consecutive failures
- **Endpoint** - Uses MicroProfile Health `/health/ready` endpoint

### Exposed Ports

```dockerfile
EXPOSE 9080 9443
```

Documents the ports used by Liberty:
- **9080** - HTTP traffic
- **9443** - HTTPS traffic (SSL/TLS)

## Next Steps

After building the container image, you can:

1. **Run the container locally** - See the "Run Liberty Container" section (below)
2. **Push to a registry** - For Kubernetes or ECS deployment
3. **Deploy to Kubernetes** - See [LOCAL_KUBERNETES_DEPLOYMENT.md](LOCAL_KUBERNETES_DEPLOYMENT.md)

## Run Liberty Container

This section covers all the ways to run the Liberty container locally with Podman.

### Basic Run Command

Run the Liberty container with standard port mappings:

```bash
# Run in foreground (useful for debugging startup issues)
podman run --rm -p 9080:9080 -p 9443:9443 liberty-app:1.0.0

# Run in detached mode (background)
podman run -d --name liberty-server \
    -p 9080:9080 \
    -p 9443:9443 \
    liberty-app:1.0.0

# Verify container is running
podman ps

# View container logs
podman logs -f liberty-server
```

Access the application at these endpoints:

| Endpoint | URL | Description |
|----------|-----|-------------|
| Application | http://localhost:9080/sample-app | Main application |
| Health (Ready) | http://localhost:9080/health/ready | Readiness probe |
| Health (Live) | http://localhost:9080/health/live | Liveness probe |
| Health (Started) | http://localhost:9080/health/started | Startup probe |
| Metrics | http://localhost:9080/metrics | Prometheus metrics |
| HTTPS | https://localhost:9443/sample-app | Secure application access |

### Run with Environment Variables

Configure Liberty runtime behavior using environment variables:

```bash
# Basic logging configuration
podman run -d --name liberty-server \
    -p 9080:9080 \
    -p 9443:9443 \
    -e WLP_LOGGING_CONSOLE_FORMAT=JSON \
    -e WLP_LOGGING_CONSOLE_LOGLEVEL=INFO \
    -e WLP_LOGGING_CONSOLE_SOURCE=message,trace,accessLog,ffdc \
    liberty-app:1.0.0

# Application-specific environment variables
podman run -d --name liberty-server \
    -p 9080:9080 \
    -p 9443:9443 \
    -e DB_HOST=localhost \
    -e DB_PORT=5432 \
    -e DB_NAME=appdb \
    -e DB_USER=appuser \
    -e DB_PASSWORD=secret \
    -e CACHE_HOST=localhost \
    -e CACHE_PORT=6379 \
    liberty-app:1.0.0
```

Using an environment file for cleaner commands:

```bash
# Create environment file
cat > /tmp/liberty.env << 'EOF'
WLP_LOGGING_CONSOLE_FORMAT=JSON
WLP_LOGGING_CONSOLE_LOGLEVEL=INFO
DB_HOST=postgres
DB_PORT=5432
DB_NAME=appdb
DB_USER=appuser
DB_PASSWORD=secret
EOF

# Run with environment file
podman run -d --name liberty-server \
    -p 9080:9080 \
    -p 9443:9443 \
    --env-file /tmp/liberty.env \
    liberty-app:1.0.0
```

Common Liberty environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `WLP_LOGGING_CONSOLE_FORMAT` | Log format: `JSON` or `SIMPLE` | `SIMPLE` |
| `WLP_LOGGING_CONSOLE_LOGLEVEL` | Log level: `INFO`, `WARNING`, `SEVERE` | `INFO` |
| `WLP_OUTPUT_DIR` | Liberty output directory | `/opt/ibm/wlp/output` |
| `WLP_DEBUG_SUSPEND` | Suspend on debug: `y` or `n` | `y` |
| `WLP_DEBUG_ADDRESS` | Debug port | `7777` |

### Run with Volume Mounts for Development (Hot Reload)

Mount local directories for rapid development without rebuilding the container:

```bash
# Mount server.xml for configuration changes
podman run -d --name liberty-dev \
    -p 9080:9080 \
    -p 9443:9443 \
    -v /home/justin/Projects/middleware-automation-platform/containers/liberty/server.xml:/config/server.xml:Z \
    liberty-app:1.0.0

# Mount application directory for WAR hot deployment
podman run -d --name liberty-dev \
    -p 9080:9080 \
    -p 9443:9443 \
    -v /home/justin/Projects/middleware-automation-platform/containers/liberty/apps:/config/apps:Z \
    liberty-app:1.0.0

# Full development setup with all mounts
podman run -d --name liberty-dev \
    -p 9080:9080 \
    -p 9443:9443 \
    -v /home/justin/Projects/middleware-automation-platform/containers/liberty/server.xml:/config/server.xml:Z \
    -v /home/justin/Projects/middleware-automation-platform/containers/liberty/jvm.options:/config/jvm.options:Z \
    -v /home/justin/Projects/middleware-automation-platform/containers/liberty/apps:/config/apps:Z \
    liberty-app:1.0.0
```

**Hot reload workflow:**

```bash
# 1. Make changes to source code
# 2. Rebuild the WAR
mvn -f /home/justin/Projects/middleware-automation-platform/sample-app/pom.xml clean package

# 3. Copy new WAR to mounted apps directory
cp /home/justin/Projects/middleware-automation-platform/sample-app/target/*.war \
   /home/justin/Projects/middleware-automation-platform/containers/liberty/apps/

# 4. Liberty automatically detects and redeploys the application
# Watch the logs to see the redeployment
podman logs -f liberty-dev
```

> **Note:** The `:Z` suffix on volume mounts is required for SELinux systems (RHEL, Fedora) to relabel the content appropriately for container access.

### Run with Resource Limits

Control container resource usage for local testing that mimics production constraints:

```bash
# Memory and CPU limits (development)
podman run -d --name liberty-server \
    -p 9080:9080 \
    -p 9443:9443 \
    --memory=512m \
    --memory-reservation=256m \
    --cpus=1.0 \
    liberty-app:1.0.0

# Production-like limits (matches ECS task definition)
podman run -d --name liberty-server \
    -p 9080:9080 \
    -p 9443:9443 \
    --memory=1g \
    --memory-reservation=512m \
    --cpus=0.5 \
    liberty-app:1.0.0

# Strict memory limit (no swap)
podman run -d --name liberty-server \
    -p 9080:9080 \
    -p 9443:9443 \
    --memory=512m \
    --memory-swap=512m \
    --cpus=1.0 \
    liberty-app:1.0.0

# View resource usage in real-time
podman stats liberty-server
```

Resource limit recommendations:

| Environment | Memory | CPU | Memory Reservation |
|-------------|--------|-----|-------------------|
| Development | 512m | 1.0 | 256m |
| Testing | 1g | 1.0 | 512m |
| Production-like | 1g | 0.5 | 512m |

### Health Check Verification

Verify the Liberty container is healthy and ready to serve traffic:

```bash
# Check container health status
podman inspect liberty-server --format='{{.State.Health.Status}}'

# View health check logs
podman inspect liberty-server --format='{{range .State.Health.Log}}{{.Output}}{{end}}'

# Manual health endpoint verification
curl -f http://localhost:9080/health/ready
curl -f http://localhost:9080/health/live
curl -f http://localhost:9080/health/started

# Combined health check (all endpoints)
curl -s http://localhost:9080/health | jq .

# Check metrics endpoint
curl -s http://localhost:9080/metrics

# Wait for container to become healthy (useful in scripts)
timeout 120 bash -c 'until curl -sf http://localhost:9080/health/ready; do sleep 5; done'

# Continuous health monitoring
watch -n 5 'curl -s http://localhost:9080/health/ready | jq .'
```

Expected health check response:

```json
{
  "status": "UP",
  "checks": [
    {
      "name": "sample-app",
      "status": "UP",
      "data": {}
    }
  ]
}
```

### Stop and Remove Containers

```bash
# Stop the container
podman stop liberty-server

# Remove the container
podman rm liberty-server

# Stop and remove in one command
podman rm -f liberty-server

# Remove all stopped containers
podman container prune

# Remove the image
podman rmi liberty-app:1.0.0
```

## Run with Podman Compose

Use Podman Compose for multi-container deployments including Liberty, databases, and load balancing.

### Install Podman Compose

```bash
# Fedora/RHEL
sudo dnf install -y podman-compose

# Ubuntu/Debian
sudo apt install -y podman-compose

# Or via pip (any platform)
pip install podman-compose

# Verify installation
podman-compose --version
```

### Single Liberty Instance

Create a compose file for a basic Liberty deployment.

Create directory structure:

```bash
mkdir -p /home/justin/Projects/middleware-automation-platform/containers/liberty/compose
```

Create `/home/justin/Projects/middleware-automation-platform/containers/liberty/compose/docker-compose.yaml`:

```yaml
# Liberty Local Development Stack
# Run with: podman-compose up -d

services:
  liberty:
    build:
      context: ..
      dockerfile: Containerfile
    image: liberty-app:1.0.0
    container_name: liberty-server
    ports:
      - "9080:9080"
      - "9443:9443"
    environment:
      - WLP_LOGGING_CONSOLE_FORMAT=JSON
      - WLP_LOGGING_CONSOLE_LOGLEVEL=INFO
    volumes:
      - liberty-logs:/logs
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9080/health/ready"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    restart: unless-stopped
    networks:
      - liberty-net

volumes:
  liberty-logs:
    driver: local

networks:
  liberty-net:
    driver: bridge
```

Run the compose stack:

```bash
cd /home/justin/Projects/middleware-automation-platform/containers/liberty/compose

# Start the stack
podman-compose up -d

# View status
podman-compose ps

# View logs
podman-compose logs -f liberty

# Stop the stack
podman-compose down

# Stop and remove volumes
podman-compose down -v
```

### Running Multiple Liberty Instances

For load balancing testing or clustered deployments, create a multi-instance setup with NGINX load balancer.

Create `/home/justin/Projects/middleware-automation-platform/containers/liberty/compose/docker-compose-cluster.yaml`:

```yaml
# Liberty Cluster with Load Balancer
# Run with: podman-compose -f docker-compose-cluster.yaml up -d

services:
  liberty1:
    build:
      context: ..
      dockerfile: Containerfile
    image: liberty-app:1.0.0
    container_name: liberty1
    hostname: liberty1
    environment:
      - WLP_LOGGING_CONSOLE_FORMAT=JSON
      - INSTANCE_NAME=liberty1
    volumes:
      - liberty1-logs:/logs
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9080/health/ready"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    networks:
      - liberty-net

  liberty2:
    build:
      context: ..
      dockerfile: Containerfile
    image: liberty-app:1.0.0
    container_name: liberty2
    hostname: liberty2
    environment:
      - WLP_LOGGING_CONSOLE_FORMAT=JSON
      - INSTANCE_NAME=liberty2
    volumes:
      - liberty2-logs:/logs
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9080/health/ready"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    networks:
      - liberty-net

  liberty3:
    build:
      context: ..
      dockerfile: Containerfile
    image: liberty-app:1.0.0
    container_name: liberty3
    hostname: liberty3
    environment:
      - WLP_LOGGING_CONSOLE_FORMAT=JSON
      - INSTANCE_NAME=liberty3
    volumes:
      - liberty3-logs:/logs
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9080/health/ready"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    networks:
      - liberty-net

  nginx:
    image: nginx:alpine
    container_name: liberty-lb
    ports:
      - "8080:80"
      - "8443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro,Z
    depends_on:
      liberty1:
        condition: service_healthy
      liberty2:
        condition: service_healthy
      liberty3:
        condition: service_healthy
    networks:
      - liberty-net

volumes:
  liberty1-logs:
  liberty2-logs:
  liberty3-logs:

networks:
  liberty-net:
    driver: bridge
```

Create the NGINX load balancer configuration at `/home/justin/Projects/middleware-automation-platform/containers/liberty/compose/nginx.conf`:

```nginx
events {
    worker_connections 1024;
}

http {
    upstream liberty_cluster {
        least_conn;
        server liberty1:9080;
        server liberty2:9080;
        server liberty3:9080;
    }

    server {
        listen 80;

        location / {
            proxy_pass http://liberty_cluster;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location /health {
            proxy_pass http://liberty_cluster;
            proxy_connect_timeout 5s;
            proxy_read_timeout 10s;
        }
    }
}
```

Run the cluster:

```bash
cd /home/justin/Projects/middleware-automation-platform/containers/liberty/compose

# Start the cluster
podman-compose -f docker-compose-cluster.yaml up -d

# Verify all instances are running
podman-compose -f docker-compose-cluster.yaml ps

# Test load balancing (run multiple times to see different instances)
for i in {1..10}; do
    echo "Request $i:"
    curl -s http://localhost:8080/health/ready
    echo
done

# View logs from all instances
podman-compose -f docker-compose-cluster.yaml logs -f

# Stop the cluster
podman-compose -f docker-compose-cluster.yaml down
```

## Connecting to Databases

### PostgreSQL Container Setup

Create a full stack with Liberty and PostgreSQL for local development.

Create `/home/justin/Projects/middleware-automation-platform/containers/liberty/compose/docker-compose-full.yaml`:

```yaml
# Liberty Full Stack with PostgreSQL and Redis
# Run with: podman-compose -f docker-compose-full.yaml up -d

services:
  postgres:
    image: postgres:15-alpine
    container_name: liberty-postgres
    environment:
      POSTGRES_DB: appdb
      POSTGRES_USER: appuser
      POSTGRES_PASSWORD: appsecret
    ports:
      - "5432:5432"
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./init-db.sql:/docker-entrypoint-initdb.d/init-db.sql:ro,Z
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U appuser -d appdb"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - liberty-net

  redis:
    image: redis:7-alpine
    container_name: liberty-redis
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - liberty-net

  liberty:
    build:
      context: ..
      dockerfile: Containerfile
    image: liberty-app:1.0.0
    container_name: liberty-server
    ports:
      - "9080:9080"
      - "9443:9443"
    environment:
      - WLP_LOGGING_CONSOLE_FORMAT=JSON
      - WLP_LOGGING_CONSOLE_LOGLEVEL=INFO
      # Database configuration
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_NAME=appdb
      - DB_USER=appuser
      - DB_PASSWORD=appsecret
      # Cache configuration
      - CACHE_HOST=redis
      - CACHE_PORT=6379
    volumes:
      - liberty-logs:/logs
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9080/health/ready"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 90s
    networks:
      - liberty-net

volumes:
  postgres-data:
  redis-data:
  liberty-logs:

networks:
  liberty-net:
    driver: bridge
```

Create database initialization script at `/home/justin/Projects/middleware-automation-platform/containers/liberty/compose/init-db.sql`:

```sql
-- Initialize application database schema
CREATE TABLE IF NOT EXISTS app_config (
    id SERIAL PRIMARY KEY,
    key VARCHAR(255) UNIQUE NOT NULL,
    value TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS app_sessions (
    id VARCHAR(255) PRIMARY KEY,
    user_id VARCHAR(255),
    data JSONB,
    expires_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert default configuration
INSERT INTO app_config (key, value) VALUES
    ('app.name', 'Liberty Sample App'),
    ('app.version', '1.0.0'),
    ('app.environment', 'development')
ON CONFLICT (key) DO NOTHING;
```

Run the full stack:

```bash
cd /home/justin/Projects/middleware-automation-platform/containers/liberty/compose

# Start all services
podman-compose -f docker-compose-full.yaml up -d

# Check service status
podman-compose -f docker-compose-full.yaml ps

# View Liberty logs
podman-compose -f docker-compose-full.yaml logs -f liberty

# Connect to PostgreSQL directly
podman exec -it liberty-postgres psql -U appuser -d appdb

# Test database connection from Liberty
podman exec -it liberty-postgres psql -U appuser -d appdb -c "SELECT * FROM app_config;"

# Connect to Redis
podman exec -it liberty-redis redis-cli ping

# Stop all services
podman-compose -f docker-compose-full.yaml down

# Stop and remove all data volumes
podman-compose -f docker-compose-full.yaml down -v
```

### Connecting to External PostgreSQL

If you have an existing PostgreSQL instance running on the host or network:

```bash
# Using host network to connect to host's PostgreSQL
podman run -d --name liberty-server \
    --network host \
    -e DB_HOST=localhost \
    -e DB_PORT=5432 \
    -e DB_NAME=appdb \
    -e DB_USER=appuser \
    -e DB_PASSWORD=appsecret \
    liberty-app:1.0.0

# Using specific IP address
podman run -d --name liberty-server \
    -p 9080:9080 \
    -p 9443:9443 \
    -e DB_HOST=192.168.68.100 \
    -e DB_PORT=5432 \
    -e DB_NAME=appdb \
    -e DB_USER=appuser \
    -e DB_PASSWORD=appsecret \
    liberty-app:1.0.0

# Using host.containers.internal (Podman's host reference)
podman run -d --name liberty-server \
    -p 9080:9080 \
    -p 9443:9443 \
    -e DB_HOST=host.containers.internal \
    -e DB_PORT=5432 \
    -e DB_NAME=appdb \
    -e DB_USER=appuser \
    -e DB_PASSWORD=appsecret \
    liberty-app:1.0.0
```

### Liberty server.xml with DataSource Configuration

To use database connectivity, update `server.xml` to include JDBC configuration:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<server description="Liberty with PostgreSQL">
    <featureManager>
        <feature>restfulWS-3.1</feature>
        <feature>jsonb-3.0</feature>
        <feature>cdi-4.0</feature>
        <feature>mpHealth-4.0</feature>
        <feature>mpMetrics-5.0</feature>
        <feature>mpConfig-3.0</feature>
        <feature>jdbc-4.3</feature>
        <feature>ssl-1.0</feature>
    </featureManager>

    <httpEndpoint id="defaultHttpEndpoint" host="*"
                  httpPort="9080"
                  httpsPort="9443" />

    <mpHealth authentication="false"/>
    <mpMetrics authentication="false"/>

    <logging consoleLogLevel="INFO" consoleFormat="JSON"/>

    <!-- PostgreSQL JDBC Driver -->
    <library id="postgresLib">
        <fileset dir="/config/lib" includes="postgresql-*.jar"/>
    </library>

    <!-- PostgreSQL DataSource -->
    <dataSource id="DefaultDataSource" jndiName="jdbc/appdb">
        <jdbcDriver libraryRef="postgresLib"/>
        <properties.postgresql
            serverName="${env.DB_HOST}"
            portNumber="${env.DB_PORT}"
            databaseName="${env.DB_NAME}"
            user="${env.DB_USER}"
            password="${env.DB_PASSWORD}"/>
        <connectionManager maxPoolSize="20" minPoolSize="5"/>
    </dataSource>
</server>
```

Download and add the PostgreSQL JDBC driver:

```bash
# Create lib directory
mkdir -p /home/justin/Projects/middleware-automation-platform/containers/liberty/lib

# Download PostgreSQL JDBC driver
curl -L https://jdbc.postgresql.org/download/postgresql-42.7.1.jar \
    -o /home/justin/Projects/middleware-automation-platform/containers/liberty/lib/postgresql-42.7.1.jar

# Update Containerfile to include the driver (add before features.sh)
# COPY --chown=1001:0 lib/*.jar /config/lib/
```

## Troubleshooting

This section covers common issues you may encounter when running Liberty containers with Podman and provides solutions for each scenario.

### Container Won't Start

When a container fails to start, follow this diagnostic process:

**Step 1: Check container logs for error messages**

```bash
# View logs from the last run attempt
podman logs liberty-server

# View logs with timestamps for timing analysis
podman logs -t liberty-server

# Follow logs in real-time (if container is running but failing health checks)
podman logs -f liberty-server

# View the last 100 lines of logs
podman logs --tail 100 liberty-server
```

**Step 2: Check container exit code and state**

```bash
# View container status and exit code
podman ps -a --filter "name=liberty-server"

# Get detailed container state information
podman inspect liberty-server --format='{{.State.Status}} - Exit: {{.State.ExitCode}} - Error: {{.State.Error}}'

# View container events for startup failures
podman events --filter container=liberty-server --since 10m
```

**Step 3: Common startup errors and solutions**

| Error Message | Cause | Solution |
|---------------|-------|----------|
| `CWWKE0005E: The runtime environment could not be launched` | Missing or corrupt Liberty installation | Rebuild the image with `podman build --no-cache` |
| `CWWKZ0013E: The application could not be started` | Invalid WAR file or missing dependencies | Verify WAR was built successfully with `jar -tf sample-app.war` |
| `java.lang.OutOfMemoryError` | Insufficient heap memory | Increase memory limit with `--memory=1g` |
| `CWWKO0220E: TCP Channel defaultHttpEndpoint initialization did not succeed` | Port binding failed | Check for port conflicts (see Port Conflicts section) |
| `SRVE0190E: File not found` | Missing application resources | Verify WAR contents and server.xml paths |

**Step 4: Run container interactively for debugging**

```bash
# Start container with interactive shell (bypasses normal entrypoint)
podman run -it --rm --entrypoint /bin/bash liberty-app:1.0.0

# Inside the container, manually start Liberty
/opt/ibm/wlp/bin/server run defaultServer

# Check Liberty server configuration
/opt/ibm/wlp/bin/server validate defaultServer
```

### Port Conflicts

When ports 9080, 9443, or other required ports are already in use:

**Identify what is using the port:**

```bash
# Find process using specific ports (requires ss or netstat)
ss -tlnp | grep -E '9080|9443'

# Alternative using lsof
sudo lsof -i :9080
sudo lsof -i :9443

# Check if another container is using the port
podman ps --format "{{.Names}} {{.Ports}}" | grep -E '9080|9443'

# List all port mappings for running containers
podman ps --format "table {{.Names}}\t{{.Ports}}"
```

**Solutions for port conflicts:**

```bash
# Option 1: Stop the conflicting container
podman stop $(podman ps -q --filter "publish=9080")

# Option 2: Use different host ports
podman run -d --name liberty-server \
    -p 8080:9080 \
    -p 8443:9443 \
    liberty-app:1.0.0

# Option 3: Use random available ports
podman run -d --name liberty-server \
    -P liberty-app:1.0.0
# Then check assigned ports with: podman port liberty-server

# Option 4: Use host networking (container uses host ports directly)
podman run -d --name liberty-server \
    --network host \
    liberty-app:1.0.0
```

### Permission Issues (Rootless Podman, SELinux)

Podman runs rootless by default, which can cause permission issues with volume mounts and file access.

**SELinux volume mount errors:**

```bash
# Error: Permission denied when accessing mounted files
# Solution: Add :Z or :z suffix to volume mounts

# :Z - Private unshared label (for single container access)
podman run -d --name liberty-server \
    -p 9080:9080 \
    -v /path/to/server.xml:/config/server.xml:Z \
    liberty-app:1.0.0

# :z - Shared label (for multiple containers accessing same volume)
podman run -d --name liberty-server \
    -p 9080:9080 \
    -v /path/to/apps:/config/apps:z \
    liberty-app:1.0.0

# Alternative: Disable SELinux for the container (not recommended for production)
podman run -d --name liberty-server \
    --security-opt label=disable \
    liberty-app:1.0.0
```

**Check SELinux context of files:**

```bash
# View current SELinux context
ls -lZ /path/to/mounted/directory

# Manually set container-accessible context
sudo chcon -Rt container_file_t /path/to/mounted/directory
```

**Rootless Podman UID/GID mapping issues:**

```bash
# Check current user namespace mapping
podman unshare cat /proc/self/uid_map

# View effective user inside container
podman run --rm liberty-app:1.0.0 id

# Fix ownership for mounted volumes (map to container user 1001)
podman unshare chown 1001:0 /path/to/mounted/files

# Run container with specific user (if image supports it)
podman run -d --name liberty-server \
    --user 1001:0 \
    liberty-app:1.0.0
```

**Permission denied writing to volumes:**

```bash
# Create volume with correct permissions
podman volume create liberty-logs
podman run -d --name liberty-server \
    -v liberty-logs:/logs \
    liberty-app:1.0.0

# Or ensure host directory is writable by container user
mkdir -p /tmp/liberty-logs
chmod 777 /tmp/liberty-logs
podman run -d --name liberty-server \
    -v /tmp/liberty-logs:/logs:Z \
    liberty-app:1.0.0
```

### Network Connectivity Issues

**Containers cannot communicate with each other:**

```bash
# Ensure containers are on the same network
podman network ls
podman network inspect liberty-net

# Create a shared network if it doesn't exist
podman network create liberty-net

# Connect running container to network
podman network connect liberty-net liberty-server

# Verify container network configuration
podman inspect liberty-server --format='{{range .NetworkSettings.Networks}}{{.NetworkID}}{{end}}'

# Test connectivity between containers
podman exec liberty-server ping -c 3 postgres
podman exec liberty-server curl -v http://postgres:5432
```

**DNS resolution failures:**

```bash
# Check DNS resolution inside container
podman exec liberty-server nslookup postgres
podman exec liberty-server cat /etc/resolv.conf

# Verify container hostname is set correctly
podman exec liberty-server hostname

# Use explicit IP if DNS fails
POSTGRES_IP=$(podman inspect postgres --format='{{.NetworkSettings.IPAddress}}')
podman exec liberty-server curl -v http://${POSTGRES_IP}:5432
```

**Cannot reach external services from container:**

```bash
# Test external connectivity
podman exec liberty-server curl -v https://google.com

# Check firewall rules (Linux)
sudo iptables -L -n | grep -i drop
sudo firewall-cmd --list-all

# Try with host networking to bypass Podman networking
podman run -d --name liberty-server \
    --network host \
    liberty-app:1.0.0
```

**macOS/Windows: Connecting to host services:**

```bash
# Use special hostname to reach host from container
# macOS/Windows with Podman Machine:
podman run -d --name liberty-server \
    -e DB_HOST=host.containers.internal \
    liberty-app:1.0.0

# Verify host.containers.internal resolves
podman exec liberty-server ping -c 1 host.containers.internal
```

### Image Build Failures

**WAR file not found during build:**

```
COPY --chown=1001:0 apps/*.war /config/apps/
error: pattern "apps/*.war" matched no files
```

```bash
# Solution: Build the application and copy WAR file first
mvn -f sample-app/pom.xml clean package
cp sample-app/target/sample-app.war containers/liberty/apps/

# Verify WAR file exists
ls -la containers/liberty/apps/*.war
```

**Base image pull failures:**

```bash
# Check network connectivity to registry
curl -I https://icr.io/v2/

# Try pulling image directly
podman pull icr.io/appcafe/open-liberty:kernel-slim-java17-openj9-ubi

# Check available tags if specific tag fails
podman search icr.io/appcafe/open-liberty --list-tags

# Use alternative registry mirror (if available)
podman pull docker.io/openliberty/open-liberty:kernel-slim-java17-openj9-ubi

# Clear podman cache and retry
podman system prune -a
podman build --no-cache -t liberty-app:1.0.0 -f Containerfile .
```

**Build fails during feature installation:**

```bash
# View detailed build output
podman build --progress=plain -t liberty-app:1.0.0 -f Containerfile .

# Check for typos in server.xml feature names
# Common issues: wrong version numbers, deprecated feature names

# Build with increased timeout for slow networks
podman build --timeout 600 -t liberty-app:1.0.0 -f Containerfile .
```

**Disk space issues during build:**

```bash
# Check available disk space
df -h

# View Podman disk usage
podman system df

# Clean up unused images and build cache
podman image prune -a
podman builder prune -a

# Clean up everything (containers, images, volumes)
podman system prune -a --volumes
```

### Out of Memory Errors

**JVM heap exhaustion:**

```bash
# Error: java.lang.OutOfMemoryError: Java heap space

# Solution 1: Increase container memory limit
podman run -d --name liberty-server \
    --memory=1g \
    --memory-swap=1g \
    liberty-app:1.0.0

# Solution 2: Tune JVM heap settings via jvm.options
# Create or edit jvm.options file:
cat > jvm.options << 'EOF'
-Xms256m
-Xmx512m
-XX:MaxMetaspaceSize=256m
EOF

# Mount jvm.options into container
podman run -d --name liberty-server \
    --memory=1g \
    -v $(pwd)/jvm.options:/config/jvm.options:Z \
    liberty-app:1.0.0
```

**Monitor container memory usage:**

```bash
# Real-time memory statistics
podman stats liberty-server

# Get memory limit and current usage
podman inspect liberty-server --format='Limit: {{.HostConfig.Memory}} Used: {{.State.OOMKilled}}'

# Check if container was OOM killed
podman inspect liberty-server --format='{{.State.OOMKilled}}'

# View container memory events
podman events --filter container=liberty-server --filter event=oom
```

**OpenJ9-specific memory tuning:**

```bash
# OpenJ9 has different memory characteristics than HotSpot
# Use -Xshareclasses for class data sharing (reduces memory)
cat > jvm.options << 'EOF'
-Xms256m
-Xmx512m
-Xshareclasses:cacheDir=/output/.classCache
-Xtune:virtualized
EOF

# -Xtune:virtualized optimizes for containerized environments
```

### Health Check Failures

**Container health check failing after startup:**

```bash
# Check current health status
podman inspect liberty-server --format='{{.State.Health.Status}}'

# View health check log
podman inspect liberty-server --format='{{range .State.Health.Log}}Exit: {{.ExitCode}} Output: {{.Output}}{{end}}'

# Manually test health endpoint
curl -f http://localhost:9080/health/ready
curl -f http://localhost:9080/health/live
curl -f http://localhost:9080/health/started
```

**Common health check failure causes and solutions:**

| Symptom | Cause | Solution |
|---------|-------|----------|
| Connection refused | Application not started yet | Increase `start_period` in health check |
| 404 Not Found | Health feature not enabled | Add `mpHealth-4.0` to server.xml features |
| 503 Service Unavailable | Application unhealthy | Check application logs for errors |
| Timeout | Slow startup or overloaded | Increase `timeout` and `start_period` |
| curl not found | Missing curl in container | Ensure Containerfile installs curl |

**Adjust health check timing:**

```bash
# Run with longer health check intervals for slow-starting applications
podman run -d --name liberty-server \
    -p 9080:9080 \
    --health-cmd="curl -f http://localhost:9080/health/ready || exit 1" \
    --health-interval=30s \
    --health-timeout=15s \
    --health-start-period=120s \
    --health-retries=5 \
    liberty-app:1.0.0
```

**Disable health check for debugging:**

```bash
# Run without health check to troubleshoot startup
podman run -d --name liberty-debug \
    -p 9080:9080 \
    --no-healthcheck \
    liberty-app:1.0.0

# Wait for manual verification
sleep 60
curl http://localhost:9080/health/ready
```

### Database Connection Errors

**Cannot connect to PostgreSQL from Liberty:**

```bash
# Verify PostgreSQL is running
podman exec -it liberty-postgres pg_isready

# Test network connectivity from Liberty container
podman exec -it liberty-server curl -v telnet://postgres:5432

# Check DNS resolution
podman exec -it liberty-server nslookup postgres

# Verify database credentials
podman exec -it liberty-postgres psql -U appuser -d appdb -c "SELECT 1;"
```

**Connection refused with host network:**

```bash
# Ensure PostgreSQL is listening on all interfaces
# In postgresql.conf: listen_addresses = '*'

# Check pg_hba.conf allows container connections
# Add: host all all 0.0.0.0/0 md5
```

### Debug Mode

Run Liberty with debug enabled for troubleshooting:

```bash
podman run -d --name liberty-debug \
    -p 9080:9080 \
    -p 9443:9443 \
    -p 7777:7777 \
    -e WLP_DEBUG_SUSPEND=n \
    -e WLP_DEBUG_ADDRESS=7777 \
    liberty-app:1.0.0

# Connect your IDE debugger to localhost:7777
```

## Monitoring Setup

This section covers setting up Prometheus and Grafana locally to monitor Liberty metrics.

### Running Prometheus Container

Prometheus scrapes metrics from Liberty's `/metrics` endpoint (MicroProfile Metrics 5.0).

#### Create Local Prometheus Configuration

Create a configuration file for local development that targets your Liberty container:

```bash
# Create Prometheus config directory
mkdir -p /home/justin/Projects/middleware-automation-platform/monitoring/prometheus/local

# Create local Prometheus configuration
cat > /home/justin/Projects/middleware-automation-platform/monitoring/prometheus/local/prometheus-local.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'liberty'
    metrics_path: /metrics
    static_configs:
      - targets: ['host.containers.internal:9080']
        labels:
          environment: 'local'
          instance_name: 'liberty-local'
EOF
```

> **Note:** `host.containers.internal` allows Prometheus (running in a container) to reach Liberty (also in a container or on the host). If both containers are on the same Podman network, use the container name instead (e.g., `liberty-server:9080`).

#### Run Prometheus Container

```bash
# Run Prometheus with local configuration
podman run -d --name prometheus \
    -p 9090:9090 \
    -v /home/justin/Projects/middleware-automation-platform/monitoring/prometheus/local/prometheus-local.yml:/etc/prometheus/prometheus.yml:ro,Z \
    prom/prometheus:latest

# Verify Prometheus is running
podman ps | grep prometheus

# Check Prometheus logs
podman logs prometheus
```

#### Prometheus on Same Network as Liberty

For containers on the same Podman network, use container names for service discovery:

```bash
# Create a shared network
podman network create monitoring-net

# Run Liberty on the network
podman run -d --name liberty-server \
    --network monitoring-net \
    -p 9080:9080 \
    -p 9443:9443 \
    liberty-app:1.0.0

# Create Prometheus config for container network
cat > /home/justin/Projects/middleware-automation-platform/monitoring/prometheus/local/prometheus-network.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'liberty'
    metrics_path: /metrics
    static_configs:
      - targets: ['liberty-server:9080']
        labels:
          environment: 'local'
          instance_name: 'liberty-local'
EOF

# Run Prometheus on the same network
podman run -d --name prometheus \
    --network monitoring-net \
    -p 9090:9090 \
    -v /home/justin/Projects/middleware-automation-platform/monitoring/prometheus/local/prometheus-network.yml:/etc/prometheus/prometheus.yml:ro,Z \
    prom/prometheus:latest
```

#### Verify Prometheus is Scraping Liberty Metrics

```bash
# Open Prometheus UI
echo "Open http://localhost:9090 in your browser"

# Check targets status via API
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health, lastScrape: .lastScrape}'

# Query Liberty metrics
curl -s 'http://localhost:9090/api/v1/query?query=base_cpu_processCpuLoad' | jq .

# Check if Liberty target is up
curl -s 'http://localhost:9090/api/v1/query?query=up{job="liberty"}' | jq '.data.result[].value[1]'
```

Access Prometheus UI at **http://localhost:9090**. Navigate to Status > Targets to verify Liberty is being scraped successfully.

### Running Grafana Container

Grafana provides dashboards for visualizing Liberty metrics collected by Prometheus.

#### Run Grafana Container

```bash
# Run Grafana with persistent storage
podman run -d --name grafana \
    --network monitoring-net \
    -p 3000:3000 \
    -v grafana-data:/var/lib/grafana \
    -e GF_SECURITY_ADMIN_USER=admin \
    -e GF_SECURITY_ADMIN_PASSWORD=admin \
    grafana/grafana:latest

# Verify Grafana is running
podman ps | grep grafana

# Check Grafana logs
podman logs grafana
```

Access Grafana at **http://localhost:3000** with credentials `admin/admin`.

#### Configure Prometheus Data Source

Add Prometheus as a data source in Grafana:

**Via UI:**
1. Navigate to Configuration > Data Sources
2. Click "Add data source"
3. Select "Prometheus"
4. Set URL to `http://prometheus:9090` (container name on same network)
5. Click "Save & Test"

**Via API (automated):**

```bash
# Wait for Grafana to be ready
sleep 10

# Add Prometheus data source via API
curl -X POST http://admin:admin@localhost:3000/api/datasources \
    -H "Content-Type: application/json" \
    -d '{
        "name": "Prometheus",
        "type": "prometheus",
        "url": "http://prometheus:9090",
        "access": "proxy",
        "isDefault": true
    }'
```

### Importing Liberty Dashboard

Import the pre-built Liberty dashboard for monitoring application health and performance.

#### Import via Grafana UI

1. Navigate to Dashboards > Import
2. Click "Upload JSON file"
3. Select `/home/justin/Projects/middleware-automation-platform/monitoring/grafana/dashboards/ecs-liberty.json`
4. Select "Prometheus" as the data source
5. Click "Import"

#### Import via API

```bash
# Import dashboard using Grafana API
curl -X POST http://admin:admin@localhost:3000/api/dashboards/db \
    -H "Content-Type: application/json" \
    -d @- << 'EOF'
{
    "dashboard": $(cat /home/justin/Projects/middleware-automation-platform/monitoring/grafana/dashboards/ecs-liberty.json),
    "overwrite": true,
    "inputs": [
        {
            "name": "DS_PROMETHEUS",
            "type": "datasource",
            "pluginId": "prometheus",
            "value": "Prometheus"
        }
    ]
}
EOF
```

#### Key Liberty Metrics to Monitor

The dashboard displays these important MicroProfile Metrics:

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| `base_cpu_processCpuLoad` | JVM CPU usage | > 80% |
| `base_memory_usedHeap_bytes` | Heap memory used | > 80% of max |
| `base_gc_time_total_seconds` | Garbage collection time | Increasing rapidly |
| `application_*` | Custom application metrics | Application-specific |
| `vendor_servlet_request_total` | HTTP request count | Rate anomalies |
| `vendor_servlet_responseTime_total_seconds` | Response time | > 2s average |

### Monitoring Stack with Podman Compose

For a complete monitoring setup, use this compose file:

Create `/home/justin/Projects/middleware-automation-platform/containers/liberty/compose/docker-compose-monitoring.yaml`:

```yaml
# Liberty with Prometheus and Grafana Monitoring Stack
# Run with: podman-compose -f docker-compose-monitoring.yaml up -d

services:
  liberty:
    build:
      context: ..
      dockerfile: Containerfile
    image: liberty-app:1.0.0
    container_name: liberty-server
    ports:
      - "9080:9080"
      - "9443:9443"
    environment:
      - WLP_LOGGING_CONSOLE_FORMAT=JSON
      - WLP_LOGGING_CONSOLE_LOGLEVEL=INFO
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9080/health/ready"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    networks:
      - monitoring-net

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus-local.yml:/etc/prometheus/prometheus.yml:ro,Z
      - prometheus-data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.enable-lifecycle'
    depends_on:
      liberty:
        condition: service_healthy
    networks:
      - monitoring-net

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false
    volumes:
      - grafana-data:/var/lib/grafana
      - ../../../monitoring/grafana/dashboards:/var/lib/grafana/dashboards:ro,Z
      - ./grafana-provisioning:/etc/grafana/provisioning:ro,Z
    depends_on:
      - prometheus
    networks:
      - monitoring-net

volumes:
  prometheus-data:
  grafana-data:

networks:
  monitoring-net:
    driver: bridge
```

Create the Prometheus configuration for the compose stack:

```bash
# Create prometheus config in compose directory
cat > /home/justin/Projects/middleware-automation-platform/containers/liberty/compose/prometheus-local.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'liberty'
    metrics_path: /metrics
    static_configs:
      - targets: ['liberty-server:9080']
        labels:
          environment: 'local'
          instance_name: 'liberty-local'
EOF
```

Create Grafana provisioning for automatic data source and dashboard setup:

```bash
# Create provisioning directories
mkdir -p /home/justin/Projects/middleware-automation-platform/containers/liberty/compose/grafana-provisioning/datasources
mkdir -p /home/justin/Projects/middleware-automation-platform/containers/liberty/compose/grafana-provisioning/dashboards

# Create datasource provisioning
cat > /home/justin/Projects/middleware-automation-platform/containers/liberty/compose/grafana-provisioning/datasources/prometheus.yml << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
EOF

# Create dashboard provisioning
cat > /home/justin/Projects/middleware-automation-platform/containers/liberty/compose/grafana-provisioning/dashboards/default.yml << 'EOF'
apiVersion: 1

providers:
  - name: 'Liberty Dashboards'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /var/lib/grafana/dashboards
EOF
```

Run the complete monitoring stack:

```bash
cd /home/justin/Projects/middleware-automation-platform/containers/liberty/compose

# Start the monitoring stack
podman-compose -f docker-compose-monitoring.yaml up -d

# Verify all services are running
podman-compose -f docker-compose-monitoring.yaml ps

# View logs
podman-compose -f docker-compose-monitoring.yaml logs -f
```

Access the monitoring services:

| Service | URL | Credentials |
|---------|-----|-------------|
| Liberty Application | http://localhost:9080/sample-app | N/A |
| Liberty Metrics | http://localhost:9080/metrics | N/A |
| Prometheus | http://localhost:9090 | N/A |
| Grafana | http://localhost:3000 | admin/admin |

## Development Workflow

This section covers efficient development practices for iterating on the Liberty application.

### Edit-Build-Restart Cycle

The standard development workflow for code changes:

```bash
# 1. Make changes to your source code in sample-app/

# 2. Rebuild the WAR file
mvn -f /home/justin/Projects/middleware-automation-platform/sample-app/pom.xml clean package

# 3. Copy the new WAR to the container build directory
cp /home/justin/Projects/middleware-automation-platform/sample-app/target/sample-app.war \
   /home/justin/Projects/middleware-automation-platform/containers/liberty/apps/

# 4. Stop the existing container
podman stop liberty-server

# 5. Remove the container
podman rm liberty-server

# 6. Rebuild the container image
cd /home/justin/Projects/middleware-automation-platform/containers/liberty
podman build -t liberty-app:1.0.0 -f Containerfile .

# 7. Start the new container
podman run -d --name liberty-server \
    -p 9080:9080 \
    -p 9443:9443 \
    liberty-app:1.0.0

# 8. Verify the application is running
curl -s http://localhost:9080/health/ready | jq .
```

#### Streamlined Rebuild Script

Create a helper script for faster iteration:

```bash
cat > /home/justin/Projects/middleware-automation-platform/scripts/dev-rebuild.sh << 'EOF'
#!/bin/bash
# Quick rebuild script for local development
set -e

PROJECT_ROOT="/home/justin/Projects/middleware-automation-platform"
CONTAINER_NAME="liberty-server"
IMAGE_NAME="liberty-app:1.0.0"

echo "==> Building WAR file..."
mvn -f "${PROJECT_ROOT}/sample-app/pom.xml" clean package -q

echo "==> Copying WAR to container build directory..."
cp "${PROJECT_ROOT}/sample-app/target/sample-app.war" "${PROJECT_ROOT}/containers/liberty/apps/"

echo "==> Stopping and removing existing container..."
podman stop "${CONTAINER_NAME}" 2>/dev/null || true
podman rm "${CONTAINER_NAME}" 2>/dev/null || true

echo "==> Building container image..."
podman build -t "${IMAGE_NAME}" -f "${PROJECT_ROOT}/containers/liberty/Containerfile" "${PROJECT_ROOT}/containers/liberty" -q

echo "==> Starting new container..."
podman run -d --name "${CONTAINER_NAME}" \
    -p 9080:9080 \
    -p 9443:9443 \
    "${IMAGE_NAME}"

echo "==> Waiting for Liberty to start..."
timeout 120 bash -c 'until curl -sf http://localhost:9080/health/ready > /dev/null 2>&1; do sleep 2; done'

echo "==> Application is ready at http://localhost:9080/sample-app"
EOF

chmod +x /home/justin/Projects/middleware-automation-platform/scripts/dev-rebuild.sh
```

Run the script to rebuild and restart:

```bash
/home/justin/Projects/middleware-automation-platform/scripts/dev-rebuild.sh
```

### Hot Deployment with Dropins Directory

Liberty supports hot deployment by monitoring the `dropins` directory. Use volume mounts to enable redeployment without container restart.

#### Using the Dropins Directory

```bash
# Run Liberty with dropins directory mounted
podman run -d --name liberty-dev \
    -p 9080:9080 \
    -p 9443:9443 \
    -v /home/justin/Projects/middleware-automation-platform/containers/liberty/dropins:/config/dropins:Z \
    liberty-app:1.0.0
```

#### Hot Deployment Workflow

```bash
# 1. Make changes to your source code

# 2. Build the WAR
mvn -f /home/justin/Projects/middleware-automation-platform/sample-app/pom.xml clean package

# 3. Copy to the mounted dropins directory
cp /home/justin/Projects/middleware-automation-platform/sample-app/target/sample-app.war \
   /home/justin/Projects/middleware-automation-platform/containers/liberty/dropins/

# 4. Liberty automatically detects and deploys the new WAR
# Watch the logs to see the redeployment
podman logs -f liberty-dev
```

You will see log messages like:

```
[AUDIT   ] CWWKZ0003I: The application sample-app updated in X.XXX seconds.
```

#### Dropins vs Apps Directory

| Directory | Behavior | Use Case |
|-----------|----------|----------|
| `/config/apps/` | Deployed at startup only | Production deployments |
| `/config/dropins/` | Monitored for changes, auto-deploys | Development hot reload |

### Using Podman Logs for Debugging

Podman logs are essential for debugging application issues.

#### Basic Log Commands

```bash
# View all logs
podman logs liberty-server

# Follow logs in real-time (like tail -f)
podman logs -f liberty-server

# Show last 100 lines
podman logs --tail 100 liberty-server

# Show logs since a specific time
podman logs --since 10m liberty-server

# Show logs with timestamps
podman logs -t liberty-server

# Combine options: last 50 lines with timestamps, follow new logs
podman logs -t --tail 50 -f liberty-server
```

#### Filtering Liberty JSON Logs

When `WLP_LOGGING_CONSOLE_FORMAT=JSON` is set, use `jq` for filtering:

```bash
# Pretty print all logs
podman logs liberty-server | jq .

# Filter by log level
podman logs liberty-server | jq 'select(.loglevel == "ERROR")'

# Filter by message content
podman logs liberty-server | jq 'select(.message | contains("sample-app"))'

# Show only warnings and errors
podman logs liberty-server | jq 'select(.loglevel == "WARNING" or .loglevel == "ERROR")'

# Extract specific fields
podman logs liberty-server | jq '{time: .datetime, level: .loglevel, msg: .message}'

# Filter by time range (last 5 minutes)
podman logs --since 5m liberty-server | jq .

# Count errors
podman logs liberty-server | jq -s '[.[] | select(.loglevel == "ERROR")] | length'
```

#### Debugging Application Startup

```bash
# Watch Liberty startup in real-time
podman run --rm -p 9080:9080 -p 9443:9443 liberty-app:1.0.0

# Look for specific startup messages
podman logs liberty-server | grep -E "(CWWKZ|CWWKF|CWWKE)"

# Common Liberty message prefixes:
# CWWKZ - Application management (deploy/undeploy)
# CWWKF - Feature management (install/start)
# CWWKE - Server lifecycle (start/stop)
# CWWKS - Security messages
```

#### Log to File for Analysis

```bash
# Save logs to file
podman logs liberty-server > /tmp/liberty-logs.txt

# Save and continue monitoring
podman logs liberty-server > /tmp/liberty-logs.txt && podman logs -f liberty-server | tee -a /tmp/liberty-logs.txt

# Export logs with container events
podman events --filter container=liberty-server --since 1h
```

### Accessing Liberty Admin Console

Liberty includes an Admin Center web UI for server management (optional feature).

#### Enable Admin Center

Update `server.xml` to include the Admin Center feature:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<server description="Containerized Open Liberty with Admin Center">
    <featureManager>
        <feature>restfulWS-3.1</feature>
        <feature>jsonb-3.0</feature>
        <feature>cdi-4.0</feature>
        <feature>mpHealth-4.0</feature>
        <feature>mpMetrics-5.0</feature>
        <feature>mpConfig-3.0</feature>
        <feature>jdbc-4.3</feature>
        <feature>ssl-1.0</feature>
        <!-- Admin Center -->
        <feature>adminCenter-1.0</feature>
    </featureManager>

    <httpEndpoint id="defaultHttpEndpoint" host="*"
                  httpPort="9080"
                  httpsPort="9443" />

    <mpHealth authentication="false"/>
    <mpMetrics authentication="false"/>

    <logging consoleLogLevel="INFO" consoleFormat="JSON"/>

    <!-- Admin Center configuration -->
    <quickStartSecurity userName="admin" userPassword="adminpwd"/>
    <keyStore id="defaultKeyStore" password="keystorePass"/>
</server>
```

#### Run with Admin Center Enabled

```bash
# Build a new image with Admin Center config
podman build -t liberty-app:admin -f Containerfile .

# Run the container
podman run -d --name liberty-admin \
    -p 9080:9080 \
    -p 9443:9443 \
    liberty-app:admin
```

#### Access Admin Center

Open **https://localhost:9443/adminCenter** in your browser.

- **Username:** admin
- **Password:** adminpwd

> **Note:** Accept the self-signed certificate warning in your browser.

Admin Center provides:
- Server status and control (start/stop/restart)
- Application management
- Configuration editor
- Server explorer
- Java batch tool (if batch feature is enabled)

#### Admin Center via Volume Mount (Development)

For development, mount a modified server.xml without rebuilding:

```bash
# Create server.xml with Admin Center enabled
cat > /tmp/server-admin.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<server description="Liberty with Admin Center">
    <featureManager>
        <feature>restfulWS-3.1</feature>
        <feature>jsonb-3.0</feature>
        <feature>cdi-4.0</feature>
        <feature>mpHealth-4.0</feature>
        <feature>mpMetrics-5.0</feature>
        <feature>mpConfig-3.0</feature>
        <feature>jdbc-4.3</feature>
        <feature>ssl-1.0</feature>
        <feature>adminCenter-1.0</feature>
    </featureManager>

    <httpEndpoint id="defaultHttpEndpoint" host="*"
                  httpPort="9080" httpsPort="9443" />

    <mpHealth authentication="false"/>
    <mpMetrics authentication="false"/>
    <logging consoleLogLevel="INFO" consoleFormat="JSON"/>

    <quickStartSecurity userName="admin" userPassword="adminpwd"/>
    <keyStore id="defaultKeyStore" password="keystorePass"/>
</server>
EOF

# Run with mounted config
podman run -d --name liberty-admin \
    -p 9080:9080 \
    -p 9443:9443 \
    -v /tmp/server-admin.xml:/config/server.xml:Z \
    liberty-app:1.0.0
```

> **Security Note:** Never use `quickStartSecurity` in production. Configure proper user registries (LDAP, database) for production environments.

### Debugging Inside the Container

Sometimes you need to inspect the container from the inside.

#### Interactive Shell Access

```bash
# Start a shell in a running container
podman exec -it liberty-server bash

# Common inspection commands inside the container
ls -la /config/                    # View server configuration
ls -la /config/apps/               # View deployed applications
cat /config/server.xml             # View server.xml
cat /config/jvm.options            # View JVM settings
/opt/ibm/wlp/bin/server status     # Check server status
/opt/ibm/wlp/bin/server version    # Show Liberty version
cat /logs/messages.log             # View log file

# Exit the container
exit
```

#### Running One-Off Commands

```bash
# Check Liberty version
podman exec liberty-server /opt/ibm/wlp/bin/server version

# List deployed applications
podman exec liberty-server ls -la /config/apps/

# View server.xml
podman exec liberty-server cat /config/server.xml

# Check Java version
podman exec liberty-server java -version

# View environment variables
podman exec liberty-server env | sort

# Check network configuration
podman exec liberty-server cat /etc/hosts
```

### Development Environment Variables

Configure Liberty behavior through environment variables:

```bash
# Development configuration with verbose logging
podman run -d --name liberty-dev \
    -p 9080:9080 \
    -p 9443:9443 \
    -e WLP_LOGGING_CONSOLE_FORMAT=JSON \
    -e WLP_LOGGING_CONSOLE_LOGLEVEL=INFO \
    -e WLP_LOGGING_CONSOLE_SOURCE=message,trace,accessLog,ffdc \
    -e MP_CONFIG_PROFILE=dev \
    liberty-app:1.0.0

# Enable debug output for troubleshooting
podman run -d --name liberty-debug \
    -p 9080:9080 \
    -p 9443:9443 \
    -e WLP_LOGGING_CONSOLE_LOGLEVEL=FINE \
    -e WLP_DEBUG_SUSPEND=n \
    -e WLP_DEBUG_ADDRESS=7777 \
    -p 7777:7777 \
    liberty-app:1.0.0
```

### Complete Development Setup

A comprehensive development setup combining hot reload, monitoring, and debugging:

```bash
# Create development network
podman network create dev-net

# Run Liberty with hot reload
podman run -d --name liberty-dev \
    --network dev-net \
    -p 9080:9080 \
    -p 9443:9443 \
    -p 7777:7777 \
    -v /home/justin/Projects/middleware-automation-platform/containers/liberty/dropins:/config/dropins:Z \
    -v /home/justin/Projects/middleware-automation-platform/containers/liberty/server.xml:/config/server.xml:Z \
    -e WLP_LOGGING_CONSOLE_FORMAT=JSON \
    -e WLP_LOGGING_CONSOLE_LOGLEVEL=INFO \
    -e WLP_DEBUG_SUSPEND=n \
    -e WLP_DEBUG_ADDRESS=7777 \
    liberty-app:1.0.0

# Run Prometheus for metrics
podman run -d --name prometheus \
    --network dev-net \
    -p 9090:9090 \
    -v /home/justin/Projects/middleware-automation-platform/monitoring/prometheus/local/prometheus-network.yml:/etc/prometheus/prometheus.yml:ro,Z \
    prom/prometheus:latest

# Run Grafana for dashboards
podman run -d --name grafana \
    --network dev-net \
    -p 3000:3000 \
    -e GF_SECURITY_ADMIN_USER=admin \
    -e GF_SECURITY_ADMIN_PASSWORD=admin \
    grafana/grafana:latest

# Development workflow
echo "
=== Development Environment Ready ===
Liberty Application:  http://localhost:9080/sample-app
Liberty Metrics:      http://localhost:9080/metrics
Health Check:         http://localhost:9080/health/ready
Prometheus:           http://localhost:9090
Grafana:              http://localhost:3000 (admin/admin)
Debug Port:           localhost:7777

Hot Reload: Copy WAR to containers/liberty/dropins/
Logs:       podman logs -f liberty-dev
"
```

### Cleanup Development Environment

```bash
# Stop and remove all development containers
podman stop liberty-dev prometheus grafana 2>/dev/null
podman rm liberty-dev prometheus grafana 2>/dev/null

# Remove the development network
podman network rm dev-net 2>/dev/null

# Remove volumes (optional - preserves data if omitted)
podman volume rm grafana-data prometheus-data 2>/dev/null

# Clean up everything
podman system prune -a
```

---

## Quick Reference

This section provides a comprehensive quick reference for Podman commands, configurations, and common operations.

### Common Podman Commands Cheatsheet

**Container Lifecycle:**

```bash
# Build image
podman build -t liberty-app:1.0.0 -f Containerfile .

# Run container (detached)
podman run -d --name liberty-server -p 9080:9080 -p 9443:9443 liberty-app:1.0.0

# Run container (foreground for debugging)
podman run --rm -p 9080:9080 -p 9443:9443 liberty-app:1.0.0

# Stop container
podman stop liberty-server

# Start stopped container
podman start liberty-server

# Restart container
podman restart liberty-server

# Remove container
podman rm liberty-server

# Force remove running container
podman rm -f liberty-server
```

**Container Inspection:**

```bash
# List running containers
podman ps

# List all containers (including stopped)
podman ps -a

# View container logs
podman logs liberty-server

# Follow logs in real-time
podman logs -f liberty-server

# View logs with timestamps
podman logs -t liberty-server

# Show last N lines of logs
podman logs --tail 100 liberty-server

# Execute command in container
podman exec -it liberty-server bash

# Execute single command
podman exec liberty-server cat /config/server.xml

# View container resource usage
podman stats liberty-server

# Inspect container details
podman inspect liberty-server

# Get specific value from inspection
podman inspect liberty-server --format='{{.State.Status}}'
```

**Image Management:**

```bash
# List images
podman images

# Search for images
podman search liberty

# Pull image
podman pull icr.io/appcafe/open-liberty:kernel-slim-java17-openj9-ubi

# Remove image
podman rmi liberty-app:1.0.0

# Tag image
podman tag liberty-app:1.0.0 liberty-app:latest

# View image history
podman history liberty-app:1.0.0

# Export image to tar
podman save liberty-app:1.0.0 -o liberty-app.tar

# Import image from tar
podman load -i liberty-app.tar
```

### Port Mappings Table

| Service | Container Port | Default Host Port | Protocol | Description |
|---------|----------------|-------------------|----------|-------------|
| HTTP | 9080 | 9080 | TCP | Main application HTTP traffic |
| HTTPS | 9443 | 9443 | TCP | Secure HTTPS traffic (TLS) |
| Debug | 7777 | 7777 | TCP | JVM remote debugging |
| Admin (optional) | 9060 | 9060 | TCP | Liberty Admin Center |
| PostgreSQL | 5432 | 5432 | TCP | Database connections |
| Redis | 6379 | 6379 | TCP | Cache connections |
| Prometheus | 9090 | 9090 | TCP | Metrics collection |
| Grafana | 3000 | 3000 | TCP | Dashboards |
| NGINX LB | 80 | 8080 | TCP | Load balancer HTTP |
| NGINX LB | 443 | 8443 | TCP | Load balancer HTTPS |

### Environment Variables Table

**Liberty Runtime Variables:**

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `WLP_LOGGING_CONSOLE_FORMAT` | Log output format | `SIMPLE` | `JSON` |
| `WLP_LOGGING_CONSOLE_LOGLEVEL` | Minimum log level | `INFO` | `WARNING`, `SEVERE`, `FINE` |
| `WLP_LOGGING_CONSOLE_SOURCE` | Log sources to include | `message,trace,accessLog,ffdc` | `message,accessLog` |
| `WLP_OUTPUT_DIR` | Liberty output directory | `/opt/ibm/wlp/output` | `/logs` |
| `WLP_DEBUG_SUSPEND` | Suspend on debug attach | `y` | `n` |
| `WLP_DEBUG_ADDRESS` | Remote debug port | `7777` | `5005` |

**Application Variables:**

| Variable | Description | Example |
|----------|-------------|---------|
| `DB_HOST` | Database hostname | `postgres`, `localhost` |
| `DB_PORT` | Database port | `5432` |
| `DB_NAME` | Database name | `appdb` |
| `DB_USER` | Database username | `appuser` |
| `DB_PASSWORD` | Database password | `appsecret` |
| `CACHE_HOST` | Redis hostname | `redis`, `localhost` |
| `CACHE_PORT` | Redis port | `6379` |
| `INSTANCE_NAME` | Container instance identifier | `liberty1` |

### Volume Mount Paths

| Container Path | Purpose | Host Mount Example |
|----------------|---------|-------------------|
| `/config/server.xml` | Liberty server configuration | `./server.xml:/config/server.xml:Z` |
| `/config/jvm.options` | JVM tuning options | `./jvm.options:/config/jvm.options:Z` |
| `/config/apps/` | Application WAR/EAR files | `./apps:/config/apps:Z` |
| `/config/lib/` | JDBC drivers, shared libraries | `./lib:/config/lib:Z` |
| `/config/dropins/` | Hot-deploy applications | `./dropins:/config/dropins:Z` |
| `/logs/` | Liberty log files | `./logs:/logs:Z` |
| `/output/` | Liberty output directory | `./output:/output:Z` |

### Full Command Examples

**Basic development workflow:**

```bash
# Build and run Liberty container
cd /home/justin/Projects/middleware-automation-platform
mvn -f sample-app/pom.xml clean package
cp sample-app/target/sample-app.war containers/liberty/apps/
cd containers/liberty
podman build -t liberty-app:1.0.0 -f Containerfile .
podman run -d --name liberty-server -p 9080:9080 -p 9443:9443 liberty-app:1.0.0

# Verify application is running
curl http://localhost:9080/health/ready
curl http://localhost:9080/sample-app/
```

**Development with hot reload:**

```bash
# Start container with mounted volumes for hot reload
podman run -d --name liberty-dev \
    -p 9080:9080 \
    -p 9443:9443 \
    -v /home/justin/Projects/middleware-automation-platform/containers/liberty/server.xml:/config/server.xml:Z \
    -v /home/justin/Projects/middleware-automation-platform/containers/liberty/apps:/config/apps:Z \
    liberty-app:1.0.0

# Make changes, rebuild WAR, copy to apps directory
mvn -f /home/justin/Projects/middleware-automation-platform/sample-app/pom.xml clean package
cp /home/justin/Projects/middleware-automation-platform/sample-app/target/*.war \
   /home/justin/Projects/middleware-automation-platform/containers/liberty/apps/

# Watch logs to see automatic redeployment
podman logs -f liberty-dev
```

**Production-like deployment with resource limits:**

```bash
podman run -d --name liberty-prod \
    -p 9080:9080 \
    -p 9443:9443 \
    --memory=1g \
    --memory-reservation=512m \
    --cpus=1.0 \
    -e WLP_LOGGING_CONSOLE_FORMAT=JSON \
    -e WLP_LOGGING_CONSOLE_LOGLEVEL=INFO \
    --restart=unless-stopped \
    liberty-app:1.0.0
```

**Full stack with database and cache:**

```bash
cd /home/justin/Projects/middleware-automation-platform/containers/liberty/compose
podman-compose -f docker-compose-full.yaml up -d

# Verify all services
podman-compose -f docker-compose-full.yaml ps
curl http://localhost:9080/health/ready

# Connect to database
podman exec -it liberty-postgres psql -U appuser -d appdb

# Connect to Redis
podman exec -it liberty-redis redis-cli ping

# Stop all services
podman-compose -f docker-compose-full.yaml down
```

**Debugging session:**

```bash
# Start with debug enabled
podman run -d --name liberty-debug \
    -p 9080:9080 \
    -p 9443:9443 \
    -p 7777:7777 \
    -e WLP_DEBUG_SUSPEND=n \
    -e WLP_DEBUG_ADDRESS=7777 \
    --no-healthcheck \
    liberty-app:1.0.0

# View startup logs
podman logs -f liberty-debug

# Connect IDE debugger to localhost:7777
```

### Cleanup Commands

**Remove specific resources:**

```bash
# Stop and remove a specific container
podman rm -f liberty-server

# Remove a specific image
podman rmi liberty-app:1.0.0

# Remove a specific volume
podman volume rm liberty-logs

# Remove a specific network
podman network rm liberty-net
```

**Cleanup unused resources:**

```bash
# Remove all stopped containers
podman container prune

# Remove unused images (dangling)
podman image prune

# Remove all unused images (not just dangling)
podman image prune -a

# Remove unused volumes
podman volume prune

# Remove unused networks
podman network prune

# Remove all unused resources (containers, images, networks)
podman system prune

# Remove everything including volumes (use with caution)
podman system prune -a --volumes
```

**Complete reset:**

```bash
# Stop all running containers
podman stop $(podman ps -q)

# Remove all containers
podman rm $(podman ps -a -q)

# Remove all images
podman rmi $(podman images -q)

# Remove all volumes
podman volume rm $(podman volume ls -q)

# Remove all networks (except default)
podman network prune -f

# Reset Podman completely (removes all data)
podman system reset
```

**Podman Compose cleanup:**

```bash
# Stop and remove containers for a compose file
podman-compose down

# Stop and remove containers and volumes
podman-compose down -v

# Stop and remove containers, volumes, and images
podman-compose down -v --rmi all
```

### Health Check Endpoints

| Endpoint | URL | Purpose |
|----------|-----|---------|
| Readiness | `http://localhost:9080/health/ready` | Application ready to serve traffic |
| Liveness | `http://localhost:9080/health/live` | Application is running (not deadlocked) |
| Startup | `http://localhost:9080/health/started` | Application has completed startup |
| Combined | `http://localhost:9080/health` | All health checks combined |
| Metrics | `http://localhost:9080/metrics` | Prometheus-format metrics |
| Application | `http://localhost:9080/sample-app/` | Main application endpoint |

**Health check commands:**

```bash
# Quick health verification
curl -sf http://localhost:9080/health/ready && echo "READY" || echo "NOT READY"

# Wait for container to become healthy (useful in scripts)
timeout 120 bash -c 'until curl -sf http://localhost:9080/health/ready; do sleep 5; done'

# Continuous health monitoring
watch -n 5 'curl -s http://localhost:9080/health | jq .'

# Check Prometheus metrics
curl -s http://localhost:9080/metrics | head -50
```

### Container Images

| Image | Registry | Tag |
|-------|----------|-----|
| Open Liberty | icr.io/appcafe/open-liberty | kernel-slim-java17-openj9-ubi |
| PostgreSQL | docker.io/library/postgres | 15-alpine |
| Redis | docker.io/library/redis | 7-alpine |
| Prometheus | docker.io/prom/prometheus | latest |
| Grafana | docker.io/grafana/grafana | latest |
| Alertmanager | docker.io/prom/alertmanager | latest |
| NGINX | docker.io/library/nginx | alpine |

### File Locations

| File | Path |
|------|------|
| Containerfile | `containers/liberty/Containerfile` |
| server.xml | `containers/liberty/server.xml` |
| JVM options | `containers/liberty/jvm.options` |
| WAR files | `containers/liberty/apps/` |
| Dropins (hot reload) | `containers/liberty/dropins/` |
| Compose files | `containers/liberty/compose/` |
| Prometheus config | `monitoring/prometheus/local/` |
| Grafana dashboards | `monitoring/grafana/dashboards/` |

### Quick Verification Script

```bash
#!/bin/bash
# Save as verify-local.sh and run after starting containers

echo "=== Container Status ==="
podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "=== Health Checks ==="
for endpoint in health/ready health/live metrics; do
    status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9080/$endpoint 2>/dev/null)
    echo "$endpoint: $status"
done

echo ""
echo "=== Sample App ==="
curl -s http://localhost:9080/sample-app/api/hello 2>/dev/null || echo "Not available"

echo ""
echo "=== Monitoring ==="
prometheus=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9090/-/ready 2>/dev/null)
grafana=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/health 2>/dev/null)
echo "Prometheus: $prometheus"
echo "Grafana: $grafana"
```

### Related Documentation

| Document | Path | Description |
|----------|------|-------------|
| Kubernetes Deployment | [LOCAL_KUBERNETES_DEPLOYMENT.md](LOCAL_KUBERNETES_DEPLOYMENT.md) | Multi-node Kubernetes deployment guide |
| AWS Production | [../CLAUDE.md](../CLAUDE.md) | AWS ECS and EC2 deployment options |
| ECS Migration Plan | [plans/ecs-migration-plan.md](plans/ecs-migration-plan.md) | Migration from EC2 to ECS |
| Terraform Troubleshooting | [troubleshooting/terraform-aws.md](troubleshooting/terraform-aws.md) | AWS infrastructure issues |
| Containerfile | [../containers/liberty/Containerfile](../containers/liberty/Containerfile) | Liberty container build definition |
| Server Configuration | [../containers/liberty/server.xml](../containers/liberty/server.xml) | Liberty server.xml template |
| Compose Files | [../containers/liberty/compose/](../containers/liberty/compose/) | Podman Compose configurations |
| Sample Application | [../sample-app/](../sample-app/) | Jakarta EE sample application |
| Ansible Liberty Role | [../automated/ansible/roles/liberty/](../automated/ansible/roles/liberty/) | Ansible automation for Liberty |

---

## Next Steps

After setting up local Podman deployment:

1. **Kubernetes deployment**: See [LOCAL_KUBERNETES_DEPLOYMENT.md](LOCAL_KUBERNETES_DEPLOYMENT.md) for multi-node cluster setup
2. **AWS production**: See [README.md](../README.md#option-4-aws-production-deployment) for cloud deployment
3. **CI/CD setup**: See [ci-cd/jenkins/podman/README.md](../ci-cd/jenkins/podman/README.md) for Jenkins with Podman
4. **Monitoring dashboards**: Import dashboards from `monitoring/grafana/dashboards/`
