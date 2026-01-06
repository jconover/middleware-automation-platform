# AWS Feature Parity Implementation Plan

**Created:** 2026-01-06
**Status:** Draft
**Effort Estimate:** 1-2 weeks

## Overview

This document details the implementation plan to add six missing features from `environments/prod-aws/` to `environments/aws/`, achieving full feature parity and enabling deprecation of the legacy environment.

### Missing Features

| Feature | Source File | Lines | Priority |
|---------|-------------|-------|----------|
| Management Server (AWX/Jenkins) | `management.tf` | ~500 | HIGH |
| Route53 DNS Failover | `route53.tf` | ~550 | HIGH |
| S3 Cross-Region Replication | `s3-replication.tf` | ~700 | MEDIUM |
| ECR Cross-Region Replication | `ecr.tf` (partial) | ~130 | MEDIUM |
| X-Ray Distributed Tracing | `xray.tf` | ~315 | LOW |
| SLO/SLI CloudWatch Alarms | `slo-alarms.tf` | ~640 | MEDIUM |

---

## Implementation Order

Dependencies dictate this order:

1. **Module outputs** - Add missing outputs to loadbalancer module
2. **X-Ray** - Least dependencies, ECS module already supports it
3. **ECR Replication** - Simple ECS module extension
4. **Management Server** - Standalone, no module dependencies
5. **SLO Alarms** - Requires loadbalancer module outputs
6. **Route53 Failover** - Requires SLO SNS topic (optional)
7. **S3 Replication** - Most complex, requires multiple module outputs

---

## Feature 1: Management Server (AWX/Jenkins)

### Recommendation: New standalone file (`management.tf`)

The management server is self-contained with its own security group, IAM roles, EIP, and EC2 instance.

### Files to Create

| File | Action |
|------|--------|
| `environments/aws/management.tf` | Copy from `prod-aws/management.tf` |
| `environments/aws/templates/management-user-data.sh` | Copy from `prod-aws/templates/` |

### Variables to Add (`variables.tf`)

```hcl
variable "create_management_server" {
  description = "Whether to create the AWX/Jenkins management server"
  type        = bool
  default     = false
}

variable "management_instance_type" {
  description = "EC2 instance type for management server (AWX needs 4GB+ RAM)"
  type        = string
  default     = "t3.medium"
  validation {
    condition     = can(regex("^[a-z][0-9][a-z]?\\.(small|medium|large|[0-9]*xlarge|metal)$", var.management_instance_type))
    error_message = "Management instance type must be a valid EC2 instance type."
  }
}
```

### Outputs to Add (`outputs.tf`)

```hcl
output "management_public_ip" {
  description = "Public IP of the management server"
  value       = var.create_management_server ? aws_eip.management[0].public_ip : null
}

output "management_ssh_command" {
  description = "SSH command to connect to management server"
  value       = var.create_management_server ? "ssh -i ~/.ssh/ansible_ed25519 ubuntu@${aws_eip.management[0].public_ip}" : null
}

output "awx_url" {
  description = "URL of the AWX web interface"
  value       = var.create_management_server ? "http://${aws_eip.management[0].public_ip}:30080" : null
}
```

### tfvars Updates

| File | Value |
|------|-------|
| `dev.tfvars` | `create_management_server = false` |
| `stage.tfvars` | `create_management_server = false` |
| `prod.tfvars` | `create_management_server = true` |

---

## Feature 2: Route53 DNS Failover

### Recommendation: New standalone file (`route53.tf`)

DNS failover creates health checks, CloudWatch alarms, S3 maintenance pages, and DNS records.

### Files to Create

| File | Action |
|------|--------|
| `environments/aws/route53.tf` | Copy from `prod-aws/route53.tf` with modifications |

### Variables to Add (`variables.tf`)

```hcl
variable "domain_name" {
  description = "Domain name for Route53 (e.g., app.example.com)"
  type        = string
  default     = ""
}

variable "enable_route53_failover" {
  description = "Enable Route53 health checks and DNS failover routing"
  type        = bool
  default     = false
}

variable "route53_zone_name" {
  description = "Route53 hosted zone name (defaults to domain_name)"
  type        = string
  default     = ""
}

variable "route53_health_check_interval" {
  description = "Interval in seconds between Route53 health checks (10 or 30)"
  type        = number
  default     = 30
}

variable "route53_health_check_failure_threshold" {
  description = "Number of consecutive failures before failover (1-10)"
  type        = number
  default     = 3
}

variable "route53_latency_threshold_ms" {
  description = "Threshold in milliseconds for Route53 latency alarm"
  type        = number
  default     = 500
}

variable "enable_maintenance_page" {
  description = "Create S3-hosted maintenance page as failover target"
  type        = bool
  default     = true
}

variable "create_www_record" {
  description = "Create www subdomain CNAME pointing to apex domain"
  type        = bool
  default     = true
}
```

### Changes to `locals.tf`

```hcl
locals {
  # ... existing locals ...
  route53_enabled = var.domain_name != "" && var.enable_route53_failover
}
```

