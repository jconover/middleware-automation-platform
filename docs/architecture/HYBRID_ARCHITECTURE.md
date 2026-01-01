# Hybrid Architecture Guide

## Overview

```
LOCAL DEVELOPMENT                    AWS PRODUCTION
═══════════════════                  ═══════════════════

Beelink Homelab                      AWS VPC
192.168.68.0/24                      10.10.0.0/16

┌─────────────┐                      ┌─────────────┐
│ k8s-master  │                      │   EC2 x2    │
│    .86      │        ────►         │  t3.small   │
├─────────────┤       Promote        ├─────────────┤
│ k8s-worker  │                      │    RDS      │
│    .88      │                      │  Postgres   │
├─────────────┤                      ├─────────────┤
│ k8s-worker  │                      │ ElastiCache │
│    .83      │                      │   Redis     │
└─────────────┘                      └─────────────┘

Services:                            Services:
• AWX (.205)                         • ALB
• Jenkins (.206)                     • ACM Certs
• Prometheus (.201)                  • CloudWatch
• Grafana (.202)

Cost: $0/month                       Cost: ~$157-170/month
```

## MetalLB IP Assignments

| Service | IP Address |
|---------|------------|
| NGINX Ingress | 192.168.68.200 |
| Prometheus | 192.168.68.201 |
| Grafana | 192.168.68.202 |
| AlertManager | 192.168.68.203 |
| ArgoCD | 192.168.68.204 |
| AWX | 192.168.68.205 |
| Jenkins | 192.168.68.206 |
| Apps | 192.168.68.210+ |

## AWS Monthly Cost Breakdown

> **Note:** Cost estimates vary based on compute model and usage patterns.
> For the most accurate estimate, use the [AWS Pricing Calculator](https://calculator.aws/).
> See the main [README.md](../../README.md#aws-cost-estimate-production) for detailed breakdowns.
>
> *Last updated: January 2026*

| Resource | Type | Cost |
|----------|------|------|
| Liberty Compute | ECS Fargate or EC2 x2 | ~$30-50 |
| Management Server (AWX) | t3.medium | ~$30 |
| Monitoring Server | t3.small | ~$15 |
| RDS | db.t3.micro | ~$15 |
| ElastiCache | cache.t3.micro | ~$12 |
| ALB | - | ~$20 |
| NAT Gateway | - | ~$35 |
| **TOTAL** | | **~$157-170/month** |

**Compute Options:**
- **ECS Fargate** (default): ~$170/month - serverless, auto-scaling
- **EC2 Instances**: ~$157/month - traditional, Ansible-managed
