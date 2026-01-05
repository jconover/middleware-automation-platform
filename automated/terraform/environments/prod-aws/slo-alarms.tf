# =============================================================================
# SLO/SLI CloudWatch Alarms for ECS Liberty
# =============================================================================
# AWS-native alarms corresponding to the Kubernetes SLO framework.
# These alarms monitor the same SLO targets using ALB and ECS metrics.
#
# SLO Definitions:
#   - Availability: 99.95% (error rate < 0.05%)
#   - Latency: p95 < 500ms
#   - Error Rate: < 0.5% (5xx responses)
#
# Burn Rate Strategy:
#   CloudWatch alarms use similar multi-period evaluation to detect
#   both rapid incidents and slow degradation.
# =============================================================================

# -----------------------------------------------------------------------------
# SNS Topic for SLO Alerts
# -----------------------------------------------------------------------------
resource "aws_sns_topic" "slo_alerts" {
  count = var.ecs_enabled ? 1 : 0

  name = "${local.name_prefix}-slo-alerts"

  tags = {
    Name = "${local.name_prefix}-slo-alerts"
  }
}

# Optional: Email subscription for SLO alerts
resource "aws_sns_topic_subscription" "slo_alerts_email" {
  count = var.ecs_enabled && var.security_alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.slo_alerts[0].arn
  protocol  = "email"
  endpoint  = var.security_alert_email
}

# =============================================================================
# Availability SLO Alarms
# =============================================================================
# Monitor 5xx error rate from ALB target group metrics

# -----------------------------------------------------------------------------
# Critical: High 5xx Rate (Burn Rate > 14x)
# Error rate > 0.72% over 5 minutes indicates severe incident
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "slo_availability_critical" {
  count = var.ecs_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-slo-availability-critical"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 0.72 # 14.4 * 0.05% = 0.72%
  alarm_description   = <<-EOT
    CRITICAL: Liberty availability SLO burn rate is 14.4x - error budget exhaustion in 2 hours.
    At this rate, the entire monthly error budget (0.05%) will be exhausted in approximately 2 hours.
    SLO Target: 99.95% availability
    Runbook: docs/runbooks/liberty-slo-breach.md
  EOT
  treat_missing_data  = "notBreaching"
  actions_enabled     = true

  alarm_actions = [aws_sns_topic.slo_alerts[0].arn]
  ok_actions    = [aws_sns_topic.slo_alerts[0].arn]

  metric_query {
    id          = "error_rate"
    expression  = "IF(total_requests > 0, (error_requests / total_requests) * 100, 0)"
    label       = "Error Rate %"
    return_data = true
  }

  metric_query {
    id = "error_requests"
    metric {
      metric_name = "HTTPCode_Target_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.main.arn_suffix
        TargetGroup  = aws_lb_target_group.liberty_ecs[0].arn_suffix
      }
    }
  }

  metric_query {
    id = "total_requests"
    metric {
      metric_name = "RequestCount"
      namespace   = "AWS/ApplicationELB"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.main.arn_suffix
        TargetGroup  = aws_lb_target_group.liberty_ecs[0].arn_suffix
      }
    }
  }

  tags = {
    Name     = "${local.name_prefix}-slo-availability-critical"
    SLO      = "availability"
    Severity = "critical"
  }
}

# -----------------------------------------------------------------------------
# Warning: Elevated 5xx Rate (Burn Rate > 6x)
# Error rate > 0.3% over 30 minutes indicates degradation
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "slo_availability_warning" {
  count = var.ecs_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-slo-availability-warning"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 6   # 30 minutes (6 x 5-min periods)
  threshold           = 0.3 # 6 * 0.05% = 0.3%
  alarm_description   = <<-EOT
    WARNING: Liberty availability SLO burn rate is 6x - error budget exhaustion in 5 days.
    Investigate degraded performance or partial outages.
    SLO Target: 99.95% availability
    Runbook: docs/runbooks/liberty-slo-breach.md
  EOT
  treat_missing_data  = "notBreaching"
  actions_enabled     = true

  alarm_actions = [aws_sns_topic.slo_alerts[0].arn]
  ok_actions    = [aws_sns_topic.slo_alerts[0].arn]

  metric_query {
    id          = "error_rate"
    expression  = "IF(total_requests > 0, (error_requests / total_requests) * 100, 0)"
    label       = "Error Rate %"
    return_data = true
  }

  metric_query {
    id = "error_requests"
    metric {
      metric_name = "HTTPCode_Target_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.main.arn_suffix
        TargetGroup  = aws_lb_target_group.liberty_ecs[0].arn_suffix
      }
    }
  }

  metric_query {
    id = "total_requests"
    metric {
      metric_name = "RequestCount"
      namespace   = "AWS/ApplicationELB"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.main.arn_suffix
        TargetGroup  = aws_lb_target_group.liberty_ecs[0].arn_suffix
      }
    }
  }

  tags = {
    Name     = "${local.name_prefix}-slo-availability-warning"
    SLO      = "availability"
    Severity = "warning"
  }
}

