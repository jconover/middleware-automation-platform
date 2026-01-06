# =============================================================================
# SLO/SLI CloudWatch Alarms for Liberty Application
# =============================================================================
# AWS-native alarms corresponding to the Kubernetes SLO framework.
# These alarms monitor the same SLO targets using ALB and ECS metrics.
#
# SLO Definitions (configurable via variables):
#   - Availability: 99.9% default (error rate < 0.1%)
#   - Latency: p99 < 500ms default
#   - Error Rate: < 0.5% (5xx responses)
#
# Burn Rate Strategy:
#   CloudWatch alarms use multi-period evaluation to detect both rapid
#   incidents and slow degradation of service quality.
# =============================================================================

# -----------------------------------------------------------------------------
# Local Values for SLO Calculations
# -----------------------------------------------------------------------------
locals {
  # Determine effective email for SLO alerts
  slo_alert_email = var.slo_alert_email != "" ? var.slo_alert_email : var.security_alert_email

  # Calculate burn rate thresholds based on availability target
  # Error budget = 100 - availability_target (e.g., 99.9% availability = 0.1% error budget)
  error_budget_percent = 100 - var.slo_availability_target

  # Critical: 14.4x burn rate = exhaust monthly budget in ~2 hours
  critical_error_threshold = local.error_budget_percent * 14.4

  # Warning: 6x burn rate = exhaust monthly budget in ~5 days
  warning_error_threshold = local.error_budget_percent * 6

  # Latency thresholds in seconds for CloudWatch
  latency_threshold_seconds         = var.slo_latency_threshold_ms / 1000
  latency_warning_threshold_seconds = (var.slo_latency_threshold_ms * 0.8) / 1000 # 80% of threshold

  # Determine which target group to monitor (prefer ECS over EC2)
  monitor_ecs        = var.ecs_enabled && var.enable_slo_alarms
  monitor_ec2        = !var.ecs_enabled && var.liberty_instance_count > 0 && var.enable_slo_alarms
  slo_alarms_enabled = local.monitor_ecs || local.monitor_ec2

  # Target group ARN suffix based on deployment type
  target_group_arn_suffix = local.monitor_ecs ? module.loadbalancer.ecs_target_group_arn_suffix : (
    local.monitor_ec2 ? module.loadbalancer.ec2_target_group_arn_suffix : null
  )
}

# -----------------------------------------------------------------------------
# SNS Topic for SLO Alerts
# -----------------------------------------------------------------------------
resource "aws_sns_topic" "slo_alerts" {
  count = local.slo_alarms_enabled ? 1 : 0

  name = "${local.name_prefix}-slo-alerts"

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-slo-alerts"
    Purpose = "SLO/SLI alerting"
  })
}

# Email subscription for SLO alerts
resource "aws_sns_topic_subscription" "slo_alerts_email" {
  count = local.slo_alarms_enabled && local.slo_alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.slo_alerts[0].arn
  protocol  = "email"
  endpoint  = local.slo_alert_email
}

# =============================================================================
# Availability SLO Alarms
# =============================================================================
# Monitor 5xx error rate from ALB target group metrics

# -----------------------------------------------------------------------------
# Critical: High 5xx Rate (Burn Rate > 14x)
# Error rate indicates severe incident - budget exhaustion in ~2 hours
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "slo_availability_critical" {
  count = local.slo_alarms_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-slo-availability-critical"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = local.critical_error_threshold
  alarm_description   = <<-EOT
    CRITICAL: Liberty availability SLO burn rate is 14.4x - error budget exhaustion in ~2 hours.
    At this rate, the entire monthly error budget (${local.error_budget_percent}%) will be exhausted quickly.
    SLO Target: ${var.slo_availability_target}% availability
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
        LoadBalancer = module.loadbalancer.alb_arn_suffix
        TargetGroup  = local.target_group_arn_suffix
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
        LoadBalancer = module.loadbalancer.alb_arn_suffix
        TargetGroup  = local.target_group_arn_suffix
      }
    }
  }

  tags = merge(local.common_tags, {
    Name     = "${local.name_prefix}-slo-availability-critical"
    SLO      = "availability"
    Severity = "critical"
  })
}

# -----------------------------------------------------------------------------
# Warning: Elevated 5xx Rate (Burn Rate > 6x)
# Error rate indicates degradation - budget exhaustion in ~5 days
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "slo_availability_warning" {
  count = local.slo_alarms_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-slo-availability-warning"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 6 # 30 minutes (6 x 5-min periods)
  threshold           = local.warning_error_threshold
  alarm_description   = <<-EOT
    WARNING: Liberty availability SLO burn rate is 6x - error budget exhaustion in ~5 days.
    Investigate degraded performance or partial outages.
    SLO Target: ${var.slo_availability_target}% availability
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
        LoadBalancer = module.loadbalancer.alb_arn_suffix
        TargetGroup  = local.target_group_arn_suffix
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
        LoadBalancer = module.loadbalancer.alb_arn_suffix
        TargetGroup  = local.target_group_arn_suffix
      }
    }
  }

  tags = merge(local.common_tags, {
    Name     = "${local.name_prefix}-slo-availability-warning"
    SLO      = "availability"
    Severity = "warning"
  })
}

