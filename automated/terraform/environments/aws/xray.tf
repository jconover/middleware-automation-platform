# =============================================================================
# AWS X-Ray Distributed Tracing
# =============================================================================
# X-Ray provides native AWS integration for distributed tracing.
#
# Features:
#   - Native AWS service integration (ECS, Lambda, API Gateway)
#   - Service map with latency distribution
#   - Trace analytics and insights
#   - Sampling rules for cost control
#
# Cost:
#   - $5 per million traces recorded
#   - $0.50 per million traces retrieved
#   - First 100k traces/month free
#
# Note: To use X-Ray:
#   1. Set enable_xray = true in terraform.tfvars
#   2. ECS module will enable X-Ray tracing
#   3. This file creates sampling rules and groups
# =============================================================================

# -----------------------------------------------------------------------------
# X-Ray Sampling Rules
# -----------------------------------------------------------------------------
# Custom sampling rules to control trace volume and cost

resource "aws_xray_sampling_rule" "liberty" {
  count = var.enable_xray ? 1 : 0

  rule_name      = "${local.name_prefix}-liberty-default"
  priority       = 1000
  version        = 1
  reservoir_size = 1 # Fixed rate: 1 trace per second guaranteed
  fixed_rate     = var.xray_sampling_rate
  url_path       = "*"
  host           = "*"
  http_method    = "*"
  service_name   = "liberty-app"
  service_type   = "*"
  resource_arn   = "*"

  attributes = {}

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-xray-sampling-default"
  })
}

# Higher sampling rate for error responses
resource "aws_xray_sampling_rule" "liberty_errors" {
  count = var.enable_xray ? 1 : 0

  rule_name      = "${local.name_prefix}-liberty-errors"
  priority       = 100 # Higher priority than default
  version        = 1
  reservoir_size = 5   # Capture more errors
  fixed_rate     = 0.5 # 50% of errors sampled
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

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-xray-sampling-errors"
  })
}

# Lower sampling for health checks
resource "aws_xray_sampling_rule" "liberty_health" {
  count = var.enable_xray ? 1 : 0

  rule_name      = "${local.name_prefix}-liberty-health"
  priority       = 50 # Highest priority
  version        = 1
  reservoir_size = 0    # No guaranteed traces
  fixed_rate     = 0.01 # 1% of health checks
  url_path       = "/health/*"
  host           = "*"
  http_method    = "GET"
  service_name   = "liberty-app"
  service_type   = "*"
  resource_arn   = "*"

  attributes = {}

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-xray-sampling-health"
  })
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

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-xray-group"
  })
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