# =============================================================================
# Latency SLO Alarms
# =============================================================================
# Monitor response time from ALB target response time metric

# -----------------------------------------------------------------------------
# Critical: p95 Latency > 500ms for 5 minutes
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "slo_latency_p95_critical" {
  count = var.ecs_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-slo-latency-p95-critical"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  extended_statistic  = "p95"
  threshold           = 0.5 # 500ms in seconds
  alarm_description   = <<-EOT
    CRITICAL: Liberty p95 latency exceeds 500ms SLO target.
    More than 5% of users are experiencing slow responses.
    SLO Target: p95 < 500ms
    Runbook: docs/runbooks/liberty-slow-responses.md
  EOT
  treat_missing_data  = "notBreaching"
  actions_enabled     = true

  alarm_actions = [aws_sns_topic.slo_alerts[0].arn]
  ok_actions    = [aws_sns_topic.slo_alerts[0].arn]

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.liberty_ecs[0].arn_suffix
  }

  tags = {
    Name     = "${local.name_prefix}-slo-latency-p95-critical"
    SLO      = "latency"
    Severity = "critical"
  }
}

# -----------------------------------------------------------------------------
# Warning: p95 Latency > 400ms for 10 minutes (approaching threshold)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "slo_latency_p95_warning" {
  count = var.ecs_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-slo-latency-p95-warning"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  extended_statistic  = "p95"
  threshold           = 0.4 # 400ms - approaching threshold
  alarm_description   = <<-EOT
    WARNING: Liberty p95 latency is 400ms, approaching 500ms SLO threshold.
    Investigate performance issues before SLO breach.
    SLO Target: p95 < 500ms
    Runbook: docs/runbooks/liberty-slow-responses.md
  EOT
  treat_missing_data  = "notBreaching"
  actions_enabled     = true

  alarm_actions = [aws_sns_topic.slo_alerts[0].arn]
  ok_actions    = [aws_sns_topic.slo_alerts[0].arn]

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.liberty_ecs[0].arn_suffix
  }

  tags = {
    Name     = "${local.name_prefix}-slo-latency-p95-warning"
    SLO      = "latency"
    Severity = "warning"
  }
}

# -----------------------------------------------------------------------------
# Critical: p99 Latency > 2 seconds (tail latency)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "slo_latency_p99_critical" {
  count = var.ecs_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-slo-latency-p99-critical"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  extended_statistic  = "p99"
  threshold           = 2 # 2 seconds
  alarm_description   = <<-EOT
    CRITICAL: Liberty p99 latency exceeds 2 seconds.
    1% of users are experiencing unacceptably slow responses.
    Runbook: docs/runbooks/liberty-slow-responses.md
  EOT
  treat_missing_data  = "notBreaching"
  actions_enabled     = true

  alarm_actions = [aws_sns_topic.slo_alerts[0].arn]
  ok_actions    = [aws_sns_topic.slo_alerts[0].arn]

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.liberty_ecs[0].arn_suffix
  }

  tags = {
    Name     = "${local.name_prefix}-slo-latency-p99-critical"
    SLO      = "latency"
    Severity = "critical"
  }
}

# =============================================================================
# Error Rate SLO Alarms
# =============================================================================
# Direct threshold monitoring for error rate SLO

