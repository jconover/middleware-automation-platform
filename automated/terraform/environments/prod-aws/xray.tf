# =============================================================================
# AWS X-Ray Distributed Tracing
# =============================================================================
# Alternative to self-hosted Jaeger for AWS environments.
# X-Ray provides native AWS integration, service maps, and trace analytics.
#
# Features:
#   - Native AWS service integration (ECS, Lambda, API Gateway)
#   - Service map with latency distribution
#   - Trace analytics and insights
#   - Sampling rules for cost control
#
# Architecture:
#   Liberty (OTEL Agent) -> X-Ray Daemon (sidecar) -> X-Ray Service
#   Or directly via OTLP to X-Ray (using ADOT Collector)
#
# Cost:
#   - $5 per million traces recorded
#   - $0.50 per million traces retrieved
#   - First 100k traces/month free
#
# Note: This file creates X-Ray resources. To use X-Ray:
#   1. Set enable_xray = true in terraform.tfvars
#   2. ECS task definition will automatically include X-Ray sidecar
#   3. OpenTelemetry agent exports to X-Ray daemon on localhost:2000
# =============================================================================

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------
variable "enable_xray" {
  description = <<-EOT
    Enable AWS X-Ray for distributed tracing.
    When enabled:
    - Adds X-Ray daemon as sidecar to ECS tasks
    - Creates X-Ray sampling rules
    - Grants IAM permissions for trace submission

    Cost: ~$5 per million traces (first 100k free)
  EOT
  type        = bool
  default     = false
}

variable "xray_sampling_rate" {
  description = <<-EOT
    Default sampling rate for X-Ray traces (0.0 to 1.0).
    0.1 = 10% of requests traced (recommended for production)
    1.0 = 100% of requests traced (development only)

    Note: High-volume production should use 0.05-0.1 to control costs.
  EOT
  type        = number
  default     = 0.1

  validation {
    condition     = var.xray_sampling_rate >= 0 && var.xray_sampling_rate <= 1
    error_message = "X-Ray sampling rate must be between 0.0 and 1.0."
  }
}

# -----------------------------------------------------------------------------
# X-Ray Sampling Rules
# -----------------------------------------------------------------------------
# Custom sampling rules to control trace volume and cost

resource "aws_xray_sampling_rule" "liberty_default" {
  count = var.enable_xray ? 1 : 0

  rule_name      = "${local.name_prefix}-liberty-default"
  priority       = 1000
  version        = 1
  reservoir_size = 1        # Fixed rate: 1 trace per second guaranteed
  fixed_rate     = var.xray_sampling_rate
  url_path       = "*"
  host           = "*"
  http_method    = "*"
  service_name   = "liberty-app"
  service_type   = "*"
  resource_arn   = "*"

  attributes = {}

  tags = {
    Name        = "${local.name_prefix}-xray-sampling-default"
    Environment = var.environment
  }
}

# Higher sampling rate for error responses
resource "aws_xray_sampling_rule" "liberty_errors" {
  count = var.enable_xray ? 1 : 0

  rule_name      = "${local.name_prefix}-liberty-errors"
  priority       = 100 # Higher priority than default
  version        = 1
  reservoir_size = 5     # Capture more errors
  fixed_rate     = 0.5   # 50% of errors sampled
  url_path       = "*"
  host           = "*"
  http_method    = "*"
  service_name   = "liberty-app"
  service_type   = "*"
  resource_arn   = "*"

  # Match 5xx responses (requires custom attribute from app)
  attributes = {
    "http.status_code" = "5*"
  }

  tags = {
    Name        = "${local.name_prefix}-xray-sampling-errors"
    Environment = var.environment
  }
}

