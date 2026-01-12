# =============================================================================
# ECR Cross-Region Replication for Disaster Recovery
# =============================================================================
# Implements cross-region replication of container images from primary region
# to DR region for disaster recovery and business continuity.
#
# Benefits:
# - Geographic redundancy for container images
# - Enables DR region ECS deployments without cross-region image pulls
# - Reduces recovery time objective (RTO) in disaster scenarios
# - Eliminates single region dependency for container deployments
#
# Enable with: enable_ecr_replication = true
# Requires: ecs_enabled = true (ECR repository must exist)
# =============================================================================

# -----------------------------------------------------------------------------
# DR Region ECR Repository
# -----------------------------------------------------------------------------
# Explicitly create the DR repository to ensure consistent configuration
# across regions (lifecycle policies, repository policies, encryption).
# While ECR replication auto-creates repositories, explicit creation gives
# us control over settings and prevents drift.
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "liberty_dr" {
  count    = var.enable_ecr_replication && var.ecs_enabled ? 1 : 0
  provider = aws.dr

  name                 = "${local.name_prefix}-liberty"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.common_tags, {
    Name         = "${local.name_prefix}-liberty-dr"
    Purpose      = "disaster-recovery"
    SourceRegion = var.aws_region
  })
}

# -----------------------------------------------------------------------------
# Lifecycle Policy for DR Repository
# -----------------------------------------------------------------------------
# Apply the same lifecycle policy as the primary repository to manage
# image retention and prevent unbounded growth of replicated images.
# -----------------------------------------------------------------------------

resource "aws_ecr_lifecycle_policy" "liberty_dr" {
  count      = var.enable_ecr_replication && var.ecs_enabled ? 1 : 0
  provider   = aws.dr
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

# -----------------------------------------------------------------------------
# Repository Policy for DR Repository
# -----------------------------------------------------------------------------
# Grant ECS task execution role permission to pull images from the DR
# repository. This enables ECS services in the DR region to use the
# replicated images during a disaster recovery scenario.
# -----------------------------------------------------------------------------

resource "aws_ecr_repository_policy" "liberty_dr" {
  count      = var.enable_ecr_replication && var.ecs_enabled ? 1 : 0
  provider   = aws.dr
  repository = aws_ecr_repository.liberty_dr[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowECSTaskExecutionPull"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      },
      {
        Sid    = "AllowAccountPull"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories"
        ]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# ECR Cross-Region Replication Configuration
# -----------------------------------------------------------------------------
# Configure ECR to automatically replicate images to the DR region.
# Uses prefix matching to replicate only our Liberty application images.
#
# Note: This is a registry-level resource - only ONE replication configuration
# can exist per AWS account per region. Repository filter ensures only
# matching images are replicated.
# -----------------------------------------------------------------------------

resource "aws_ecr_replication_configuration" "cross_region" {
  count = var.enable_ecr_replication && var.ecs_enabled ? 1 : 0

  replication_configuration {
    rule {
      destination {
        region      = var.dr_region
        registry_id = local.account_id
      }

      repository_filter {
        filter      = local.name_prefix
        filter_type = "PREFIX_MATCH"
      }
    }
  }

  # Ensure DR repository exists before configuring replication
  depends_on = [aws_ecr_repository.liberty_dr]
}

# -----------------------------------------------------------------------------
# CloudWatch Alarm for ECR Replication Monitoring
# -----------------------------------------------------------------------------
# Monitor the replication status using CloudWatch Events rather than metrics,
# as ECR doesn't publish replication-specific metrics. This alarm uses a
# custom metric that can be populated via EventBridge rule.
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "ecr_replication" {
  count = var.enable_ecr_replication && var.ecs_enabled ? 1 : 0

  name              = "/aws/ecr/${local.name_prefix}/replication"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecr-replication-logs"
  })
}

# EventBridge rule to capture ECR image replication events
resource "aws_cloudwatch_event_rule" "ecr_replication" {
  count = var.enable_ecr_replication && var.ecs_enabled ? 1 : 0

  name        = "${local.name_prefix}-ecr-replication-events"
  description = "Capture ECR image replication events for monitoring"

  event_pattern = jsonencode({
    source      = ["aws.ecr"]
    detail-type = ["ECR Image Action"]
    detail = {
      action-type = ["PUSH"]
      repository-name = [{
        prefix = local.name_prefix
      }]
    }
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecr-replication-events"
  })
}

# CloudWatch Log Group target for replication events
resource "aws_cloudwatch_event_target" "ecr_replication_logs" {
  count = var.enable_ecr_replication && var.ecs_enabled ? 1 : 0

  rule      = aws_cloudwatch_event_rule.ecr_replication[0].name
  target_id = "ecr-replication-logs"
  arn       = aws_cloudwatch_log_group.ecr_replication[0].arn
}

# Log group policy to allow EventBridge to write logs
resource "aws_cloudwatch_log_resource_policy" "ecr_replication" {
  count = var.enable_ecr_replication && var.ecs_enabled ? 1 : 0

  policy_name = "${local.name_prefix}-ecr-replication-logs"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgeToWriteLogs"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.ecr_replication[0].arn}:*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# SNS Topic for ECR Replication Alerts (Optional)
# -----------------------------------------------------------------------------
# Create SNS topic for alerting on ECR replication issues.
# Integrates with existing SLO alarm infrastructure if enabled.
# -----------------------------------------------------------------------------

resource "aws_sns_topic" "ecr_replication_alerts" {
  count = var.enable_ecr_replication && var.ecs_enabled && var.enable_slo_alarms ? 1 : 0

  name = "${local.name_prefix}-ecr-replication-alerts"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecr-replication-alerts"
  })
}

# SNS subscription for email alerts
resource "aws_sns_topic_subscription" "ecr_replication_email" {
  count = var.enable_ecr_replication && var.ecs_enabled && var.enable_slo_alarms && var.slo_alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.ecr_replication_alerts[0].arn
  protocol  = "email"
  endpoint  = var.slo_alert_email
}