# -----------------------------------------------------------------------------
# Critical: Error Rate > 0.5% (SLO Breach)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "slo_error_rate_breach" {
  count = var.ecs_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-slo-error-rate-breach"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 0.5 # 0.5%
  alarm_description   = <<-EOT
    CRITICAL: Liberty error rate exceeds 0.5% SLO target.
    Immediate investigation required. Check application logs, downstream dependencies, and resource utilization.
    SLO Target: Error Rate < 0.5%
    Runbook: docs/runbooks/liberty-high-error-rate.md
  EOT
  treat_missing_data  = "notBreaching"
  actions_enabled     = true

  alarm_actions = [aws_sns_topic.slo_alerts[0].arn]
  ok_actions    = [aws_sns_topic.slo_alerts[0].arn]

  metric_query {
    id          = "error_rate"
    expression  = "IF(total_requests > 0, (error_requests / total_requests) * 100, 0)"
    label       = "Error Rate %"
    return_data = true
  }

  metric_query {
    id = "error_requests"
    metric {
      metric_name = "HTTPCode_Target_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.main.arn_suffix
        TargetGroup  = aws_lb_target_group.liberty_ecs[0].arn_suffix
      }
    }
  }

  metric_query {
    id = "total_requests"
    metric {
      metric_name = "RequestCount"
      namespace   = "AWS/ApplicationELB"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.main.arn_suffix
        TargetGroup  = aws_lb_target_group.liberty_ecs[0].arn_suffix
      }
    }
  }

  tags = {
    Name     = "${local.name_prefix}-slo-error-rate-breach"
    SLO      = "error_rate"
    Severity = "critical"
  }
}

# -----------------------------------------------------------------------------
# Warning: Error Rate > 0.3% (approaching threshold)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "slo_error_rate_warning" {
  count = var.ecs_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-slo-error-rate-warning"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  threshold           = 0.3 # 0.3% - approaching 0.5% threshold
  alarm_description   = <<-EOT
    WARNING: Liberty error rate is approaching 0.5% SLO threshold.
    Investigate the source of errors to prevent SLO breach.
    SLO Target: Error Rate < 0.5%
    Runbook: docs/runbooks/liberty-high-error-rate.md
  EOT
  treat_missing_data  = "notBreaching"
  actions_enabled     = true

  alarm_actions = [aws_sns_topic.slo_alerts[0].arn]
  ok_actions    = [aws_sns_topic.slo_alerts[0].arn]

  metric_query {
    id          = "error_rate"
    expression  = "IF(total_requests > 0, (error_requests / total_requests) * 100, 0)"
    label       = "Error Rate %"
    return_data = true
  }

  metric_query {
    id = "error_requests"
    metric {
      metric_name = "HTTPCode_Target_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.main.arn_suffix
        TargetGroup  = aws_lb_target_group.liberty_ecs[0].arn_suffix
      }
    }
  }

  metric_query {
    id = "total_requests"
    metric {
      metric_name = "RequestCount"
      namespace   = "AWS/ApplicationELB"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.main.arn_suffix
        TargetGroup  = aws_lb_target_group.liberty_ecs[0].arn_suffix
      }
    }
  }

  tags = {
    Name     = "${local.name_prefix}-slo-error-rate-warning"
    SLO      = "error_rate"
    Severity = "warning"
  }
}

# =============================================================================
# Health Check Alarms
# =============================================================================

# -----------------------------------------------------------------------------
# Critical: Unhealthy Target Count
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "slo_unhealthy_targets" {
  count = var.ecs_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-slo-unhealthy-targets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = <<-EOT
    CRITICAL: One or more Liberty ECS tasks are unhealthy.
    This may indicate application crashes, failed health checks, or deployment issues.
    Runbook: docs/runbooks/liberty-server-down.md
  EOT
  treat_missing_data  = "notBreaching"
  actions_enabled     = true

  alarm_actions = [aws_sns_topic.slo_alerts[0].arn]
  ok_actions    = [aws_sns_topic.slo_alerts[0].arn]

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.liberty_ecs[0].arn_suffix
  }

  tags = {
    Name     = "${local.name_prefix}-slo-unhealthy-targets"
    SLO      = "availability"
    Severity = "critical"
  }
}

# -----------------------------------------------------------------------------
# Warning: Low Healthy Target Count
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "slo_low_healthy_targets" {
  count = var.ecs_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-slo-low-healthy-targets"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Minimum"
  threshold           = var.ecs_min_capacity
  alarm_description   = <<-EOT
    WARNING: Number of healthy Liberty ECS tasks is below minimum capacity (${var.ecs_min_capacity}).
    Service capacity is degraded. Check ECS service events and task logs.
    Runbook: docs/runbooks/liberty-server-down.md
  EOT
  treat_missing_data  = "notBreaching"
  actions_enabled     = true

  alarm_actions = [aws_sns_topic.slo_alerts[0].arn]
  ok_actions    = [aws_sns_topic.slo_alerts[0].arn]

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.liberty_ecs[0].arn_suffix
  }

  tags = {
    Name     = "${local.name_prefix}-slo-low-healthy-targets"
    SLO      = "availability"
    Severity = "warning"
  }
}

# =============================================================================
# ECS Service Alarms
# =============================================================================