# Lower sampling for health checks
resource "aws_xray_sampling_rule" "liberty_health" {
  count = var.enable_xray ? 1 : 0

  rule_name      = "${local.name_prefix}-liberty-health"
  priority       = 50 # Highest priority
  version        = 1
  reservoir_size = 0     # No guaranteed traces
  fixed_rate     = 0.01  # 1% of health checks
  url_path       = "/health/*"
  host           = "*"
  http_method    = "GET"
  service_name   = "liberty-app"
  service_type   = "*"
  resource_arn   = "*"

  attributes = {}

  tags = {
    Name        = "${local.name_prefix}-xray-sampling-health"
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# X-Ray Group for Liberty Traces
# -----------------------------------------------------------------------------
resource "aws_xray_group" "liberty" {
  count = var.enable_xray ? 1 : 0

  group_name        = "${local.name_prefix}-liberty"
  filter_expression = "service(id(name: \"liberty-app\"))"

  insights_configuration {
    insights_enabled      = true
    notifications_enabled = true
  }

  tags = {
    Name        = "${local.name_prefix}-xray-group"
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# IAM Policy for X-Ray
# -----------------------------------------------------------------------------
# Attached to ECS task role in ecs-iam.tf

resource "aws_iam_policy" "xray" {
  count = var.enable_xray ? 1 : 0

  name        = "${local.name_prefix}-xray-policy"
  description = "Allow ECS tasks to send traces to X-Ray"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "XRayAccess"
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets",
          "xray:GetSamplingStatisticSummaries"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${local.name_prefix}-xray-policy"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_xray" {
  count = var.enable_xray && var.ecs_enabled ? 1 : 0

  role       = aws_iam_role.ecs_task.name
  policy_arn = aws_iam_policy.xray[0].arn
}

# -----------------------------------------------------------------------------
# CloudWatch Dashboard for X-Ray Metrics
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "xray" {
  count = var.enable_xray ? 1 : 0

  dashboard_name = "${local.name_prefix}-xray-traces"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Trace Count"
          region = var.aws_region
          metrics = [
            ["AWS/XRay", "TracesProcessedCount", "ServiceName", "liberty-app", { stat = "Sum", period = 300 }]
          ]
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Average Response Time"
          region = var.aws_region
          metrics = [
            ["AWS/XRay", "ResponseTime", "ServiceName", "liberty-app", { stat = "Average", period = 300 }]
          ]
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Error Rate"
          region = var.aws_region
          metrics = [
            ["AWS/XRay", "ErrorRate", "ServiceName", "liberty-app", { stat = "Average", period = 300 }]
          ]
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Fault Rate"
          region = var.aws_region
          metrics = [
            ["AWS/XRay", "FaultRate", "ServiceName", "liberty-app", { stat = "Average", period = 300 }]
          ]
          view = "timeSeries"
        }
      },
      {
        type   = "text"
        x      = 0
        y      = 12
        width  = 24
        height = 2
        properties = {
          markdown = <<-EOF
            ## X-Ray Service Map
            View the [X-Ray Service Map](https://${var.aws_region}.console.aws.amazon.com/xray/home?region=${var.aws_region}#/service-map) for visualization of service dependencies and latencies.

            View [Trace Analytics](https://${var.aws_region}.console.aws.amazon.com/xray/home?region=${var.aws_region}#/analytics) for trace insights.
          EOF
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "xray_enabled" {
  description = "Whether X-Ray tracing is enabled"
  value       = var.enable_xray
}

output "xray_sampling_rule_arn" {
  description = "ARN of the default X-Ray sampling rule"
  value       = var.enable_xray ? aws_xray_sampling_rule.liberty_default[0].arn : null
}

output "xray_group_arn" {
  description = "ARN of the X-Ray trace group for Liberty"
  value       = var.enable_xray ? aws_xray_group.liberty[0].arn : null
}

output "xray_service_map_url" {
  description = "URL to X-Ray Service Map in AWS Console"
  value       = var.enable_xray ? "https://${var.aws_region}.console.aws.amazon.com/xray/home?region=${var.aws_region}#/service-map" : null
}
