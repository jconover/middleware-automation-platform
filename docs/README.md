# Documentation Navigation

Welcome to the Middleware Automation Platform documentation. This index helps you find the right guide based on your goal.

## Quick Start: Which Guide Do I Need?

```
What do you want to do?
│
├─► "Test locally on my laptop"
│    └─► LOCAL_PODMAN_DEPLOYMENT.md (10 min)
│
├─► "Deploy to multi-node Kubernetes"
│    └─► LOCAL_KUBERNETES_DEPLOYMENT.md (30-45 min)
│
├─► "Deploy to AWS production"
│    └─► AWS_DEPLOYMENT.md (30-45 min)
│
├─► "Configure credentials first"
│    └─► CREDENTIAL_SETUP.md (Required before ANY deployment)
│
├─► "Test all deployment options"
│    └─► END_TO_END_TESTING.md (90 min)
│
└─► "Understand the project"
     └─► Main README.md
```

---

## Documentation Structure

```
docs/
├── README.md                          # This file - navigation index
├── CREDENTIAL_SETUP.md                # Required before deployment
├── AWS_DEPLOYMENT.md                  # AWS production deployment
├── LOCAL_KUBERNETES_DEPLOYMENT.md     # Multi-node K8s deployment
├── LOCAL_PODMAN_DEPLOYMENT.md         # Single-machine development
├── END_TO_END_TESTING.md              # Complete testing guide
├── KUBERNETES_SECURITY.md             # K8s security hardening
├── PROJECT_REVIEW_FINDINGS.md         # Code review and improvements
├── ALERTMANAGER_CONFIGURATION.md      # Webhook notification setup
│
├── architecture/
│   ├── HYBRID_ARCHITECTURE.md         # Local vs AWS comparison
│   └── diagrams/                      # Mermaid architecture diagrams
│       ├── hybrid-architecture.md
│       ├── ecs-vs-ec2.md
│       ├── data-flow.md
│       ├── cicd-pipeline.md
│       ├── network-topology.md
│       └── monitoring-architecture.md
│
├── plans/
│   └── ecs-migration-plan.md          # EC2 to ECS migration guide
│
└── troubleshooting/
    └── terraform-aws.md               # AWS/Terraform issues
```

---

## Getting Started

| Document                                       | When to Read          | Time   |
| ---------------------------------------------- | --------------------- | ------ |
| **[CREDENTIAL_SETUP.md](CREDENTIAL_SETUP.md)** | Before ANY deployment | 10 min |
| **[Main README](../README.md)**                | First time visiting   | 10 min |

---

## Deployment Guides

| Guide                                                                | Environment      | Time      | Best For             |
| -------------------------------------------------------------------- | ---------------- | --------- | -------------------- |
| **[LOCAL_PODMAN_DEPLOYMENT.md](LOCAL_PODMAN_DEPLOYMENT.md)**         | Single machine   | 10 min    | Quick testing, demos |
| **[LOCAL_KUBERNETES_DEPLOYMENT.md](LOCAL_KUBERNETES_DEPLOYMENT.md)** | Multi-node K8s   | 30-45 min | Homelab, staging     |
| **[AWS_DEPLOYMENT.md](AWS_DEPLOYMENT.md)**                           | AWS cloud        | 30-45 min | Production           |
| **[END_TO_END_TESTING.md](END_TO_END_TESTING.md)**                   | All environments | 90 min    | Full verification    |

### Deployment Decision Matrix

| Criteria          | Podman         | Kubernetes | AWS           |
| ----------------- | -------------- | ---------- | ------------- |
| Infrastructure    | Single machine | 3+ nodes   | Cloud-managed |
| Complexity        | Simple         | Moderate   | High          |
| Scaling           | Manual         | Automatic  | Automatic     |
| High availability | No             | Yes        | Yes           |
| Cost              | $0             | $0-300/mo  | $120-170/mo   |
| Use case          | Dev            | Staging    | Production    |

---

## Architecture Documentation

| Document                                                                           | Purpose                           |
| ---------------------------------------------------------------------------------- | --------------------------------- |
| **[HYBRID_ARCHITECTURE.md](architecture/HYBRID_ARCHITECTURE.md)**                  | Local vs AWS comparison           |
| **[ecs-vs-ec2.md](architecture/diagrams/ecs-vs-ec2.md)**                           | ECS Fargate vs EC2 instances      |
| **[data-flow.md](architecture/diagrams/data-flow.md)**                             | Request flow through application  |
| **[cicd-pipeline.md](architecture/diagrams/cicd-pipeline.md)**                     | Jenkins pipeline stages           |
| **[network-topology.md](architecture/diagrams/network-topology.md)**               | VPC, subnets, security groups     |
| **[monitoring-architecture.md](architecture/diagrams/monitoring-architecture.md)** | Prometheus, Grafana, AlertManager |

---

