# Terraform Modules

## Overview

This directory contains **reusable Terraform modules** for the middleware automation platform.

## Current Status: NOT IN USE

**IMPORTANT**: These modules are **NOT actively used** by the production deployment in `automated/terraform/environments/prod-aws/`.

The prod-aws environment implements all infrastructure **inline** (directly in individual .tf files) rather than calling these modules. This was a conscious architectural decision to:

1. **Simplify debugging** - All resources visible in one location
2. **Reduce abstraction layers** - Easier for new engineers to understand
3. **Enable rapid iteration** - Faster to modify inline code during initial development
4. **Maintain flexibility** - Avoid module interface constraints

## Module Directory

| Module | Status | Purpose | Quality |
|--------|--------|---------|---------|
| **networking** | Complete, unused | VPC, subnets, NAT gateway, route tables, VPC flow logs | Production-ready |
| **security-groups** | Complete, unused | Security groups for ALB, Liberty, ECS, RDS, ElastiCache | Production-ready |
| **ecs** | Complete, unused | ECS cluster, task definition, service, ECR repository | Production-ready |
| **compute** | Stub/empty | Intended for EC2 Liberty instances | Not implemented |

## Why Keep These Modules?

Even though unused, these modules provide value:

1. **Future refactoring** - If the team decides to modularize prod-aws later
2. **Multi-environment** - Could be used for dev/staging environments
3. **Reference implementation** - Well-structured examples of Terraform best practices
4. **Alternative architecture** - For teams preferring modular over monolithic Terraform

## Using These Modules (Future)

Example usage if refactoring to modular approach:

```hcl
module "networking" {
  source = "../../modules/networking"

  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones

  enable_nat_gateway = true
  enable_flow_logs   = true

  tags = {
    Environment = var.environment
    Project     = "middleware-automation"
  }
}

module "security_groups" {
  source = "../../modules/security-groups"

  name_prefix = local.name_prefix
  vpc_id      = module.networking.vpc_id
  vpc_cidr    = module.networking.vpc_cidr

  create_liberty_sg = var.liberty_instance_count > 0
  create_ecs_sg     = var.ecs_enabled
}

module "ecs" {
  source = "../../modules/ecs"

  name_prefix        = local.name_prefix
  aws_region         = var.aws_region
  private_subnet_ids = module.networking.private_subnet_ids
  security_group_ids = [module.security_groups.ecs_security_group_id]

  container_image = "${aws_ecr_repository.liberty.repository_url}:latest"
  task_cpu        = var.ecs_task_cpu
  task_memory     = var.ecs_task_memory
  desired_count   = var.ecs_desired_count

  target_group_arn = aws_lb_target_group.liberty_ecs[0].arn
}
```

## Decision: Inline vs Modular

### Current (Inline) Architecture
**Pros:**
- Single file contains all related resources
- Easier to debug - `terraform state list` shows all resources directly
- No module versioning complexity
- Faster initial development

**Cons:**
- Code duplication if multiple environments exist
- Harder to enforce standards across teams

### Alternative (Modular) Architecture
**Pros:**
- DRY principle - modules reused across environments
- Easier to test modules in isolation
- Enforces interface contracts

**Cons:**
- Additional abstraction layer to understand
- Module outputs must be carefully planned

## Recommendation

**For this project:** The current inline approach is **appropriate** because:
- Single production environment (no dev/staging/prod split)
- Small team (1-3 engineers)
- Rapid iteration phase

**Consider modules when:**
- Adding dev/staging environments
- Team grows beyond 5 engineers
- Need to enforce organizational standards

## Related Documentation

- [Production AWS Environment](../environments/prod-aws/)
- [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/index.html)

---

**Last Updated:** 2025-12-30
