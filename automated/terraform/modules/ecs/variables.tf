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