# =============================================================================
# Latency SLO Alarms
# =============================================================================
# Monitor response time from ALB target response time metric

# -----------------------------------------------------------------------------
# Critical: p99 Latency exceeds threshold
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "slo_latency_p99_critical" {
  count = local.slo_alarms_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-slo-latency-p99-critical"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  extended_statistic  = "p99"
  threshold           = local.latency_threshold_seconds
  alarm_description   = <<-EOT
    CRITICAL: Liberty p99 latency exceeds ${var.slo_latency_threshold_ms}ms SLO target.
    1% of users are experiencing unacceptably slow responses.
    SLO Target: p99 < ${var.slo_latency_threshold_ms}ms
    Runbook: docs/runbooks/liberty-slow-responses.md
  EOT
  treat_missing_data  = "notBreaching"
  actions_enabled     = true

  alarm_actions = [aws_sns_topic.slo_alerts[0].arn]
  ok_actions    = [aws_sns_topic.slo_alerts[0].arn]

  dimensions = {
    LoadBalancer = module.loadbalancer.alb_arn_suffix
    TargetGroup  = local.target_group_arn_suffix
  }

  tags = merge(local.common_tags, {
    Name     = "${local.name_prefix}-slo-latency-p99-critical"
    SLO      = "latency"
    Severity = "critical"
  })
}

# -----------------------------------------------------------------------------
# Warning: p99 Latency approaching threshold (80%)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "slo_latency_p99_warning" {
  count = local.slo_alarms_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-slo-latency-p99-warning"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  extended_statistic  = "p99"
  threshold           = local.latency_warning_threshold_seconds
  alarm_description   = <<-EOT
    WARNING: Liberty p99 latency is at 80% of the ${var.slo_latency_threshold_ms}ms SLO threshold.
    Investigate performance issues before SLO breach.
    SLO Target: p99 < ${var.slo_latency_threshold_ms}ms
    Runbook: docs/runbooks/liberty-slow-responses.md
  EOT
  treat_missing_data  = "notBreaching"
  actions_enabled     = true

  alarm_actions = [aws_sns_topic.slo_alerts[0].arn]
  ok_actions    = [aws_sns_topic.slo_alerts[0].arn]

  dimensions = {
    LoadBalancer = module.loadbalancer.alb_arn_suffix
    TargetGroup  = local.target_group_arn_suffix
  }

  tags = merge(local.common_tags, {
    Name     = "${local.name_prefix}-slo-latency-p99-warning"
    SLO      = "latency"
    Severity = "warning"
  })
}

# -----------------------------------------------------------------------------
# Critical: p99 Latency > 2 seconds (tail latency - severe degradation)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "slo_latency_tail_critical" {
  count = local.slo_alarms_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-slo-latency-tail-critical"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  extended_statistic  = "p99"
  threshold           = 2.0 # 2 seconds - severe tail latency
  alarm_description   = <<-EOT
    CRITICAL: Liberty p99 latency exceeds 2 seconds.
    Severe performance degradation affecting user experience.
    Runbook: docs/runbooks/liberty-slow-responses.md
  EOT
  treat_missing_data  = "notBreaching"
  actions_enabled     = true

  alarm_actions = [aws_sns_topic.slo_alerts[0].arn]
  ok_actions    = [aws_sns_topic.slo_alerts[0].arn]

  dimensions = {
    LoadBalancer = module.loadbalancer.alb_arn_suffix
    TargetGroup  = local.target_group_arn_suffix
  }

  tags = merge(local.common_tags, {
    Name     = "${local.name_prefix}-slo-latency-tail-critical"
    SLO      = "latency"
    Severity = "critical"
  })
}

# =============================================================================
# Error Rate SLO Alarms
# =============================================================================
# Direct threshold monitoring for error rate SLO

# -----------------------------------------------------------------------------
# Critical: Error Rate > 0.5% (SLO Breach)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "slo_error_rate_breach" {
  count = local.slo_alarms_enabled ? 1 : 0

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
        LoadBalancer = module.loadbalancer.alb_arn_suffix
        TargetGroup  = local.target_group_arn_suffix
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
        LoadBalancer = module.loadbalancer.alb_arn_suffix
        TargetGroup  = local.target_group_arn_suffix
      }
    }
  }

  tags = merge(local.common_tags, {
    Name     = "${local.name_prefix}-slo-error-rate-breach"
    SLO      = "error_rate"
    Severity = "critical"
  })
}

