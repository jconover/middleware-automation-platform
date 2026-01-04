# =============================================================================
# Networking - Uses the reusable networking module
# =============================================================================
# This file replaces 274 lines of duplicated networking code with a module call.
# The networking module provides:
#   - VPC with DNS support
#   - Public and private subnets across availability zones
#   - Internet Gateway for public subnets
#   - NAT Gateway(s) for private subnet internet access
#   - Route tables with proper associations
#   - VPC Flow Logs with optional KMS encryption
#
# For module source, see: ../../modules/networking/
# =============================================================================

module "networking" {
  source = "../../modules/networking"

  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  aws_region         = var.aws_region

  # NAT Gateway configuration
  enable_nat_gateway    = true
  high_availability_nat = var.high_availability_nat

  # VPC Flow Logs with KMS encryption (security best practice)
  enable_flow_logs            = true
  enable_flow_logs_encryption = true
  flow_logs_traffic_type      = "ALL"
  flow_logs_retention_days    = 30

  tags = local.common_tags
}

# =============================================================================
# Local values for referencing module outputs
# =============================================================================
# These locals provide convenient access to networking resources throughout
# the configuration. They also ensure backward compatibility with any code
# that was previously referencing aws_vpc.main, aws_subnet.public, etc.
# =============================================================================

locals {
  # VPC references
  vpc_id   = module.networking.vpc_id
  vpc_cidr = module.networking.vpc_cidr

  # Subnet references
  public_subnet_ids  = module.networking.public_subnet_ids
  private_subnet_ids = module.networking.private_subnet_ids
}
