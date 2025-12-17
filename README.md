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
│   192.168.68.0/24               │          │    10.0.0.0/16          │
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
│  Cost: $0/month                │          │  Cost: ~$137/month      │
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

---

## AWS Cost Estimate (Production)

| Resource | Type | Monthly Cost |
|----------|------|--------------|
| EC2 Instances (x2) | t3.small | ~$30 |
| RDS PostgreSQL | db.t3.micro | ~$15 |
| ElastiCache Redis | cache.t3.micro | ~$12 |
| Application Load Balancer | - | ~$20 |
| NAT Gateway | - | ~$35 |
| Data Transfer | ~10GB | ~$10 |
| **TOTAL** | | **~$137/month** |

---

## Documentation

| Document | Description |
|----------|-------------|
| [MANUAL_DEPLOYMENT.md](./MANUAL_DEPLOYMENT.md) | Complete manual deployment guide |
| [docs/architecture/HYBRID_ARCHITECTURE.md](./docs/architecture/HYBRID_ARCHITECTURE.md) | Hybrid architecture details |
| [docs/timing-analysis/](./docs/timing-analysis/) | Timing comparison reports |

---

## License

This project is licensed under the MIT License.

---

## Author

**Justin** - Cloud Infrastructure & Platform Engineering

*Demonstrating enterprise-grade DevOps practices with measurable business impact.*