## Operations Guides

### Security

| Document                                             | Topic                       |
| ---------------------------------------------------- | --------------------------- |
| **[CREDENTIAL_SETUP.md](CREDENTIAL_SETUP.md)**       | All credentials             |
| **[KUBERNETES_SECURITY.md](KUBERNETES_SECURITY.md)** | K8s hardening, Pod Security |

### Monitoring

| Resource                                                           | Location                         |
| ------------------------------------------------------------------ | -------------------------------- |
| **[ALERTMANAGER_CONFIGURATION.md](ALERTMANAGER_CONFIGURATION.md)** | Webhook notifications            |
| **[monitoring/README.md](../monitoring/README.md)**                | Monitoring stack overview        |
| Prometheus config                                                  | `monitoring/prometheus/`         |
| Grafana dashboards                                                 | `monitoring/grafana/dashboards/` |
| Alert rules                                                        | `monitoring/prometheus/rules/`   |

### CI/CD

| Resource         | Location                                                   |
| ---------------- | ---------------------------------------------------------- |
| Main pipeline    | `ci-cd/Jenkinsfile`                                        |
| Pipeline diagram | [cicd-pipeline.md](architecture/diagrams/cicd-pipeline.md) |

---

## Troubleshooting

| Document                                                                                         | Covers               |
| ------------------------------------------------------------------------------------------------ | -------------------- |
| **[terraform-aws.md](troubleshooting/terraform-aws.md)**                                         | AWS/Terraform issues |
| [LOCAL_KUBERNETES_DEPLOYMENT.md#troubleshooting](LOCAL_KUBERNETES_DEPLOYMENT.md#troubleshooting) | Kubernetes issues    |
| [LOCAL_PODMAN_DEPLOYMENT.md#troubleshooting](LOCAL_PODMAN_DEPLOYMENT.md#troubleshooting)         | Podman issues        |

### Quick Troubleshooting

**Podman:**

- Container won't start: `podman logs liberty-server`
- Port conflicts: `ss -tlnp | grep 9080`

**Kubernetes:**

- ImagePullBackOff: Image not on all nodes
- LoadBalancer pending: MetalLB not configured
- Pods failing: `kubectl describe pod <name>`

**AWS:**

- ECS tasks failing: Check CloudWatch `/ecs/mw-prod-liberty`
- ALB 503: Wait 2-3 min for health checks
- Terraform fails: See [terraform-aws.md](troubleshooting/terraform-aws.md)

---

## Migration & Planning

| Document                                                 | Purpose                      |
| -------------------------------------------------------- | ---------------------------- |
| **[ecs-migration-plan.md](plans/ecs-migration-plan.md)** | EC2 to ECS Fargate migration |

---

## MetalLB IP Assignments (Local Kubernetes)

| Service      | IP             | Port |
| ------------ | -------------- | ---- |
| Liberty      | 192.168.68.200 | 9080 |
| Prometheus   | 192.168.68.201 | 9090 |
| Grafana      | 192.168.68.202 | 3000 |
| AlertManager | 192.168.68.203 | 9093 |
| ArgoCD       | 192.168.68.204 | 443  |
| AWX          | 192.168.68.205 | 80   |
| Jenkins      | 192.168.68.206 | 8080 |

---

## FAQs

**Q: Where do I start?**
A: Read [Main README](../README.md), then [LOCAL_PODMAN_DEPLOYMENT.md](LOCAL_PODMAN_DEPLOYMENT.md).

**Q: How do I deploy to production?**
A: [CREDENTIAL_SETUP.md](CREDENTIAL_SETUP.md) first, then [AWS_DEPLOYMENT.md](AWS_DEPLOYMENT.md).

**Q: ECS vs EC2?**
A: See [ecs-vs-ec2.md](architecture/diagrams/ecs-vs-ec2.md). ECS = serverless (default), EC2 = traditional VMs.

**Q: How do I stop AWS to save costs?**
A: Run `./automated/scripts/aws-stop.sh` or `--destroy` for full teardown.

**Q: Cost estimates?**
A: See [AWS_DEPLOYMENT.md](AWS_DEPLOYMENT.md) - approximately $120-170/month.

---

## Quick Links

**Most Used:**

- [Credentials Setup](CREDENTIAL_SETUP.md)
- [Podman Deployment](LOCAL_PODMAN_DEPLOYMENT.md)
- [Kubernetes Deployment](LOCAL_KUBERNETES_DEPLOYMENT.md)
- [AWS Deployment](AWS_DEPLOYMENT.md)

**Architecture:**

- [Hybrid Architecture](architecture/HYBRID_ARCHITECTURE.md)
- [ECS vs EC2](architecture/diagrams/ecs-vs-ec2.md)

**Troubleshooting:**

- [Terraform/AWS Issues](troubleshooting/terraform-aws.md)

---

**Last Updated:** 2025-12-30