### Outputs to Add

```hcl
output "route53_health_check_id" {
  description = "Route53 health check ID"
  value       = local.route53_enabled ? aws_route53_health_check.alb[0].id : null
}

output "maintenance_page_url" {
  description = "URL of the S3 maintenance page"
  value       = local.route53_enabled && var.enable_maintenance_page ? "http://${aws_s3_bucket_website_configuration.maintenance[0].website_endpoint}" : null
}
```

### tfvars Updates

| File | Value |
|------|-------|
| `dev.tfvars` | `enable_route53_failover = false` |
| `stage.tfvars` | `enable_route53_failover = false` |
| `prod.tfvars` | `enable_route53_failover = true`, `domain_name = ""` (user sets) |

---

## Feature 3: S3 Cross-Region Replication

### Recommendation: New standalone file (`s3-replication.tf`)

Requires secondary AWS provider for DR region and creates S3 buckets, IAM roles, and replication configurations.

### Changes to `providers.tf`

```hcl
provider "aws" {
  alias  = "dr"
  region = var.dr_region

  default_tags {
    tags = merge(
      {
        Project     = var.project
        Environment = var.environment
        ManagedBy   = "terraform"
        Purpose     = "disaster-recovery"
      },
      var.additional_tags
    )
  }
}
```

### Module Changes Required

Add to `modules/loadbalancer/outputs.tf`:

```hcl
output "alb_logs_bucket_arn" {
  description = "ARN of the ALB access logs S3 bucket"
  value       = var.enable_access_logs ? aws_s3_bucket.alb_logs[0].arn : null
}

output "alb_logs_bucket_id" {
  description = "Name of the ALB access logs S3 bucket"
  value       = var.enable_access_logs ? aws_s3_bucket.alb_logs[0].id : null
}
```

### Variables to Add (`variables.tf`)

```hcl
variable "enable_s3_replication" {
  description = "Enable S3 cross-region replication for disaster recovery"
  type        = bool
  default     = false
}

variable "dr_region" {
  description = "AWS region for disaster recovery replication"
  type        = string
  default     = "us-west-2"
}
```

### tfvars Updates

| File | Value |
|------|-------|
| `dev.tfvars` | `enable_s3_replication = false` |
| `stage.tfvars` | `enable_s3_replication = false` |
| `prod.tfvars` | `enable_s3_replication = true`, `dr_region = "us-west-2"` |

---

## Feature 4: ECR Cross-Region Replication

### Recommendation: Extend existing ECS module

ECR is created by the ECS module. Add replication as optional functionality.

### Changes to `modules/ecs/main.tf`

```hcl
# ECR Cross-Region Replication Configuration
resource "aws_ecr_replication_configuration" "cross_region" {
  count = var.ecr_replication_enabled ? 1 : 0

  replication_configuration {
    rule {
      destination {
        region      = var.ecr_replication_region
        registry_id = data.aws_caller_identity.current.account_id
      }
      repository_filter {
        filter      = "${var.name_prefix}-liberty"
        filter_type = "PREFIX_MATCH"
      }
    }
  }
}
```

### Variables to Add to `modules/ecs/variables.tf`

```hcl
variable "ecr_replication_enabled" {
  description = "Enable ECR cross-region replication"
  type        = bool
  default     = false
}

variable "ecr_replication_region" {
  description = "AWS region for ECR replication"
  type        = string
  default     = "us-west-2"
}
```

### Variables to Add to `environments/aws/variables.tf`

```hcl
variable "ecr_replication_enabled" {
  description = "Enable ECR cross-region replication for disaster recovery"
  type        = bool
  default     = false
}

variable "ecr_replication_region" {
  description = "AWS region for ECR cross-region replication"
  type        = string
  default     = "us-west-2"
}
```

### Changes to `main.tf`

Update ECS module call:

```hcl
module "ecs" {
  # ... existing config ...

  ecr_replication_enabled = var.ecr_replication_enabled
  ecr_replication_region  = var.ecr_replication_region
}
```

### tfvars Updates

| File | Value |
|------|-------|
| `dev.tfvars` | `ecr_replication_enabled = false` |
| `stage.tfvars` | `ecr_replication_enabled = false` |
| `prod.tfvars` | `ecr_replication_enabled = true` |

---

## Feature 5: X-Ray Distributed Tracing

### Recommendation: New standalone file (`xray.tf`)

X-Ray creates sampling rules, groups, and dashboards. The ECS module already has X-Ray IAM support.

### Files to Create

| File | Action |
|------|--------|
| `environments/aws/xray.tf` | Create with sampling rules, groups, dashboard |

### Variables to Add (`variables.tf`)

```hcl
variable "enable_xray" {
  description = "Enable AWS X-Ray for distributed tracing"
  type        = bool
  default     = false
}

variable "xray_sampling_rate" {
  description = "Default sampling rate for X-Ray traces (0.0 to 1.0)"
  type        = number
  default     = 0.1
  validation {
    condition     = var.xray_sampling_rate >= 0 && var.xray_sampling_rate <= 1
    error_message = "X-Ray sampling rate must be between 0.0 and 1.0."
  }
}
```

