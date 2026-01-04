# =============================================================================
# Local Values
# =============================================================================
# Computed values used throughout the configuration for consistent naming,
# tagging, and resource configuration.
# =============================================================================

locals {
  # ---------------------------------------------------------------------------
  # Naming Conventions
  # ---------------------------------------------------------------------------
  # Short prefix for resources with name limits (ALB max 32 chars)
  name_prefix = "${var.project}-${var.environment}"

  # Full name prefix for resources without strict limits
  name_prefix_long = "${var.project}-${var.environment}"

  # ---------------------------------------------------------------------------
  # Common Tags
  # ---------------------------------------------------------------------------
  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.additional_tags
  )

  # ---------------------------------------------------------------------------
  # Computed Values
  # ---------------------------------------------------------------------------
  # AWS account ID from data source
  account_id = data.aws_caller_identity.current.account_id

  # Region from data source
  region = data.aws_region.current.name

  # ECR repository URL (computed after ECS module creates the repo)
  ecr_repository_url = var.ecs_enabled ? module.ecs[0].ecr_repository_url : null

  # Container image for ECS tasks
  container_image = var.ecs_enabled ? (
    local.ecr_repository_url != null ?
    "${local.ecr_repository_url}:${var.container_image_tag}" :
    "icr.io/appcafe/open-liberty:kernel-slim-java17-openj9-ubi"
  ) : null

  # ---------------------------------------------------------------------------
  # Certificate Logic
  # ---------------------------------------------------------------------------
  # Determine if HTTPS is available
  has_certificate = var.certificate_arn != "" || var.enable_https

  # Effective certificate ARN (provided or will be created by loadbalancer module)
  effective_certificate_arn = var.certificate_arn

  # ---------------------------------------------------------------------------
  # Availability Zones
  # ---------------------------------------------------------------------------
  # Select the requested number of AZs from available ones
  selected_azs = slice(data.aws_availability_zones.available.names, 0, var.availability_zones)

  # ---------------------------------------------------------------------------
  # SSH Key
  # ---------------------------------------------------------------------------
  # Read SSH public key from file if path is provided
  ssh_public_key = var.ssh_public_key_path != "" ? file(pathexpand(var.ssh_public_key_path)) : null
}
