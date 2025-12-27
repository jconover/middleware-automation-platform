# =============================================================================
# ECS Auto Scaling
# =============================================================================
# Scale ECS service based on CPU and memory utilization
# =============================================================================

# -----------------------------------------------------------------------------
# Auto Scaling Target
# -----------------------------------------------------------------------------
resource "aws_appautoscaling_target" "liberty" {
  count = var.ecs_enabled ? 1 : 0

  max_capacity       = var.ecs_max_capacity
  min_capacity       = var.ecs_min_capacity
  resource_id        = "service/${aws_ecs_cluster.main[0].name}/${aws_ecs_service.liberty[0].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# -----------------------------------------------------------------------------
# CPU-based Scaling Policy
# -----------------------------------------------------------------------------
resource "aws_appautoscaling_policy" "liberty_cpu" {
  count = var.ecs_enabled ? 1 : 0

  name               = "${local.name_prefix}-liberty-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.liberty[0].resource_id
  scalable_dimension = aws_appautoscaling_target.liberty[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.liberty[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.ecs_cpu_target
    scale_in_cooldown  = 300  # 5 minutes
    scale_out_cooldown = 60   # 1 minute
  }
}

# -----------------------------------------------------------------------------
# Memory-based Scaling Policy
# -----------------------------------------------------------------------------
resource "aws_appautoscaling_policy" "liberty_memory" {
  count = var.ecs_enabled ? 1 : 0

  name               = "${local.name_prefix}-liberty-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.liberty[0].resource_id
  scalable_dimension = aws_appautoscaling_target.liberty[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.liberty[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = var.ecs_memory_target
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# -----------------------------------------------------------------------------
# Request Count Scaling Policy (based on ALB requests)
# -----------------------------------------------------------------------------
resource "aws_appautoscaling_policy" "liberty_requests" {
  count = var.ecs_enabled ? 1 : 0

  name               = "${local.name_prefix}-liberty-request-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.liberty[0].resource_id
  scalable_dimension = aws_appautoscaling_target.liberty[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.liberty[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.main.arn_suffix}/${aws_lb_target_group.liberty_ecs[0].arn_suffix}"
    }
    target_value       = var.ecs_requests_per_target
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# Scaling variables are defined in variables.tf with validation
