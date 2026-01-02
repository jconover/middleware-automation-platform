# Getting Started: From Zero to Running Liberty in 30 Minutes

This guide walks you through deploying your first Open Liberty container on your local machine. No cloud accounts, no Kubernetes cluster, no complex setup required.

**Time to complete:** 30 minutes
**Difficulty:** Beginner
**Prerequisites:** Basic command-line familiarity

---

## Table of Contents

1. [Prerequisites Check](#1-prerequisites-check-5-minutes) (5 min)
2. [Your First Liberty Container](#2-your-first-liberty-container-10-minutes) (10 min)
3. [Test the Sample Application](#3-test-the-sample-application-10-minutes) (10 min)
4. [Decision Tree: What's Next?](#4-decision-tree-whats-next-5-minutes) (5 min)
5. [Troubleshooting First Run](#5-troubleshooting-first-run)

---

## 1. Prerequisites Check (5 minutes)

### System Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 2 cores | 4+ cores |
| RAM | 4 GB | 8+ GB |
| Disk | 10 GB free | 20+ GB free |
| OS | Linux, macOS, or Windows (WSL2) | Ubuntu 22.04+, Fedora 38+, macOS 13+ |

### Required Software

You need a container runtime (Podman or Docker) and a few basic tools. Choose **one** container runtime.

#### Option A: Podman (Recommended for Linux)

```bash
# Ubuntu/Debian
sudo apt update && sudo apt install -y podman

# Fedora/RHEL
sudo dnf install -y podman

# macOS (requires Homebrew)
brew install podman
podman machine init
podman machine start
```

#### Option B: Docker

```bash
# Ubuntu/Debian
sudo apt update && sudo apt install -y docker.io
sudo usermod -aG docker $USER
# Log out and back in for group changes to take effect

# macOS/Windows
# Download Docker Desktop from https://www.docker.com/products/docker-desktop
```

#### Additional Tools

```bash
# Git (for cloning the repository)
# Ubuntu/Debian
sudo apt install -y git

# Fedora/RHEL
sudo dnf install -y git

# macOS
xcode-select --install

# curl (usually pre-installed)
# Ubuntu/Debian
sudo apt install -y curl
```

### Verification Commands

Run these commands to confirm everything is installed correctly. All should return version information without errors.

```bash
# Check container runtime (run ONE of these)
podman --version    # Expected: podman version 4.x.x or higher
docker --version    # Expected: Docker version 24.x.x or higher

# Check Git
git --version       # Expected: git version 2.x.x

# Check curl
curl --version      # Expected: curl 7.x.x or 8.x.x
```

**Checkpoint:** If all commands return version information, proceed to the next section.

---

## 2. Your First Liberty Container (10 minutes)

### Step 1: Clone the Repository

```bash
# Choose a directory for the project
cd ~/Projects  # or any directory you prefer

# Clone the repository
git clone https://github.com/example/middleware-automation-platform.git

# Enter the project directory
cd middleware-automation-platform
```

### Step 2: Build the Container Image

The build uses a multi-stage Containerfile that:
1. Compiles the sample Java application from source (using Maven)
2. Creates a minimal runtime image with Open Liberty

**Important:** Run this command from the project root directory (where this README is located).

```bash
# Using Podman
podman build -t liberty-app:1.0.0 -f containers/liberty/Containerfile .

# Using Docker
docker build -t liberty-app:1.0.0 -f containers/liberty/Containerfile .
```

**Expected output:** The build takes 2-5 minutes on first run (subsequent builds are faster due to caching). You should see:

```
STEP 1: FROM docker.io/library/maven:3.9-eclipse-temurin-17 AS builder
...
STEP 2: FROM icr.io/appcafe/open-liberty:kernel-slim-java17-openj9-ubi AS runtime
...
Successfully tagged localhost/liberty-app:1.0.0
```

### Step 3: Run the Container

```bash
# Using Podman
podman run -d -p 9080:9080 -p 9443:9443 --name liberty liberty-app:1.0.0

# Using Docker
docker run -d -p 9080:9080 -p 9443:9443 --name liberty liberty-app:1.0.0
```

**Flag explanation:**
- `-d`: Run in detached mode (background)
- `-p 9080:9080`: Map HTTP port
- `-p 9443:9443`: Map HTTPS port
- `--name liberty`: Name the container for easy reference

### Step 4: Verify the Container is Running

```bash
# Check container status (use docker if not using podman)
podman ps

# Expected output:
# CONTAINER ID  IMAGE                      COMMAND               STATUS         PORTS                                         NAMES
# a1b2c3d4e5f6  localhost/liberty-app:1.0.0  /opt/ol/wlp/bin/...  Up 30 seconds  0.0.0.0:9080->9080/tcp, 0.0.0.0:9443->9443/tcp  liberty
```

### Step 5: Verify Health Endpoint

Wait about 30-60 seconds for Liberty to fully start, then:

```bash
curl http://localhost:9080/health/ready
```

**Expected output:**

```json
{"checks":[{"data":{},"name":"SampleReadinessCheck","status":"UP"}],"status":"UP"}
```

**Checkpoint:** If you see `"status":"UP"`, your Liberty container is running correctly.

---

## 3. Test the Sample Application (10 minutes)

The sample application provides several REST endpoints for testing. All endpoints are prefixed with `/api`.

### Test the Hello Endpoint

```bash
# Basic hello
curl http://localhost:9080/api/hello
```

**Expected output:**

```json
{"message":"Hello from Liberty!","timestamp":"2024-01-15T10:30:45.123Z"}
```

```bash
# Hello with a name parameter
curl http://localhost:9080/api/hello/Developer
```

**Expected output:**

```json
{"message":"Hello, Developer!","timestamp":"2024-01-15T10:30:55.456Z"}
```

### Test the Info Endpoint

This endpoint returns detailed server information including Java version, memory usage, and uptime.

```bash
curl http://localhost:9080/api/info
```

**Expected output:**

```json
{
  "hostname": "a1b2c3d4e5f6",
  "javaVersion": "17.0.9",
  "javaVendor": "Eclipse Adoptium",
  "osName": "Linux",
  "osArch": "amd64",
  "availableProcessors": 4,
  "heapMemoryUsed": "45 MB",
  "heapMemoryMax": "512 MB",
  "uptime": "PT2M30S",
  "requestCount": 3,
  "appUptime": "PT2M25S"
}
```

### View Prometheus Metrics

Liberty exposes MicroProfile Metrics in Prometheus format for monitoring.

```bash
curl http://localhost:9080/metrics
```

**Expected output (partial):**

```
# HELP base_cpu_availableProcessors_total Displays the number of processors available.
# TYPE base_cpu_availableProcessors_total gauge
base_cpu_availableProcessors_total 4.0

# HELP base_memory_usedHeap_bytes Displays the amount of used heap memory.
# TYPE base_memory_usedHeap_bytes gauge
base_memory_usedHeap_bytes 4.7185920E7
...
```

### Check All Health Endpoints

Liberty provides three health check endpoints:

```bash
# Readiness check (is the app ready to receive traffic?)
curl http://localhost:9080/health/ready

# Liveness check (is the app still running?)
curl http://localhost:9080/health/live

# Startup check (has the app finished starting?)
curl http://localhost:9080/health/started

# All health checks combined
curl http://localhost:9080/health
```

### Additional API Endpoints

The sample application includes several other useful endpoints:

```bash
# Get application statistics
curl http://localhost:9080/api/stats

# Echo endpoint (returns what you send)
curl -X POST http://localhost:9080/api/echo \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello, Echo!"}'

# Simulated slow response (for testing timeouts)
curl "http://localhost:9080/api/slow?delay=2000"

# CPU-intensive endpoint (for load testing)
curl "http://localhost:9080/api/compute?iterations=1000000"
```

### Quick API Reference

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/hello` | GET | Simple greeting |
| `/api/hello/{name}` | GET | Personalized greeting |
| `/api/info` | GET | Server and JVM information |
| `/api/stats` | GET | Request statistics |
| `/api/echo` | POST | Echo back JSON payload |
| `/api/slow?delay=ms` | GET | Delayed response (0-10000ms) |
| `/api/compute?iterations=n` | GET | CPU workload simulation |
| `/health/ready` | GET | Readiness probe |
| `/health/live` | GET | Liveness probe |
| `/health/started` | GET | Startup probe |
| `/metrics` | GET | Prometheus metrics |

**Checkpoint:** If the API endpoints respond as expected, congratulations - you have a fully working Liberty deployment!

---

## 4. Decision Tree: What's Next? (5 minutes)

Now that you have Liberty running locally, here is how to proceed based on your goals:

### Path A: Continue Local Development with Podman

**Best for:** Individual development, testing, demos, CI/CD container builds

You already have everything you need. Some useful next steps:

```bash
# View container logs
podman logs -f liberty

# Stop the container
podman stop liberty

# Start it again
podman start liberty

# Remove the container
podman rm -f liberty

# Rebuild after code changes
podman build -t liberty-app:1.0.0 -f containers/liberty/Containerfile .
podman rm -f liberty && podman run -d -p 9080:9080 -p 9443:9443 --name liberty liberty-app:1.0.0
```

**Documentation:** [LOCAL_PODMAN_DEPLOYMENT.md](LOCAL_PODMAN_DEPLOYMENT.md) covers advanced Podman workflows including:
- Running multiple Liberty instances
- Podman Compose for multi-container setups
- Local monitoring with Prometheus and Grafana
- Database integration with PostgreSQL

### Path B: Deploy to a Kubernetes Cluster

**Best for:** Multi-node deployments, high availability, auto-scaling, production-like testing

If you have access to a Kubernetes cluster (local or cloud-based):

```bash
# Push image to a registry (Docker Hub example)
podman tag liberty-app:1.0.0 docker.io/YOUR_USERNAME/liberty-app:1.0.0
podman push docker.io/YOUR_USERNAME/liberty-app:1.0.0

# Deploy to Kubernetes
kubectl apply -f kubernetes/base/liberty-deployment.yaml
```

**Documentation:** [LOCAL_KUBERNETES_DEPLOYMENT.md](LOCAL_KUBERNETES_DEPLOYMENT.md) covers:
- Deploying to a local Kubernetes cluster
- MetalLB load balancer configuration
- Prometheus Operator monitoring setup
- ServiceMonitor for automatic metric discovery

### Path C: Deploy to AWS Production

**Best for:** Production workloads, enterprise deployments, managed infrastructure

AWS deployment requires:
1. AWS account with appropriate permissions
2. Terraform installed locally
3. AWS CLI configured with credentials

**Two compute options available:**

| Option | When to Use |
|--------|-------------|
| **ECS Fargate** | Serverless, auto-scaling, minimal ops overhead |
| **EC2 Instances** | Traditional VMs, full control, Ansible-managed |

**Documentation:** The main [README.md](../README.md) covers AWS deployment, including:
- Terraform infrastructure provisioning
- ECS Fargate configuration
- EC2 with Ansible automation
- RDS PostgreSQL and ElastiCache Redis
- ALB load balancing
- Prometheus/Grafana monitoring

### Quick Comparison

| Aspect | Local Podman | Local Kubernetes | AWS Production |
|--------|--------------|------------------|----------------|
| Setup time | 10 minutes | 1-2 hours | 2-4 hours |
| Cost | Free | Free | ~$120-170/month |
| Scaling | Manual | HPA/replicas | Auto-scaling |
| Best for | Development | Testing/staging | Production |
| Complexity | Low | Medium | High |

---

## 5. Troubleshooting First Run

### Port 9080 Already in Use

**Symptom:** Error message when starting the container:

```
Error: rootlessport cannot expose privileged port 9080, you can add 'net.ipv4.ip_unprivileged_port_start=9080' to /etc/sysctl.conf
```

or

```
Bind for 0.0.0.0:9080 failed: port is already allocated
```

**Solutions:**

```bash
# Option 1: Find and stop the process using port 9080
sudo lsof -i :9080
# Then kill the process or stop the conflicting service

# Option 2: Use different host ports
podman run -d -p 8080:9080 -p 8443:9443 --name liberty liberty-app:1.0.0
# Access at http://localhost:8080 instead

# Option 3: Remove existing container using the same name
podman rm -f liberty
podman run -d -p 9080:9080 -p 9443:9443 --name liberty liberty-app:1.0.0
```

### Build Fails

**Symptom:** Build errors during `podman build`

**Common causes and solutions:**

#### 1. Network timeout downloading Maven dependencies

```bash
# Retry the build (Maven caches dependencies)
podman build -t liberty-app:1.0.0 -f containers/liberty/Containerfile .

# Or increase timeout
podman build --timeout=1200 -t liberty-app:1.0.0 -f containers/liberty/Containerfile .
```

#### 2. Running from wrong directory

```
COPY sample-app/pom.xml ./pom.xml
COPY: /home/user/sample-app/pom.xml: no such file or directory
```

**Solution:** Run the build from the repository root:

```bash
cd /path/to/middleware-automation-platform
podman build -t liberty-app:1.0.0 -f containers/liberty/Containerfile .
```

#### 3. Insufficient disk space

```
Error: writing blob: storing blob to file: write /var/lib/containers/...: no space left on device
```

**Solution:**

```bash
# Check available space
df -h

# Clean up old images and containers
podman system prune -a

# Then retry the build
```

#### 4. Out of memory during Maven build

```
Error: spawn ENOMEM
```

**Solution:**

```bash
# For Podman on macOS, increase VM memory
podman machine stop
podman machine set --memory 4096
podman machine start

# For Docker Desktop, increase memory in Settings > Resources
```

### Container Won't Start

**Symptom:** Container exits immediately or shows status "Exited"

**Diagnosis:**

```bash
# Check container status
podman ps -a

# View container logs
podman logs liberty
```

**Common causes:**

#### 1. Liberty configuration error

Look for XML parsing errors in the logs:

```
[ERROR] CWWKG0075E: The value ... is not valid for attribute ...
```

**Solution:** Check `containers/liberty/server.xml` for syntax errors.

#### 2. Port conflict inside container

```
[ERROR] CWWKO0221E: TCP Channel ... cannot bind to host * and port 9080
```

**Solution:** The container's internal ports are conflicting. This is rare but can happen with custom images. Ensure no other processes in the container are using ports 9080 or 9443.

#### 3. Insufficient container resources

```
There is insufficient memory for the Java Runtime Environment to continue
```

**Solution:**

```bash
# Run with explicit memory limits
podman run -d -p 9080:9080 -p 9443:9443 --memory=1g --name liberty liberty-app:1.0.0
```

### Health Check Fails

**Symptom:** `curl http://localhost:9080/health/ready` returns connection refused or timeout

**Diagnosis:**

```bash
# Check if container is running
podman ps

# Check container logs for startup progress
podman logs -f liberty
```

**Common causes:**

#### 1. Liberty still starting

Liberty typically takes 30-60 seconds to start. Look for this message in the logs:

```
[AUDIT] CWWKF0011I: The server defaultServer is ready to run a smarter planet.
```

Wait for this message before testing health endpoints.

#### 2. Application deployment failed

Look for deployment errors in the logs:

```
[ERROR] CWWKZ0002E: An exception occurred while starting the application
```

**Solution:** Check the logs for the specific error and verify the WAR file was built correctly.

### Container Runtime Not Found

**Symptom:** `podman: command not found` or `docker: command not found`

**Solution:** Install the container runtime as described in [Prerequisites Check](#1-prerequisites-check-5-minutes).

For macOS with Podman, ensure the Podman machine is running:

```bash
podman machine start
```

### Additional Resources

- [Full Podman Deployment Guide](LOCAL_PODMAN_DEPLOYMENT.md)
- [End-to-End Testing Guide](END_TO_END_TESTING.md)
- [Credential Setup](CREDENTIAL_SETUP.md)
- [Terraform/AWS Troubleshooting](troubleshooting/terraform-aws.md)

---

## Cleanup

When you are done experimenting, clean up your local environment:

```bash
# Stop and remove the container
podman rm -f liberty

# Remove the image (optional, saves disk space)
podman rmi liberty-app:1.0.0

# Remove all unused images and containers (more aggressive cleanup)
podman system prune -a
```

---

## Summary

You have successfully:

1. Verified your system meets the prerequisites
2. Built a Liberty container image from source
3. Deployed and ran the container locally
4. Tested the sample application endpoints
5. Learned about next steps for different deployment scenarios

**Total time:** Approximately 25-30 minutes

For questions or issues not covered in this guide, see the full documentation in the `docs/` directory or open an issue in the repository.
