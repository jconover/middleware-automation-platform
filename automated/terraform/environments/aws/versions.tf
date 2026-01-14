# =============================================================================
# Terraform and Provider Version Requirements
# =============================================================================
# This file specifies the minimum versions of Terraform and providers required
# for this environment. Pin versions to ensure reproducible deployments.
#
# Backend Configuration:
#   The S3 backend requires configuration via -backend-config flag:
#   terraform init -backend-config=backends/dev.backend.hcl
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  # S3 backend with DynamoDB state locking
  # Configure with: terraform init -backend-config=backends/<env>.backend.hcl
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}