# -----------------------------------------------------------------------------
# Warning: Error Rate > 0.3% (approaching threshold)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "slo_error_rate_warning" {
  count = local.slo_alarms_enabled ? 1 : 0

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
        LoadBalancer = module.loadbalancer.alb_arn_suffix
        TargetGroup  = local.target_group_arn_suffix
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
        LoadBalancer = module.loadbalancer.alb_arn_suffix
        TargetGroup  = local.target_group_arn_suffix
      }
    }
  }

  tags = merge(local.common_tags, {
    Name     = "${local.name_prefix}-slo-error-rate-warning"
    SLO      = "error_rate"
    Severity = "warning"
  })
}

# =============================================================================
# Health Check Alarms
# =============================================================================

# -----------------------------------------------------------------------------
# Critical: Unhealthy Target Count
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "slo_unhealthy_targets" {
  count = local.slo_alarms_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-slo-unhealthy-targets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = <<-EOT
    CRITICAL: One or more Liberty targets are unhealthy.
    This may indicate application crashes, failed health checks, or deployment issues.
    Runbook: docs/runbooks/liberty-server-down.md
  EOT
  treat_missing_data  = "notBreaching"
  actions_enabled     = true

  alarm_actions = [aws_sns_topic.slo_alerts[0].arn]
  ok_actions    = [aws_sns_topic.slo_alerts[0].arn]

  dimensions = {
    LoadBalancer = module.loadbalancer.alb_arn_suffix
    TargetGroup  = local.target_group_arn_suffix
  }

  tags = merge(local.common_tags, {
    Name     = "${local.name_prefix}-slo-unhealthy-targets"
    SLO      = "availability"
    Severity = "critical"
  })
}

# -----------------------------------------------------------------------------
# Warning: Low Healthy Target Count
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "slo_low_healthy_targets" {
  count = local.slo_alarms_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-slo-low-healthy-targets"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Minimum"
  threshold           = local.monitor_ecs ? var.ecs_min_capacity : var.liberty_instance_count
  alarm_description   = <<-EOT
    WARNING: Number of healthy Liberty targets is below minimum capacity.
    Service capacity is degraded. Check service events and logs.
    Runbook: docs/runbooks/liberty-server-down.md
  EOT
  treat_missing_data  = "notBreaching"
  actions_enabled     = true

  alarm_actions = [aws_sns_topic.slo_alerts[0].arn]
  ok_actions    = [aws_sns_topic.slo_alerts[0].arn]

  dimensions = {
    LoadBalancer = module.loadbalancer.alb_arn_suffix
    TargetGroup  = local.target_group_arn_suffix
  }

  tags = merge(local.common_tags, {
    Name     = "${local.name_prefix}-slo-low-healthy-targets"
    SLO      = "availability"
    Severity = "warning"
  })
}

# =============================================================================
# ECS Service Alarms (only when ECS is enabled)
# =============================================================================

# -----------------------------------------------------------------------------
# Warning: High CPU Utilization
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "slo_ecs_cpu_high" {
  count = local.monitor_ecs ? 1 : 0

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
    ClusterName = module.ecs[0].cluster_name
    ServiceName = module.ecs[0].service_name
  }

  tags = merge(local.common_tags, {
    Name     = "${local.name_prefix}-slo-ecs-cpu-high"
    SLO      = "latency"
    Severity = "warning"
  })
}

# -----------------------------------------------------------------------------
# Warning: High Memory Utilization
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "slo_ecs_memory_high" {
  count = local.monitor_ecs ? 1 : 0

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
    ClusterName = module.ecs[0].cluster_name
    ServiceName = module.ecs[0].service_name
  }

  tags = merge(local.common_tags, {
    Name     = "${local.name_prefix}-slo-ecs-memory-high"
    SLO      = "latency"
    Severity = "warning"
  })
}

# =============================================================================
# Composite Alarm for Overall SLO Health
# =============================================================================

resource "aws_cloudwatch_composite_alarm" "slo_overall_health" {
  count = local.slo_alarms_enabled ? 1 : 0

  alarm_name        = "${local.name_prefix}-slo-overall-health"
  alarm_description = <<-EOT
    Overall SLO health composite alarm.
    Triggers when ANY critical SLO alarm is in ALARM state.
    This is the primary alert for on-call responders.

    Critical alarms included:
    - Availability (high error rate)
    - Latency (p99 threshold breach)
    - Error Rate (>0.5%)
    - Unhealthy Targets
  EOT

  alarm_rule = <<-EOT
    ALARM(${aws_cloudwatch_metric_alarm.slo_availability_critical[0].alarm_name}) OR
    ALARM(${aws_cloudwatch_metric_alarm.slo_latency_p99_critical[0].alarm_name}) OR
    ALARM(${aws_cloudwatch_metric_alarm.slo_error_rate_breach[0].alarm_name}) OR
    ALARM(${aws_cloudwatch_metric_alarm.slo_unhealthy_targets[0].alarm_name})
  EOT

  actions_enabled = true
  alarm_actions   = [aws_sns_topic.slo_alerts[0].arn]
  ok_actions      = [aws_sns_topic.slo_alerts[0].arn]

  tags = merge(local.common_tags, {
    Name     = "${local.name_prefix}-slo-overall-health"
    SLO      = "composite"
    Severity = "critical"
  })
}