### Changes to `main.tf`

```hcl
module "ecs" {
  # ... existing config ...
  enable_xray = var.enable_xray
}
```

### tfvars Updates

| File | Value |
|------|-------|
| `dev.tfvars` | `enable_xray = false` |
| `stage.tfvars` | `enable_xray = false` |
| `prod.tfvars` | `enable_xray = true`, `xray_sampling_rate = 0.1` |

---

## Feature 6: SLO/SLI CloudWatch Alarms

### Recommendation: New standalone file (`slo-alarms.tf`)

Creates SNS topics, CloudWatch alarms, and composite alarms for SLO monitoring.

### Module Changes Required

Add to `modules/loadbalancer/outputs.tf`:

```hcl
output "ecs_target_group_arn_suffix" {
  description = "ARN suffix of the ECS target group"
  value       = var.create_ecs_target_group ? aws_lb_target_group.ecs[0].arn_suffix : null
}
```

### Variables to Add (`variables.tf`)

```hcl
variable "enable_slo_alarms" {
  description = "Enable comprehensive SLO/SLI CloudWatch alarms"
  type        = bool
  default     = false
}

variable "slo_alert_email" {
  description = "Email for SLO alerts (uses security_alert_email if not set)"
  type        = string
  default     = ""
}
```

### tfvars Updates

| File | Value |
|------|-------|
| `dev.tfvars` | `enable_slo_alarms = false` |
| `stage.tfvars` | `enable_slo_alarms = true` |
| `prod.tfvars` | `enable_slo_alarms = true` |

---

## Summary: All New Variables

| Variable | Type | Default | Feature |
|----------|------|---------|---------|
| `create_management_server` | bool | false | Management |
| `management_instance_type` | string | "t3.medium" | Management |
| `domain_name` | string | "" | Route53 |
| `enable_route53_failover` | bool | false | Route53 |
| `route53_zone_name` | string | "" | Route53 |
| `route53_health_check_interval` | number | 30 | Route53 |
| `route53_health_check_failure_threshold` | number | 3 | Route53 |
| `route53_latency_threshold_ms` | number | 500 | Route53 |
| `enable_maintenance_page` | bool | true | Route53 |
| `create_www_record` | bool | true | Route53 |
| `enable_s3_replication` | bool | false | S3 DR |
| `dr_region` | string | "us-west-2" | S3 DR |
| `ecr_replication_enabled` | bool | false | ECR DR |
| `ecr_replication_region` | string | "us-west-2" | ECR DR |
| `enable_xray` | bool | false | X-Ray |
| `xray_sampling_rate` | number | 0.1 | X-Ray |
| `enable_slo_alarms` | bool | false | SLO |
| `slo_alert_email` | string | "" | SLO |

---

## Files to Create

| File | Lines | Source |
|------|-------|--------|
| `environments/aws/management.tf` | ~500 | prod-aws/management.tf |
| `environments/aws/route53.tf` | ~550 | prod-aws/route53.tf |
| `environments/aws/s3-replication.tf` | ~700 | prod-aws/s3-replication.tf |
| `environments/aws/xray.tf` | ~200 | prod-aws/xray.tf (partial) |
| `environments/aws/slo-alarms.tf` | ~640 | prod-aws/slo-alarms.tf |
| `environments/aws/templates/management-user-data.sh` | ~82 | prod-aws/templates/ |

---

## Files to Modify

| File | Changes |
|------|---------|
| `environments/aws/variables.tf` | Add ~18 new variables |
| `environments/aws/outputs.tf` | Add ~15 new outputs |
| `environments/aws/main.tf` | Update ECS module call |
| `environments/aws/locals.tf` | Add route53_enabled |
| `environments/aws/providers.tf` | Add DR region provider |
| `modules/ecs/main.tf` | Add ECR replication |
| `modules/ecs/variables.tf` | Add ecr_replication_* |
| `modules/ecs/outputs.tf` | Add replication outputs |
| `modules/loadbalancer/outputs.tf` | Add bucket/target group outputs |
| `envs/dev.tfvars` | Add new variables (disabled) |
| `envs/stage.tfvars` | Add new variables (some enabled) |
| `envs/prod.tfvars` | Add new variables (most enabled) |

---

## Validation Checklist

After implementation:

- [ ] `terraform fmt -check -recursive` passes
- [ ] `terraform validate` passes
- [ ] `terraform plan -var-file=envs/dev.tfvars` succeeds
- [ ] `terraform plan -var-file=envs/stage.tfvars` succeeds
- [ ] `terraform plan -var-file=envs/prod.tfvars` succeeds
- [ ] All new features disabled by default in dev.tfvars
- [ ] Module outputs documented
- [ ] README.md updated

---

## Post-Implementation

After feature parity is achieved:

1. Update README.md to recommend `environments/aws/`
2. Add deprecation notice to `prod-aws/`
3. Create migration guide for existing deployments
4. Archive `prod-aws/` after successful production migration
