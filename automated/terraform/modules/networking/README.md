# Networking Module

## Status: UNUSED - For Reference Only

**This module is NOT currently used by the production environment.** See [../README.md](../README.md) for details.

## Purpose

Provides a complete AWS VPC networking foundation including:
- VPC with configurable CIDR block
- Public and private subnets across multiple availability zones
- Internet Gateway for public subnet internet access
- NAT Gateway for private subnet internet access (optional)
- Route tables and associations
- VPC Flow Logs for network monitoring (optional)

## Resources Created

| Resource | Count | Description |
|----------|-------|-------------|
| `aws_vpc` | 1 | Main VPC |
| `aws_internet_gateway` | 1 | Internet access for public subnets |
| `aws_subnet` (public) | N | Public subnets across AZs |
| `aws_subnet` (private) | N | Private subnets across AZs |
| `aws_eip` | 0-1 | Elastic IP for NAT gateway (if enabled) |
| `aws_nat_gateway` | 0-1 | NAT for private subnet internet (if enabled) |
| `aws_route_table` | 2 | Public and private route tables |
| `aws_flow_log` | 0-1 | VPC flow logging (if enabled) |

## Usage Example

```hcl
module "networking" {
  source = "../../modules/networking"

  name_prefix        = "mw-prod"
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = 2

  enable_nat_gateway = true
  enable_flow_logs   = true
  flow_logs_retention_days = 30

  tags = {
    Environment = "production"
    Project     = "middleware-automation"
  }
}
```

## Key Outputs

| Output | Description |
|--------|-------------|
| `vpc_id` | VPC identifier |
| `vpc_cidr` | VPC CIDR block |
| `public_subnet_ids` | List of public subnet IDs |
| `private_subnet_ids` | List of private subnet IDs |
| `nat_gateway_id` | NAT Gateway ID (null if disabled) |

## Design Decisions

### Single NAT Gateway
Creates **one** NAT Gateway in the first public subnet (cost optimization).

**For high availability:** Consider creating one NAT Gateway per AZ.

### Subnet CIDR Calculation
Uses `cidrsubnet()` to automatically calculate subnet CIDRs:
- **Public subnets:** Offset 1 -> 10.0.1.0/24, 10.0.2.0/24
- **Private subnets:** Offset 10 -> 10.0.10.0/24, 10.0.11.0/24

## Cost Estimate

| Resource | Monthly Cost (us-east-1) |
|----------|--------------------------|
| NAT Gateway | ~$32.40 (if enabled) |
| Data transfer | ~$0.045/GB |
| Flow Logs (CloudWatch) | ~$0.50/GB |
| **Total (typical)** | ~$35-40/month |

## Related Files

- [Module implementation](./main.tf)
- [Production inline implementation](../../environments/prod-aws/networking.tf)

---

**Status:** Complete but unused
**Last Updated:** 2025-12-30
