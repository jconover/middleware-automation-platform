# =============================================================================
# Terraform State Backend Bootstrap
# =============================================================================
# Run this ONCE to create the S3 bucket and DynamoDB table for state management.
#
# Usage:
#   cd bootstrap
#   terraform init
#   terraform apply
#
# After this completes, all environments (dev/stage/prod) can use remote state.
# =============================================================================

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project   = "middleware-platform"
      Component = "terraform-state"
      ManagedBy = "terraform"
    }
  }
}

variable "aws_region" {
  description = "AWS region for state backend"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  type        = string
  default     = "middleware-platform-terraform-state"
}

variable "lock_table_name" {
  description = "Name of the DynamoDB table for state locking"
  type        = string
  default     = "terraform-state-lock"
}

# -----------------------------------------------------------------------------
# S3 Bucket for State Storage
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "terraform_state" {
  bucket = var.state_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# DynamoDB Table for State Locking
# -----------------------------------------------------------------------------
resource "aws_dynamodb_table" "terraform_locks" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "state_bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "state_bucket_arn" {
  description = "ARN of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.arn
}

output "lock_table_name" {
  description = "Name of the DynamoDB table for state locking"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "backend_config" {
  description = "Backend configuration for the unified environments/aws setup"
  value       = <<-EOT

    The unified environment uses backend config files in environments/aws/backends/.
    Each environment has its own state file:

    - dev:   environments/dev/terraform.tfstate
    - stage: environments/stage/terraform.tfstate
    - prod:  environments/prod/terraform.tfstate

    Usage:
      cd environments/aws
      terraform init -backend-config=backends/dev.backend.hcl
      terraform init -backend-config=backends/prod.backend.hcl -reconfigure

    Backend config files use:
      bucket         = "${aws_s3_bucket.terraform_state.id}"
      dynamodb_table = "${aws_dynamodb_table.terraform_locks.name}"
      region         = "${var.aws_region}"
      encrypt        = true
  EOT
}
