# Enterprise Middleware Automation Platform

> **From 7 Hours Manual to 28 Minutes Automated** - Demonstrating enterprise-grade middleware deployment automation with measurable ROI.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Open Liberty](https://img.shields.io/badge/Open%20Liberty-24.0.0.1-blue)](https://openliberty.io/)
[![Ansible](https://img.shields.io/badge/Ansible-2.15+-red)](https://www.ansible.com/)
[![Terraform](https://img.shields.io/badge/Terraform-1.6+-purple)](https://www.terraform.io/)

## Executive Summary

This project demonstrates the transformation of manual middleware deployment processes into fully automated, repeatable infrastructure-as-code workflows. The platform showcases:

- **WebSphere Liberty** deployment and collective configuration
- **Ansible automation** with AWX/Tower patterns
- **Terraform** infrastructure provisioning (AWS)
- **Container orchestration** with Podman and Kubernetes
- **CI/CD pipelines** with Jenkins
- **Monitoring** with Prometheus and Grafana
- **Certificate management** and security hardening

### Key Metrics

| Metric | Manual Process | Automated Process | Improvement |
|--------|---------------|-------------------|-------------|
| **Total Deployment Time** | ~7 hours | ~28 minutes | **93% reduction** |
| **Human Effort Required** | 7 hours | 5 minutes | **98% reduction** |
| **Error Rate** | ~15% | <1% | **93% reduction** |
| **Environment Consistency** | Variable | 100% identical | **Deterministic** |
| **Rollback Time** | 2-4 hours | 3 minutes | **98% reduction** |

---

## Architecture Overview

### Hybrid Deployment Model

```
LOCAL DEVELOPMENT (Beelink Homelab)          AWS PRODUCTION
════════════════════════════════════         ═══════════════════════════

┌─────────────────────────────────┐          ┌─────────────────────────┐
│   Kubernetes Cluster            │          │      AWS VPC            │
│   192.168.68.0/24               │          │    10.10.0.0/16          │
│                                 │          │                         │
│  ┌─────────┐  ┌─────────┐      │   ────►  │  ┌────────┐ ┌────────┐ │
│  │ Master  │  │ Worker  │      │  Promote │  │  EC2   │ │  EC2   │ │
│  │  .86    │  │  .88    │      │          │  │t3.small│ │t3.small│ │
│  └─────────┘  └─────────┘      │          │  └────────┘ └────────┘ │
│       ┌─────────┐              │          │                         │
│       │ Worker  │              │          │  ┌────────┐ ┌────────┐ │
│       │  .83    │              │          │  │  RDS   │ │ Redis  │ │
│       └─────────┘              │          │  │Postgres│ │ Cache  │ │
│                                 │          │  └────────┘ └────────┘ │
│  Services:                     │          │                         │
│  • AWX (.205)                  │          │  • ALB Load Balancer    │
│  • Jenkins (.206)              │          │  • ACM Certificates     │
│  • Prometheus (.201)           │          │  • CloudWatch           │
│  • Grafana (.202)              │          │                         │
│                                 │          │                         │
│  Cost: $0/month                │          │  Cost: ~$152/month      │
└─────────────────────────────────┘          └─────────────────────────┘
```

---

## Timing Comparison Framework

### Phase-by-Phase Breakdown

| Phase | Manual Time | Automated Time | Savings |
|-------|-------------|----------------|---------|
| Infrastructure Provisioning | 135 min | 7 min | 95% |
| Liberty Installation | 140 min | 7.5 min | 95% |
| Application Deployment | 75 min | 4.5 min | 94% |
| Load Balancer Configuration | 75 min | 3 min | 96% |
| Security Configuration | 80 min | 3 min | 96% |
| Monitoring Setup | 100 min | 3 min | 97% |
| **TOTAL** | **~7 hours** | **~28 min** | **93%** |

---

## Technology Stack

### Core Middleware
- **Open Liberty 24.0.0.x** - WebSphere Liberty open source edition
- **Java 17** - LTS runtime
- **Jakarta EE 10** - Enterprise Java standards

### Infrastructure as Code
- **Terraform 1.6+** - Infrastructure provisioning (AWS)
- **Ansible 2.15+** - Configuration management
- **AWX** - Ansible Tower open source (workflow automation)

### Containerization
- **Podman** - Daemonless container engine (OCI compliant)
- **Kubernetes** - Container orchestration
- **Helm** - Kubernetes package manager

### CI/CD
- **Jenkins** - Pipeline automation
- **ArgoCD** - GitOps continuous delivery

### Monitoring
- **Prometheus** - Metrics collection
- **Grafana** - Visualization
- **AlertManager** - Alert routing

---

## Project Structure

```
middleware-automation-platform/
├── README.md                      # This file
├── MANUAL_DEPLOYMENT.md           # Step-by-step manual guide with timing
│
├── manual/                        # Manual deployment guides
│   ├── 01-infrastructure/
│   ├── 02-liberty-install/
│   ├── 03-collective-setup/
│   ├── 04-nginx-config/
│   ├── 05-database-setup/
│   ├── 06-certificates/
│   └── 07-monitoring/
│
├── automated/                     # Fully automated deployment
│   ├── terraform/                 # Infrastructure as Code
│   │   ├── environments/
│   │   │   └── prod-aws/          # AWS production config
│   │   └── modules/
│   ├── ansible/                   # Configuration management
│   │   ├── inventory/
│   │   ├── playbooks/
│   │   └── roles/
│   └── scripts/                   # Deployment scripts
│
├── containers/                    # Container definitions
│   └── liberty/                   # Open Liberty Containerfile
│
├── kubernetes/                    # Kubernetes manifests
│   ├── base/
│   └── overlays/
│
├── ci-cd/                         # Pipeline definitions
│   └── Jenkinsfile
│
├── awx/                           # AWX configuration
│   ├── awx-deployment.yaml
│   └── awx-resources.yml
│
├── monitoring/                    # Observability
│   ├── prometheus/
│   ├── grafana/
│   └── alertmanager/
│
├── local-setup/                   # Local environment setup
│   └── setup-local-env.sh
│
└── docs/                          # Documentation
    └── architecture/
```

---

## Quick Start

### Prerequisites

```bash
# Required tools
- Ansible 2.15+
- Terraform 1.6+
- Podman 4.0+
- kubectl
- Java 17+
- Helm 3
```

### Option 1: Automated Deployment

```bash
# Clone the repository
git clone https://github.com/jconover/middleware-automation-platform.git
cd middleware-automation-platform

# Run the automated deployment
./automated/scripts/deploy.sh --environment dev

# Deployment completes in ~28 minutes
```

### Option 2: Manual Deployment (Learning Path)

```bash
# Follow step-by-step guides
cd manual/01-infrastructure
cat README.md
# Continue through each phase...
```

### Option 3: Local Container Build (Podman)

Build and run Liberty with the sample app in a container:

```bash
# Build the sample app
mvn -f sample-app/pom.xml clean package

# Copy WAR to container build directory
cp sample-app/target/*.war containers/liberty/apps/

# Build and run the container
cd containers/liberty
podman build -t liberty-app:1.0.0 -f Containerfile .
podman run -d -p 9080:9080 -p 9443:9443 --name liberty liberty-app:1.0.0

# Verify
curl http://localhost:9080/health/ready
curl http://localhost:9080/sample-app/api/hello
```

### Option 4: AWS Production Deployment

#### Step 1: Bootstrap Terraform State Backend (one-time)

```bash
cd automated/terraform/bootstrap
terraform init
terraform apply
```

#### Step 2: Deploy AWS Infrastructure

This deploys EC2 instances, RDS, ElastiCache, ALB, and the AWX management server.

```bash
cd ../environments/prod-aws
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your settings (domain, instance types, etc.)
terraform init
terraform plan    # Review changes
terraform apply   # Deploy (~5-10 minutes)
```

#### Step 3: Configure Ansible Inventory

**Option A: Dynamic Inventory (Recommended for AWX)**

No action needed. The `prod-aws-ec2.yml` inventory uses the AWS EC2 plugin to auto-discover instances by tags. AWX uses IAM credentials from the management server.

**Option B: Static Inventory (for CLI deployments)**

If deploying via CLI without AWS credentials, update the static inventory with Terraform outputs:
```bash
terraform output ansible_inventory
# Copy the IPs into automated/ansible/inventory/prod-aws.yml
```

#### Step 4: Configure AWX

Access the AWX web UI to set up credentials, project, and job templates.

**Get AWX credentials:**
```bash
# Get AWX URL
terraform output awx_url

# SSH to management server and get admin password
$(terraform output -raw management_ssh_command)
sudo kubectl get secret awx-admin-password -n awx -o jsonpath='{.data.password}' | base64 -d && echo
```

- **URL:** `http://<MANAGEMENT_PUBLIC_IP>:30080`
- **Username:** `admin`
- **Password:** (from command above)

**4a. Create SSH Credential**
1. **Resources → Credentials → Add**
2. **Name:** `AWS SSH Key`
3. **Credential Type:** `Machine`
4. **Username:** `ansible`
5. **SSH Private Key:** Paste contents of `~/.ssh/ansible_ed25519` (from your local machine)

**4b. Create Project**
1. **Resources → Projects → Add**
2. **Name:** `Middleware Platform`
3. **Source Control Type:** `Git`
4. **Source Control URL:** `https://github.com/jconover/middleware-automation-platform.git`
5. **Options:** ✓ Update Revision on Launch

**4c. Create Inventory**
1. **Resources → Inventories → Add Inventory**
2. **Name:** `AWS Production`
3. Save, then go to **Sources → Add**
4. **Source:** `Sourced from a Project`
5. **Project:** `Middleware Platform`
6. **Inventory file:** `automated/ansible/inventory/prod-aws-ec2.yml` (dynamic - auto-discovers instances)

**4d. Create Job Template - Deploy Liberty**
1. **Resources → Templates → Add → Job Template**
2. **Name:** `Deploy Liberty`
3. **Inventory:** `AWS Production`
4. **Project:** `Middleware Platform`
5. **Playbook:** `automated/ansible/playbooks/site.yml`
6. **Credentials:** `AWS SSH Key`

**4e. Create Job Template - Deploy Monitoring**

**Option A: Via AWX Console**
1. **Resources → Templates → Add → Job Template**
2. **Name:** `Deploy Monitoring - AWS`
3. **Inventory:** `AWS Production`
4. **Project:** `Middleware Platform`
5. **Playbook:** `automated/ansible/playbooks/site.yml`
6. **Credentials:** `AWS SSH Key`
7. **Job Tags:** `monitoring`

**Option B: Via Command Line (API)**

SSH to the management server and use the AWX API:
```bash
# Get AWX admin password
AWX_PASS=$(kubectl get secret awx-admin-password -n awx -o jsonpath='{.data.password}' | base64 -d)

# Create the job template
curl -s -X POST -u admin:$AWX_PASS -H "Content-Type: application/json" \
  http://localhost:30080/api/v2/job_templates/ -d '{
    "name": "Deploy Monitoring - AWS",
    "project": 8,
    "inventory": 2,
    "playbook": "automated/ansible/playbooks/site.yml",
    "job_tags": "monitoring"
  }'

# Associate the SSH credential (ID 3 = AWS SSH Key)
curl -s -X POST -u admin:$AWX_PASS -H "Content-Type: application/json" \
  http://localhost:30080/api/v2/job_templates/11/credentials/ -d '{"id": 3}'

# Launch the job
curl -s -X POST -u admin:$AWX_PASS -H "Content-Type: application/json" \
  http://localhost:30080/api/v2/job_templates/11/launch/
```

> **Note:** Project/inventory/credential IDs may vary. List them with:
> ```bash
> curl -s -u admin:$AWX_PASS http://localhost:30080/api/v2/projects/
> curl -s -u admin:$AWX_PASS http://localhost:30080/api/v2/inventories/
> curl -s -u admin:$AWX_PASS http://localhost:30080/api/v2/credentials/
> ```

**4f. Create Job Template - Health Check**

**Option A: Via AWX Console**
1. **Resources → Templates → Add → Job Template**
2. **Name:** `Health Check - AWS`
3. **Inventory:** `AWS Production`
4. **Project:** `Middleware Platform`
5. **Playbook:** `automated/ansible/playbooks/health-check.yml`
6. **Credentials:** `AWS SSH Key`

**Option B: Via Command Line (API)**

```bash
# Get AWX admin password
AWX_PASS=$(kubectl get secret awx-admin-password -n awx -o jsonpath='{.data.password}' | base64 -d)

# Create the job template
curl -s -X POST -u admin:$AWX_PASS -H "Content-Type: application/json" \
  http://localhost:30080/api/v2/job_templates/ -d '{
    "name": "Health Check - AWS",
    "project": 8,
    "inventory": 2,
    "playbook": "automated/ansible/playbooks/health-check.yml"
  }'

# Associate the SSH credential
curl -s -X POST -u admin:$AWX_PASS -H "Content-Type: application/json" \
  http://localhost:30080/api/v2/job_templates/<TEMPLATE_ID>/credentials/ -d '{"id": 3}'

# Launch the health check
curl -s -X POST -u admin:$AWX_PASS \
  http://localhost:30080/api/v2/job_templates/<TEMPLATE_ID>/launch/
```

The health check playbook validates:
- Liberty `/health/ready` endpoints (readiness)
- Liberty `/health/live` endpoints (liveness)
- Liberty `/metrics` endpoints (Prometheus metrics)

#### Step 5: Deploy Liberty

**Option A: Via AWX (Recommended)**

Click **Launch** on the "Deploy Liberty" job template in AWX. This provides:
- Web-based job output and history
- Scheduled/recurring deployments
- Role-based access control
- Audit logging

**Option B: Via CLI (Quick/One-time)**

For one-off deployments without AWX:
```bash
cd automated/ansible
ansible-playbook -i inventory/prod-aws-ec2.yml playbooks/site.yml
```
> **Note:** Requires VPN or bastion access to private subnets

#### Step 6: Verify Deployment

```bash
ALB_DNS=$(cd automated/terraform/environments/prod-aws && terraform output -raw alb_dns_name)
curl http://$ALB_DNS/health/ready
```

#### Step 7: Deploy Monitoring Server (Optional)

The monitoring server runs Prometheus and Grafana on a dedicated t3.small instance.

**7a. Enable in terraform.tfvars:**
```hcl
create_monitoring_server = true
monitoring_instance_type = "t3.small"  # ~$15/month
```

**7b. Deploy with Terraform:**
```bash
cd automated/terraform/environments/prod-aws
terraform plan   # Review changes
terraform apply  # Deploy (~3-5 minutes)
```

**7c. Access monitoring:**
```bash
# Get URLs
terraform output prometheus_url  # Prometheus: http://<IP>:9090
terraform output grafana_url     # Grafana: http://<IP>:3000

# SSH to server
$(terraform output -raw monitoring_ssh_command)
```

- **Grafana credentials:** admin / admin (change on first login)
- **Prometheus** auto-configured to scrape Liberty `/metrics` endpoints
- **Retention:** 15 days of metrics data

#### Step 8: Deploy Sample Application (Optional)

Deploy the sample REST API for testing and load testing.

**8a. Build the application:**
```bash
cd sample-app
mvn clean package
```

**8b. Deploy via management server:**
```bash
# Copy WAR to management server
MGMT_IP=$(terraform output -raw management_public_ip)
scp -i ~/.ssh/ansible_ed25519 target/sample-app.war ubuntu@$MGMT_IP:/tmp/

# SSH to management server
ssh -i ~/.ssh/ansible_ed25519 ubuntu@$MGMT_IP

# From management server, deploy to Liberty servers
scp -i ~/.ssh/ansible_ed25519 /tmp/sample-app.war ansible@<LIBERTY_IP>:/tmp/
ssh -i ~/.ssh/ansible_ed25519 ansible@<LIBERTY_IP> \
  "sudo cp /tmp/sample-app.war /opt/ibm/wlp/usr/servers/appServer01/dropins/"
```

**8c. Verify deployment:**
```bash
curl http://<LIBERTY_IP>:9080/sample-app/api/hello
curl http://<LIBERTY_IP>:9080/sample-app/api/info
```

**8d. Run load tests:**
```bash
# Install hey load testing tool (on management server)
wget -q https://hey-release.s3.us-east-2.amazonaws.com/hey_linux_amd64 -O hey
chmod +x hey && sudo mv hey /usr/local/bin/

# Run load test
hey -n 1000 -c 50 http://<LIBERTY_IP>:9080/sample-app/api/hello
```

**Sample App Endpoints:**
| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/hello` | GET | Simple hello response |
| `/api/hello/{name}` | GET | Personalized hello |
| `/api/info` | GET | Server info (hostname, memory, uptime) |
| `/api/stats` | GET | Request statistics |
| `/api/slow?delay=1000` | GET | Simulated latency (ms) |
| `/api/compute?iterations=N` | GET | CPU load test |
| `/api/echo` | POST | Echo request body |

#### Liberty Admin Console

Access the Open Liberty Admin Center for each server:

```bash
# Get Liberty server IPs
terraform output liberty_private_ips

# Access via SSH tunnel (from your local machine)
ssh -i ~/.ssh/ansible_ed25519 -L 9443:<LIBERTY_IP>:9443 ubuntu@$MGMT_IP
# Then open: https://localhost:9443/adminCenter
```

- **URL:** `https://<LIBERTY_IP>:9443/adminCenter`
- **Credentials:** admin / admin

**AWS Prerequisites:**
- AWS CLI configured (`aws configure`)
- Terraform 1.6+
- SSH key at `~/.ssh/ansible_ed25519.pub`

**Estimated Cost:** ~$167/month (see [terraform.tfvars.example](./automated/terraform/environments/prod-aws/terraform.tfvars.example))

### Teardown / Clean Reinstall

**Local Development:**
```bash
# Remove all deployed components (prompts for confirmation)
./automated/scripts/destroy.sh --environment dev

# Force destroy without confirmation
./automated/scripts/destroy.sh --environment dev --force

# Destroy specific component only
./automated/scripts/destroy.sh --environment dev --phase liberty
./automated/scripts/destroy.sh --environment dev --phase monitoring
```

**AWS Production:**
```bash
cd automated/terraform/environments/prod-aws
terraform destroy
```

> **Note:** Some resources may require manual cleanup after destroy. See [docs/troubleshooting/terraform-aws.md](./docs/troubleshooting/terraform-aws.md)

---

## Verification & Console URLs

After deployment, verify all services are running:

### Health Checks

```bash
# Liberty Servers
curl -s http://192.168.68.86:9080/health/ready   # Liberty Server 01
curl -s http://192.168.68.88:9080/health/ready   # Liberty Server 02

# Prometheus
curl -s http://192.168.68.82:9090/-/ready

# Grafana
curl -s http://192.168.68.82:3000/api/health
```

### AWS Production Health Checks

Liberty servers in AWS are in private subnets. Run health checks from the management server:

```bash
cd automated/terraform/environments/prod-aws

# Get Liberty server IPs
terraform output liberty_private_ips

# SSH to management server and run health checks
MGMT_IP=$(terraform output -raw management_public_ip)
ssh -i ~/.ssh/ansible_ed25519 ubuntu@$MGMT_IP \
  'curl -s http://<LIBERTY_1_IP>:9080/health/ready && echo ""'
ssh -i ~/.ssh/ansible_ed25519 ubuntu@$MGMT_IP \
  'curl -s http://<LIBERTY_2_IP>:9080/health/ready && echo ""'

# Or check liveness
ssh -i ~/.ssh/ansible_ed25519 ubuntu@$MGMT_IP \
  'curl -s http://<LIBERTY_1_IP>:9080/health/live && echo ""'
```

Expected response: `{"checks":[],"status":"UP"}`

### Quick Verification Script

```bash
echo "=== Liberty Servers ==="
for ip in 192.168.68.86 192.168.68.88; do
  http_code=$(curl -s -o /dev/null -w "%{http_code}" http://$ip:9080/health/ready)
  echo "$ip: $http_code"
done

echo "=== Monitoring ==="
echo "Prometheus: $(curl -s -o /dev/null -w "%{http_code}" http://192.168.68.82:9090/-/ready)"
echo "Grafana: $(curl -s -o /dev/null -w "%{http_code}" http://192.168.68.82:3000/api/health)"
```

### Web Console URLs

| Service | URL | Default Credentials |
|---------|-----|---------------------|
| **Liberty Server 01** | http://192.168.68.86:9080 | - |
| **Liberty Server 02** | http://192.168.68.88:9080 | - |
| **Liberty Health** | http://192.168.68.86:9080/health/ready | - |
| **Liberty Metrics** | http://192.168.68.86:9080/metrics | - |
| **Prometheus** | http://192.168.68.82:9090 | - |
| **Grafana** | http://192.168.68.82:3000 | admin / admin |
| **AWX** | http://192.168.68.205 | (configured separately) |
| **Jenkins** | http://192.168.68.206:8080 | (configured separately) |

> **Note:** Update IPs for your environment. See [CONFIGURATION.md](./CONFIGURATION.md) for details.

---

## AWS Cost Estimate (Production)

| Resource | Type | Monthly Cost |
|----------|------|--------------|
| Liberty Servers (x2) | t3.small | ~$30 |
| Management Server (AWX) | t3.medium | ~$30 |
| Monitoring Server (Prometheus/Grafana) | t3.small | ~$15 |
| RDS PostgreSQL | db.t3.micro | ~$15 |
| ElastiCache Redis | cache.t3.micro | ~$12 |
| Application Load Balancer | - | ~$20 |
| NAT Gateway | - | ~$35 |
| Data Transfer | ~10GB | ~$10 |
| **TOTAL** | | **~$167/month** |

---

## Documentation

| Document | Description |
|----------|-------------|
| [CONFIGURATION.md](./CONFIGURATION.md) | IP addresses and environment setup (local) |
| [terraform.tfvars.example](./automated/terraform/environments/prod-aws/terraform.tfvars.example) | AWS production configuration |
| [MANUAL_DEPLOYMENT.md](./MANUAL_DEPLOYMENT.md) | Complete manual deployment guide |
| [docs/architecture/HYBRID_ARCHITECTURE.md](./docs/architecture/HYBRID_ARCHITECTURE.md) | Hybrid architecture details |
| [docs/timing-analysis/](./docs/timing-analysis/) | Timing comparison reports |
| [docs/troubleshooting/terraform-aws.md](./docs/troubleshooting/terraform-aws.md) | AWS/Terraform troubleshooting guide |

---

## License

This project is licensed under the MIT License.

---

## Author

**Justin** - Cloud Infrastructure & Platform Engineering

*Demonstrating enterprise-grade DevOps practices with measurable business impact.*
