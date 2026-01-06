# =============================================================================
# ECS Module - Outputs
# =============================================================================

output "cluster_id" {
  description = "ID of the ECS cluster"
  value       = aws_ecs_cluster.main.id
}

output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "service_id" {
  description = "ID of the ECS service"
  value       = aws_ecs_service.main.id
}

output "service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.main.name
}

output "task_definition_arn" {
  description = "ARN of the task definition"
  value       = aws_ecs_task_definition.main.arn
}

output "task_execution_role_arn" {
  description = "ARN of the task execution role"
  value       = aws_iam_role.ecs_execution.arn
}

output "task_role_arn" {
  description = "ARN of the task role"
  value       = aws_iam_role.ecs_task.arn
}

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = var.create_ecr_repository ? aws_ecr_repository.main[0].repository_url : null
}

output "ecr_repository_arn" {
  description = "ARN of the ECR repository"
  value       = var.create_ecr_repository ? aws_ecr_repository.main[0].arn : null
}

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.ecs.name
}

# =============================================================================
# Auto-Scaling Outputs
# =============================================================================

output "autoscaling_enabled" {
  description = "Whether auto-scaling is enabled"
  value       = var.enable_autoscaling
}

output "autoscaling_target_arn" {
  description = "ARN of the auto-scaling target"
  value       = var.enable_autoscaling ? aws_appautoscaling_target.ecs[0].id : null
}

output "autoscaling_min_capacity" {
  description = "Minimum capacity for auto-scaling"
  value       = var.enable_autoscaling ? var.min_capacity : null
}

output "autoscaling_max_capacity" {
  description = "Maximum capacity for auto-scaling"
  value       = var.enable_autoscaling ? var.max_capacity : null
}

# =============================================================================
# Blue-Green Deployment Outputs
# =============================================================================

output "blue_green_enabled" {
  description = "Whether blue-green deployments are enabled"
  value       = var.enable_blue_green
}

output "green_target_group_arn" {
  description = "ARN of the green target group for blue-green deployments"
  value       = var.enable_blue_green && var.vpc_id != null ? aws_lb_target_group.green[0].arn : null
}

output "green_target_group_name" {
  description = "Name of the green target group for blue-green deployments"
  value       = var.enable_blue_green && var.vpc_id != null ? aws_lb_target_group.green[0].name : null
}

output "codedeploy_app_name" {
  description = "Name of the CodeDeploy application"
  value       = var.enable_blue_green ? aws_codedeploy_app.ecs[0].name : null
}

output "codedeploy_deployment_group_name" {
  description = "Name of the CodeDeploy deployment group"
  value       = var.enable_blue_green && var.listener_arn != null ? aws_codedeploy_deployment_group.ecs[0].deployment_group_name : null
}

output "codedeploy_role_arn" {
  description = "ARN of the CodeDeploy IAM role"
  value       = var.enable_blue_green ? aws_iam_role.codedeploy[0].arn : null
}

# =============================================================================
# Fargate Spot Outputs
# =============================================================================

output "fargate_spot_weight" {
  description = "Weight assigned to FARGATE_SPOT capacity provider"
  value       = var.fargate_spot_weight
}

# =============================================================================
# X-Ray / OpenTelemetry Outputs
# =============================================================================

output "xray_enabled" {
  description = "Whether X-Ray tracing is enabled"
  value       = var.enable_xray
}

output "xray_policy_arn" {
  description = "ARN of the X-Ray IAM policy"
  value       = var.enable_xray ? aws_iam_policy.xray[0].arn : null
}

output "otel_service_name" {
  description = "OpenTelemetry service name configured for tracing"
  value       = var.enable_xray || var.otel_collector_endpoint != "" ? var.otel_service_name : null
}

# =============================================================================
# SLO Alarms Outputs
# =============================================================================

output "slo_alarms_enabled" {
  description = "Whether SLO alarms are enabled"
  value       = var.enable_slo_alarms
}

output "cpu_alarm_arn" {
  description = "ARN of the CPU high utilization alarm"
  value       = var.enable_slo_alarms ? aws_cloudwatch_metric_alarm.cpu_high[0].arn : null
}

output "memory_alarm_arn" {
  description = "ARN of the memory high utilization alarm"
  value       = var.enable_slo_alarms ? aws_cloudwatch_metric_alarm.memory_high[0].arn : null
}

output "unhealthy_tasks_alarm_arn" {
  description = "ARN of the unhealthy tasks alarm"
  value       = var.enable_slo_alarms && var.target_group_arn != null && var.alb_arn_suffix != null ? aws_cloudwatch_metric_alarm.unhealthy_tasks[0].arn : null
}

# =============================================================================
# Service Discovery Outputs (for external alarm configuration)
# =============================================================================

output "service_discovery" {
  description = "Service discovery information for external monitoring/alerting systems"
  value = {
    cluster_name = aws_ecs_cluster.main.name
    service_name = aws_ecs_service.main.name
    cluster_arn  = aws_ecs_cluster.main.arn
    service_arn  = aws_ecs_service.main.id
  }
}

# =============================================================================
# ECR Cross-Region Replication Outputs
# =============================================================================

output "ecr_replication_enabled" {
  description = "Whether ECR cross-region replication is enabled"
  value       = var.ecr_replication_enabled
}

output "ecr_replication_region" {
  description = "ECR replication destination region"
  value       = var.ecr_replication_enabled ? var.ecr_replication_region : null
}
