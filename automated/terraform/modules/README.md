# Terraform Modules

```
+------------------------------------------------------------------------+
|                                                                        |
|   WARNING: THESE MODULES ARE NOT USED BY PROD-AWS                      |
|                                                                        |
|   The production AWS environment (automated/terraform/environments/   |
|   prod-aws/) implements all infrastructure INLINE in separate .tf     |
|   files rather than calling these modules.                            |
|                                                                        |
|   These modules exist for potential future use but are NOT deployed.  |
|                                                                        |
+------------------------------------------------------------------------+
```

## Overview

This directory contains reusable Terraform modules that were created for potential multi-environment deployments. However, the current `prod-aws` environment implements all infrastructure directly in individual `.tf` files.

## Why Prod-AWS Does Not Use These Modules

The decision to use inline resources instead of modules was intentional:

1. **Simpler Debugging** - All resources visible in one location without module abstraction
2. **Reduced Complexity** - Easier for new engineers to understand the infrastructure
3. **Rapid Iteration** - Faster to modify inline code during initial development
4. **Flexibility** - No need to define module interfaces upfront
5. **Single Environment** - No immediate need for module reuse across dev/staging/prod

## Module Inventory

| Module | Status | Files | Description |
|--------|--------|-------|-------------|
| `networking/` | Complete | main.tf, variables.tf, outputs.tf | VPC, subnets, NAT gateway, route tables, VPC flow logs |
| `security-groups/` | Complete | main.tf, variables.tf, outputs.tf | Security groups for ALB, Liberty EC2, ECS, RDS, ElastiCache |
| `ecs/` | Complete | main.tf, variables.tf, outputs.tf | ECS cluster, task definition, service, ECR repository |
| `compute/` | Stub Only | README.md only | Intended for EC2 Liberty instances - never implemented |
| `storage/` | Empty | No files | Empty directory - never implemented |

## Detailed Module Status

### networking/ - COMPLETE, UNUSED

A fully implemented VPC module providing:

- VPC with configurable CIDR block
- Public and private subnets across multiple availability zones
- Internet gateway
- NAT gateway (optional)
- Route tables and associations
- VPC flow logs (optional)

**Comparable prod-aws file:** `networking.tf`

### security-groups/ - COMPLETE, UNUSED

A fully implemented security groups module providing:

- ALB security group (HTTP/HTTPS ingress)
- Liberty EC2 security group (HTTP/HTTPS from ALB, SSH from VPC)
- ECS task security group (HTTP/HTTPS from ALB)
- RDS database security group (PostgreSQL from Liberty/ECS)
- ElastiCache security group (Redis from Liberty/ECS)

**Comparable prod-aws file:** `security.tf`

### ecs/ - COMPLETE, UNUSED

A fully implemented ECS module providing:

- ECS Fargate cluster with container insights
- Task definition with health checks and logging
- ECS service with deployment circuit breaker
- IAM roles for task execution and task runtime
- ECR repository with lifecycle policies
- CloudWatch log group

**Comparable prod-aws files:** `ecs.tf`, `ecs-iam.tf`, `ecr.tf`

### compute/ - STUB ONLY

An empty placeholder that was never implemented. Contains only a README.md explaining its intended purpose.

- No main.tf
- No variables.tf
- No outputs.tf

**Comparable prod-aws file:** `compute.tf` (fully implemented inline)

### storage/ - EMPTY

An empty directory with no files. Was likely intended for S3 buckets or EBS volumes but was never started.

## Using These Modules (If Refactoring)

If you decide to refactor `prod-aws` to use these modules, here is an example configuration:

```hcl
# In automated/terraform/environments/prod-aws/main.tf

module "networking" {
  source = "../../modules/networking"

  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  availability_zones = 2

  enable_nat_gateway = true
  enable_flow_logs   = true

  tags = local.common_tags
}

module "security_groups" {
  source = "../../modules/security-groups"

  name_prefix = local.name_prefix
  vpc_id      = module.networking.vpc_id
  vpc_cidr    = module.networking.vpc_cidr

  create_liberty_sg = var.liberty_instance_count > 0
  create_ecs_sg     = var.ecs_enabled

  tags = local.common_tags
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

  tags = local.common_tags
}
```

## Refactoring Checklist

If you want to migrate `prod-aws` to use these modules:

1. **Backup current state**
   ```bash
   cd automated/terraform/environments/prod-aws
   terraform state pull > terraform.tfstate.backup
   ```

2. **Replace inline resources with module calls**
   - Start with `networking` module first
   - Use `terraform state mv` to move resources into modules without destroying

3. **Handle state migration**
   ```bash
   # Example: Move VPC from inline to module
   terraform state mv aws_vpc.main module.networking.aws_vpc.main
   terraform state mv aws_subnet.public module.networking.aws_subnet.public
   # ... repeat for all resources
   ```

4. **Verify with plan**
   ```bash
   terraform plan
   # Should show no changes if state migration was correct
   ```

5. **Complete incomplete modules**
   - Implement `compute/` module if EC2 instances are needed
   - Remove empty `storage/` directory or implement if needed

## Recommendations

### Keep Inline If:

- You have a single production environment
- Your team is small (1-5 engineers)
- You are still iterating on infrastructure design
- You value simplicity over abstraction

### Switch to Modules If:

- You are adding dev/staging environments
- Your team grows beyond 5 engineers
- You want to enforce consistent infrastructure standards
- You are deploying to multiple AWS accounts

### Cleanup Option

If modules will never be used, consider removing them to avoid confusion:

```bash
cd automated/terraform
rm -rf modules/compute  # Empty stub
rm -rf modules/storage  # Empty directory
# Keep networking, security-groups, ecs if they serve as reference implementations
```

## Related Files

| Location | Description |
|----------|-------------|
| `../environments/prod-aws/` | Production AWS environment (inline resources) |
| `../environments/prod-aws/networking.tf` | Inline VPC implementation |
| `../environments/prod-aws/security.tf` | Inline security groups |
| `../environments/prod-aws/ecs.tf` | Inline ECS implementation |
| `../environments/prod-aws/compute.tf` | Inline EC2 implementation |

---

**Current State:** Modules complete but unused
**Recommended Action:** Continue using inline resources unless multi-environment is needed
**Last Updated:** 2026-01-02
