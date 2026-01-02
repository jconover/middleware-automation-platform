# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-01-02

Initial release of the Enterprise Middleware Automation Platform, demonstrating the transformation from 7 hours manual deployment to approximately 28 minutes automated deployment.

### Added

#### Core Platform
- Open Liberty 24.0.0.x deployment with Jakarta EE 10 and MicroProfile 6.0
- Multi-stage container builds with automatic sample-app compilation
- Health endpoints (`/health/ready`, `/health/live`, `/health/started`)
- Prometheus-compatible metrics endpoint (`/metrics`)
- Sample REST API with OpenAPI annotations for testing and load testing

#### AWS Production Deployment
- **ECS Fargate support** - Serverless container deployment with auto-scaling (2-6 tasks)
- **EC2 instance support** - Traditional VM-based deployment with Ansible configuration
- **Dual-mode routing** - Run ECS and EC2 side-by-side with header-based routing for migration
- ECR container registry with lifecycle policies
- Application Load Balancer with health checks and target group routing
- RDS PostgreSQL database with Secrets Manager integration
- ElastiCache Redis for session caching
- VPC with public/private subnets and NAT gateway

#### Local Development Options
- **Kubernetes deployment** - 3-node Beelink homelab cluster with MetalLB load balancing
- **Podman deployment** - Single-machine container deployment for development
- Kustomize overlays for environment-specific configuration
- Docker Hub integration for local Kubernetes deployments

#### Infrastructure as Code
- Terraform modules for VPC, compute, database, and monitoring
- Terraform state management with S3 backend and DynamoDB locking
- Environment-specific configurations (dev, stage, prod)
- Variable validation and reusable module structure
- Cost-saving start/stop scripts with dry-run support

#### Configuration Management
- Ansible roles for Liberty, monitoring, and infrastructure components
- Molecule tests for Ansible role validation
- Dynamic AWS EC2 inventory for AWX integration
- Ansible Vault integration for secrets management
- Automatic AES-encoding of Liberty passwords using `securityUtility`

#### CI/CD Pipeline
- Jenkins pipeline with multi-stage builds (maven, podman, ansible)
- Security scanning integration in CI pipeline
- ECR push automation with Terraform outputs
- AWX/Tower integration for workflow automation

#### Monitoring and Observability
- Prometheus with file-based service discovery for ECS
- Grafana dashboards for Liberty metrics (ECS and Kubernetes variants)
- AlertManager configuration with runbook links
- ServiceMonitor for Kubernetes Prometheus Operator integration
- PrometheusRule for Liberty alerting

#### Documentation
- Architecture Decision Records (ADRs) for key technical decisions
- Comprehensive runbooks for operational procedures
- End-to-end testing guide for all deployment environments
- Credential setup guide for secure configuration
- Troubleshooting documentation for AWS and Terraform issues

### Security

- OIDC-based authentication for AWS access (no long-lived credentials)
- Least-privilege IAM policies with explicit resource ARNs
- Network policies and security groups with restricted access
- Secrets stored in AWS Secrets Manager (never in git)
- `no_log: true` on Ansible tasks handling sensitive data
- Kubernetes security hardening with NetworkPolicies

### Architecture Decisions

- [ADR-001] Dual compute model supporting both ECS Fargate and EC2 instances
- [ADR-002] Hybrid deployment architecture (local Kubernetes + AWS production)
- [ADR-003] File-based Prometheus discovery for ECS (vs native `ecs_sd_configs`)
- [ADR-004] AWS Secrets Manager for centralized secrets management
- [ADR-005] Open Liberty kernel-slim-java17-openj9-ubi as base container image

---

## Release Notes

### Upgrade Instructions

This is the initial release. For new deployments:

1. Review [docs/CREDENTIAL_SETUP.md](./docs/CREDENTIAL_SETUP.md) for required credentials
2. Choose your deployment model:
   - **AWS ECS**: Set `ecs_enabled = true` in `terraform.tfvars`
   - **AWS EC2**: Set `liberty_instance_count = 2` in `terraform.tfvars`
   - **Local Kubernetes**: Follow [docs/LOCAL_KUBERNETES_DEPLOYMENT.md](./docs/LOCAL_KUBERNETES_DEPLOYMENT.md)
   - **Local Podman**: Follow [docs/LOCAL_PODMAN_DEPLOYMENT.md](./docs/LOCAL_PODMAN_DEPLOYMENT.md)
3. Run `terraform apply` for AWS deployments

### Known Issues

- Grafana ECS dashboard must be imported manually (user-data 16KB limit)
- Prometheus official binaries do not include `ecs_sd_configs`; file-based discovery is used instead

### Cost Estimates

| Deployment | Monthly Cost |
|------------|--------------|
| ECS Fargate (default) | ~$170/month |
| EC2 Instances | ~$157/month |
| Local Kubernetes | $0/month |
| Local Podman | $0/month |

---

[1.0.0]: https://github.com/jconover/middleware-automation-platform/releases/tag/v1.0.0
