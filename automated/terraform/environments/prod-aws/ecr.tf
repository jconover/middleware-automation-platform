# =============================================================================
# ECR - Elastic Container Registry
# =============================================================================
# Container registry for Liberty application images
# =============================================================================

resource "aws_ecr_repository" "liberty" {
  name                 = "${local.name_prefix}-liberty"
  image_tag_mutability = "MUTABLE"

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
          tagStatus     = "tagged"
          tagPrefixList = ["v", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
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
