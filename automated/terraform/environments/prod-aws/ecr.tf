# =============================================================================
# ECR - Elastic Container Registry
# =============================================================================
# Container registry for Liberty application images
# =============================================================================

resource "aws_ecr_repository" "liberty" {
  name                 = "${local.name_prefix}-liberty"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "${local.name_prefix}-liberty"
  }
}

# -----------------------------------------------------------------------------
# Lifecycle Policy - Keep last 10 images, expire untagged after 7 days
# -----------------------------------------------------------------------------
resource "aws_ecr_lifecycle_policy" "liberty" {
  repository = aws_ecr_repository.liberty.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Repository Policy - Allow ECS to pull images
# -----------------------------------------------------------------------------
resource "aws_ecr_repository_policy" "liberty" {
  repository = aws_ecr_repository.liberty.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowECSPull"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      }
    ]
  })
}

# =============================================================================
# ECR Cross-Region Replication Configuration
# =============================================================================
# Automatically replicate container images to a DR region for disaster recovery.
# This is a registry-level configuration that applies to all repositories.
# =============================================================================

resource "aws_ecr_replication_configuration" "cross_region" {
  count = var.ecr_replication_enabled ? 1 : 0

  replication_configuration {
    rule {
      destination {
        region      = var.ecr_replication_region
        registry_id = data.aws_caller_identity.current.account_id
      }

      # Filter to replicate only the Liberty repository
      # This ensures only production application images are replicated
      repository_filter {
        filter      = "${local.name_prefix}-liberty"
        filter_type = "PREFIX_MATCH"
      }
    }
  }
}

# -----------------------------------------------------------------------------
# DR Region ECR Repository
# -----------------------------------------------------------------------------
# Note: ECR replication automatically creates the repository in the destination
# region if it doesn't exist. However, we create it explicitly to:
# 1. Apply consistent tags
# 2. Configure image scanning
# 3. Apply lifecycle policies
# -----------------------------------------------------------------------------

# Provider alias for the DR region
provider "aws" {
  alias  = "dr_region"
  region = var.ecr_replication_region
}

resource "aws_ecr_repository" "liberty_dr" {
  count    = var.ecr_replication_enabled ? 1 : 0
  provider = aws.dr_region

  name                 = "${local.name_prefix}-liberty"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name        = "${local.name_prefix}-liberty"
    Purpose     = "disaster-recovery"
    PrimaryRepo = aws_ecr_repository.liberty.repository_url
  }
}

# Apply the same lifecycle policy to the DR repository
resource "aws_ecr_lifecycle_policy" "liberty_dr" {
  count      = var.ecr_replication_enabled ? 1 : 0
  provider   = aws.dr_region
  repository = aws_ecr_repository.liberty_dr[0].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Allow ECS in DR region to pull images
resource "aws_ecr_repository_policy" "liberty_dr" {
  count      = var.ecr_replication_enabled ? 1 : 0
  provider   = aws.dr_region
  repository = aws_ecr_repository.liberty_dr[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowECSPull"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      }
    ]
  })
}