# -----------------------------------------------------------------------------
# Warning: High CPU Utilization
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "slo_ecs_cpu_high" {
  count = var.ecs_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-slo-ecs-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 85
  alarm_description   = <<-EOT
    WARNING: Liberty ECS service CPU utilization is above 85%.
    This may lead to performance degradation and latency issues.
    Consider scaling up or optimizing application performance.
    Runbook: docs/runbooks/liberty-slow-responses.md
  EOT
  treat_missing_data  = "notBreaching"
  actions_enabled     = true

  alarm_actions = [aws_sns_topic.slo_alerts[0].arn]
  ok_actions    = [aws_sns_topic.slo_alerts[0].arn]

  dimensions = {
    ClusterName = aws_ecs_cluster.main[0].name
    ServiceName = aws_ecs_service.liberty[0].name
  }

  tags = {
    Name     = "${local.name_prefix}-slo-ecs-cpu-high"
    SLO      = "latency"
    Severity = "warning"
  }
}

# -----------------------------------------------------------------------------
# Warning: High Memory Utilization
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "slo_ecs_memory_high" {
  count = var.ecs_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-slo-ecs-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 85
  alarm_description   = <<-EOT
    WARNING: Liberty ECS service memory utilization is above 85%.
    JVM heap pressure may cause GC pauses and latency spikes.
    Consider increasing task memory or optimizing heap settings.
    Runbook: docs/runbooks/liberty-high-heap.md
  EOT
  treat_missing_data  = "notBreaching"
  actions_enabled     = true

  alarm_actions = [aws_sns_topic.slo_alerts[0].arn]
  ok_actions    = [aws_sns_topic.slo_alerts[0].arn]

  dimensions = {
    ClusterName = aws_ecs_cluster.main[0].name
    ServiceName = aws_ecs_service.liberty[0].name
  }

  tags = {
    Name     = "${local.name_prefix}-slo-ecs-memory-high"
    SLO      = "latency"
    Severity = "warning"
  }
}

# =============================================================================
# Composite Alarm for Overall SLO Health
# =============================================================================

resource "aws_cloudwatch_composite_alarm" "slo_overall_health" {
  count = var.ecs_enabled ? 1 : 0

  alarm_name        = "${local.name_prefix}-slo-overall-health"
  alarm_description = <<-EOT
    Overall SLO health composite alarm.
    Triggers when ANY critical SLO alarm is in ALARM state.
    This is the primary alert for on-call responders.
  EOT

  alarm_rule = <<-EOT
    ALARM(${aws_cloudwatch_metric_alarm.slo_availability_critical[0].alarm_name}) OR
    ALARM(${aws_cloudwatch_metric_alarm.slo_latency_p95_critical[0].alarm_name}) OR
    ALARM(${aws_cloudwatch_metric_alarm.slo_error_rate_breach[0].alarm_name}) OR
    ALARM(${aws_cloudwatch_metric_alarm.slo_unhealthy_targets[0].alarm_name})
  EOT

  actions_enabled = true
  alarm_actions   = [aws_sns_topic.slo_alerts[0].arn]
  ok_actions      = [aws_sns_topic.slo_alerts[0].arn]

  tags = {
    Name     = "${local.name_prefix}-slo-overall-health"
    SLO      = "composite"
    Severity = "critical"
  }
}

# =============================================================================
# Outputs
# =============================================================================

output "slo_alerts_sns_topic_arn" {
  description = "ARN of the SNS topic for SLO alerts"
  value       = var.ecs_enabled ? aws_sns_topic.slo_alerts[0].arn : null
}

output "slo_alarms" {
  description = "List of SLO CloudWatch alarm ARNs"
  value = var.ecs_enabled ? {
    availability_critical = aws_cloudwatch_metric_alarm.slo_availability_critical[0].arn
    availability_warning  = aws_cloudwatch_metric_alarm.slo_availability_warning[0].arn
    latency_p95_critical  = aws_cloudwatch_metric_alarm.slo_latency_p95_critical[0].arn
    latency_p95_warning   = aws_cloudwatch_metric_alarm.slo_latency_p95_warning[0].arn
    latency_p99_critical  = aws_cloudwatch_metric_alarm.slo_latency_p99_critical[0].arn
    error_rate_breach     = aws_cloudwatch_metric_alarm.slo_error_rate_breach[0].arn
    error_rate_warning    = aws_cloudwatch_metric_alarm.slo_error_rate_warning[0].arn
    unhealthy_targets     = aws_cloudwatch_metric_alarm.slo_unhealthy_targets[0].arn
    overall_health        = aws_cloudwatch_composite_alarm.slo_overall_health[0].arn
  } : null
}
