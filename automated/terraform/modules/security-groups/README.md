# Security Groups Module

## Status: UNUSED - For Reference Only

**This module is NOT currently used by the production environment.** See [../README.md](../README.md) for details.

## Purpose

Provides comprehensive security group configuration for the middleware automation platform:
- ALB security group (public internet access)
- Liberty EC2 security group (application servers)
- ECS security group (Fargate tasks)
- RDS security group (PostgreSQL database)
- ElastiCache security group (Redis)

All security groups follow **least privilege** principles with explicit ingress/egress rules.

## Resources Created

| Resource | Count | Description |
|----------|-------|-------------|
| `aws_security_group.alb` | 1 | Application Load Balancer |
| `aws_security_group.liberty` | 0-1 | Liberty EC2 instances (if enabled) |
| `aws_security_group.ecs` | 0-1 | ECS Fargate tasks (if enabled) |
| `aws_security_group.db` | 1 | RDS PostgreSQL |
| `aws_security_group.cache` | 1 | ElastiCache Redis |

## Usage Example

```hcl
module "security_groups" {
  source = "../../modules/security-groups"

  name_prefix = "mw-prod"
  vpc_id      = module.networking.vpc_id
  vpc_cidr    = module.networking.vpc_cidr

  create_liberty_sg = var.liberty_instance_count > 0
  create_ecs_sg     = var.ecs_enabled

  tags = {
    Environment = "production"
  }
}
```

## Security Group Rules

### ALB Security Group
| Direction | Port | Source | Description |
|-----------|------|--------|-------------|
| Ingress | 80 | 0.0.0.0/0 | HTTP from anywhere |
| Ingress | 443 | 0.0.0.0/0 | HTTPS from anywhere |
| Egress | All | 0.0.0.0/0 | All outbound traffic |

### Liberty/ECS Security Groups
| Direction | Port | Source | Description |
|-----------|------|--------|-------------|
| Ingress | 9080 | ALB SG | HTTP from ALB |
| Ingress | 9443 | ALB SG | HTTPS from ALB |
| Ingress | 22 | VPC CIDR | SSH from VPC (Liberty only) |

### Database/Cache Security Groups
| Direction | Port | Source | Description |
|-----------|------|--------|-------------|
| Ingress | 5432 | Liberty/ECS SG | PostgreSQL |
| Ingress | 6379 | Liberty/ECS SG | Redis |

## Key Outputs

| Output | Description |
|--------|-------------|
| `alb_security_group_id` | ALB security group ID |
| `liberty_security_group_id` | Liberty EC2 security group ID |
| `ecs_security_group_id` | ECS security group ID |
| `db_security_group_id` | Database security group ID |
| `cache_security_group_id` | Cache security group ID |

## Security Best Practices

- **Least privilege** - Only required ports open
- **Security group references** - Uses SG IDs instead of CIDR blocks
- **No overly permissive rules** - No 0.0.0.0/0 ingress except ALB public ports
- **Descriptive names** - Each rule has a description for auditing

## Related Files

- [Module implementation](./main.tf)
- [Production inline implementation](../../environments/prod-aws/security.tf)

---

**Status:** Complete but unused
**Last Updated:** 2025-12-30
