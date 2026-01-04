# =============================================================================
# ECS Module - Variables
# =============================================================================

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for ECS tasks"
  type        = list(string)
}

variable "container_image" {
  description = "Docker image for the ECS task"
  type        = string
}

variable "task_cpu" {
  description = "CPU units for ECS task"
  type        = number
  default     = 512

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.task_cpu)
    error_message = "Task CPU must be one of: 256, 512, 1024, 2048, 4096."
  }
}

variable "task_memory" {
  description = "Memory for ECS task in MB"
  type        = number
  default     = 1024

  validation {
    condition     = var.task_memory >= 512 && var.task_memory <= 30720
    error_message = "Task memory must be between 512 and 30720 MB."
  }
}

variable "container_name" {
  description = "Name of the container"
  type        = string
  default     = "liberty"
}

variable "desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 2
}

variable "environment_variables" {
  description = "Environment variables for the container"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "secrets" {
  description = "Secrets from AWS Secrets Manager"
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "secrets_arns" {
  description = "ARNs of secrets the task execution role needs access to"
  type        = list(string)
  default     = []
}

variable "target_group_arn" {
  description = "ARN of the target group for load balancer"
  type        = string
  default     = null
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights"
  type        = bool
  default     = true
}

variable "enable_execute_command" {
  description = "Enable ECS Exec for debugging"
  type        = bool
  default     = true
}

variable "create_ecr_repository" {
  description = "Create ECR repository"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# =============================================================================
# Auto-Scaling Variables
# =============================================================================

variable "enable_autoscaling" {
  description = "Enable auto-scaling for the ECS service"
  type        = bool
  default     = false
}

variable "enable_request_scaling" {
  description = "Enable request-count based scaling (requires ALB integration)"
  type        = bool
  default     = false
}

variable "min_capacity" {
  description = "Minimum number of ECS tasks for auto-scaling"
  type        = number
  default     = 2

  validation {
    condition     = var.min_capacity >= 1
    error_message = "Minimum capacity must be at least 1."
  }
}

variable "max_capacity" {
  description = "Maximum number of ECS tasks for auto-scaling"
  type        = number
  default     = 6

  validation {
    condition     = var.max_capacity >= 1
    error_message = "Maximum capacity must be at least 1."
  }
}

variable "cpu_target" {
  description = "Target CPU utilization percentage for auto-scaling"
  type        = number
  default     = 70

  validation {
    condition     = var.cpu_target >= 10 && var.cpu_target <= 100
    error_message = "CPU target must be between 10 and 100."
  }
}

variable "memory_target" {
  description = "Target memory utilization percentage for auto-scaling"
  type        = number
  default     = 80

  validation {
    condition     = var.memory_target >= 10 && var.memory_target <= 100
    error_message = "Memory target must be between 10 and 100."
  }
}

variable "request_count_target" {
  description = "Target request count per target for auto-scaling (requires ALB)"
  type        = number
  default     = 1000

  validation {
    condition     = var.request_count_target >= 1
    error_message = "Request count target must be at least 1."
  }
}

variable "alb_arn_suffix" {
  description = "ARN suffix of the ALB (required for request count scaling)"
  type        = string
  default     = null
}

variable "scale_in_cooldown" {
  description = "Cooldown period in seconds for scale-in actions"
  type        = number
  default     = 300
}

variable "scale_out_cooldown" {
  description = "Cooldown period in seconds for scale-out actions"
  type        = number
  default     = 60
}

# =============================================================================
# Blue-Green Deployment Variables (CodeDeploy)
# =============================================================================

variable "enable_blue_green" {
  description = <<-EOT
    Enable Blue-Green deployments using AWS CodeDeploy.
    When enabled:
    - Creates a second target group for blue-green deployments
    - Creates CodeDeploy application and deployment group
    - Changes ECS service deployment_controller to CODE_DEPLOY
    - Disables circuit breaker (incompatible with CodeDeploy)

    Requires: target_group_arn to be set for the primary target group
  EOT
  type        = bool
  default     = false
}

variable "green_target_group_arn" {
  description = "ARN of the green target group for blue-green deployments (if external)"
  type        = string
  default     = null
}

variable "vpc_id" {
  description = "VPC ID (required for blue-green to create green target group)"
  type        = string
  default     = null
}

variable "listener_arn" {
  description = "ARN of the ALB listener (required for blue-green deployments)"
  type        = string
  default     = null
}

variable "codedeploy_deployment_config" {
  description = "CodeDeploy deployment configuration name"
  type        = string
  default     = "CodeDeployDefault.ECSLinear10PercentEvery1Minutes"
}

variable "blue_green_termination_wait_minutes" {
  description = "Minutes to wait before terminating blue instances after successful deployment"
  type        = number
  default     = 5
}

# =============================================================================
# Fargate Spot Variables
# =============================================================================

variable "fargate_spot_weight" {
  description = <<-EOT
    Weight for FARGATE_SPOT capacity provider (0-100).
    Higher values mean more tasks will use Spot instances.
    Spot instances are up to 70% cheaper but may be interrupted.

    Recommended: 0 for production critical workloads, 50-70 for cost optimization

    Example: fargate_spot_weight = 70 means ~70% of tasks above baseline use Spot
  EOT
  type        = number
  default     = 0

  validation {
    condition     = var.fargate_spot_weight >= 0 && var.fargate_spot_weight <= 100
    error_message = "Fargate spot weight must be between 0 and 100."
  }
}

# =============================================================================
# X-Ray / OpenTelemetry Variables
# =============================================================================

variable "enable_xray" {
  description = <<-EOT
    Enable AWS X-Ray for distributed tracing.
    When enabled:
    - Adds X-Ray permissions to task role
    - Sets OTEL environment variables to export to X-Ray

    Cost: ~$5 per million traces (first 100k free)
  EOT
  type        = bool
  default     = false
}

variable "otel_collector_endpoint" {
  description = <<-EOT
    OpenTelemetry Collector endpoint for trace export.
    Used when enable_xray is false for sending traces to external backends.
    Example: "http://otel-collector:4317"
  EOT
  type        = string
  default     = ""
}

variable "otel_service_name" {
  description = "Service name for OpenTelemetry traces"
  type        = string
  default     = "liberty-app"
}

variable "otel_environment" {
  description = "Deployment environment for OpenTelemetry resource attributes"
  type        = string
  default     = "production"
}

# =============================================================================
# SLO Alarms Variables
# =============================================================================

variable "enable_slo_alarms" {
  description = <<-EOT
    Enable SLO-based CloudWatch alarms.
    Creates basic alarms for:
    - High CPU utilization
    - High memory utilization
    - Unhealthy host count

    Outputs cluster_name and service_name for external alarm configuration.
  EOT
  type        = bool
  default     = false
}

variable "slo_cpu_threshold" {
  description = "CPU utilization threshold percentage for SLO alarm"
  type        = number
  default     = 85
}

variable "slo_memory_threshold" {
  description = "Memory utilization threshold percentage for SLO alarm"
  type        = number
  default     = 85
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for alarm notifications"
  type        = string
  default     = null
}
