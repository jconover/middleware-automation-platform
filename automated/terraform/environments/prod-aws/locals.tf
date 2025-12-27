# =============================================================================
# Locals - Consolidated local values for the environment
# =============================================================================

locals {
  # ---------------------------------------------------------------------------
  # Naming Conventions
  # ---------------------------------------------------------------------------
  # Short prefix for resources with name limits (ALB max 32 chars)
  name_prefix      = "mw-prod"
  name_prefix_long = "${var.project_name}-${var.environment}"

  # ---------------------------------------------------------------------------
  # Common Tags
  # ---------------------------------------------------------------------------
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
  }

  # ---------------------------------------------------------------------------
  # Certificate Logic
  # ---------------------------------------------------------------------------
  # Use provided certificate ARN, or created certificate, or none
  certificate_arn = var.certificate_arn != "" ? var.certificate_arn : (
    var.create_certificate && length(aws_acm_certificate.main) > 0 ? aws_acm_certificate.main[0].arn : ""
  )

  has_certificate = local.certificate_arn != ""

  # For admin console, use provided cert or fall back to a self-signed approach
  # ALB requires a certificate for HTTPS - use the main cert if available
  admin_certificate_arn = local.certificate_arn != "" ? local.certificate_arn : (
    length(aws_acm_certificate.admin_self_signed) > 0 ? aws_acm_certificate.admin_self_signed[0].arn : ""
  )
}
