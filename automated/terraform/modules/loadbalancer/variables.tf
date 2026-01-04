# =============================================================================
# Load Balancer Module - Variables
# =============================================================================

# -----------------------------------------------------------------------------
# General Configuration
# -----------------------------------------------------------------------------
variable "name_prefix" {
  description = "Prefix for resource names (e.g., 'mw-prod')"
  type        = string

  validation {
    condition     = length(var.name_prefix) >= 2 && length(var.name_prefix) <= 20
    error_message = "Name prefix must be between 2 and 20 characters."
  }

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name_prefix))
    error_message = "Name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be a valid format (e.g., us-east-1, eu-west-2)."
  }
}

# -----------------------------------------------------------------------------
# Network Configuration
# -----------------------------------------------------------------------------
variable "vpc_id" {
  description = "ID of the VPC where the ALB will be deployed"
  type        = string

  validation {
    condition     = can(regex("^vpc-[a-f0-9]+$", var.vpc_id))
    error_message = "VPC ID must be a valid AWS VPC identifier (vpc-*)."
  }
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for the ALB"
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "At least 2 public subnets are required for ALB high availability."
  }

  validation {
    condition = alltrue([
      for subnet_id in var.public_subnet_ids : can(regex("^subnet-[a-f0-9]+$", subnet_id))
    ])
    error_message = "All subnet IDs must be valid AWS subnet identifiers (subnet-*)."
  }
}

variable "alb_security_group_id" {
  description = "ID of the security group to attach to the ALB"
  type        = string

  validation {
    condition     = can(regex("^sg-[a-f0-9]+$", var.alb_security_group_id))
    error_message = "Security group ID must be a valid AWS security group identifier (sg-*)."
  }
}

# -----------------------------------------------------------------------------
# ALB Configuration
# -----------------------------------------------------------------------------
variable "internal" {
  description = "Whether the ALB is internal (true) or internet-facing (false)"
  type        = bool
  default     = false
}

variable "idle_timeout" {
  description = "The time in seconds that the connection is allowed to be idle"
  type        = number
  default     = 60

  validation {
    condition     = var.idle_timeout >= 1 && var.idle_timeout <= 4000
    error_message = "Idle timeout must be between 1 and 4000 seconds."
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for the ALB"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# HTTPS / Certificate Configuration
# -----------------------------------------------------------------------------
variable "enable_https" {
  description = "Enable HTTPS listener (creates self-signed cert if certificate_arn not provided)"
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "ARN of an existing ACM certificate for HTTPS. If empty and enable_https is true, a self-signed certificate will be created."
  type        = string
  default     = ""

  validation {
    condition = (
      var.certificate_arn == "" ||
      can(regex("^arn:aws:acm:[a-z0-9-]+:[0-9]{12}:certificate/[a-f0-9-]+$", var.certificate_arn))
    )
    error_message = "Certificate ARN must be empty or a valid ACM certificate ARN format."
  }
}

variable "additional_certificate_arn" {
  description = "ARN of an additional ACM certificate for the HTTPS listener (for multiple domains)"
  type        = string
  default     = ""

  validation {
    condition = (
      var.additional_certificate_arn == "" ||
      can(regex("^arn:aws:acm:[a-z0-9-]+:[0-9]{12}:certificate/[a-f0-9-]+$", var.additional_certificate_arn))
    )
    error_message = "Additional certificate ARN must be empty or a valid ACM certificate ARN format."
  }
}

variable "ssl_policy" {
  description = "SSL policy for HTTPS listener. See: https://docs.aws.amazon.com/elasticloadbalancing/latest/application/create-https-listener.html"
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  validation {
    condition     = can(regex("^ELBSecurityPolicy-", var.ssl_policy))
    error_message = "SSL policy must be a valid ELB security policy name."
  }
}

# -----------------------------------------------------------------------------
# Self-Signed Certificate Configuration (Fallback)
# -----------------------------------------------------------------------------
variable "self_signed_cert_common_name" {
  description = "Common name for self-signed certificate (when no external cert provided)"
  type        = string
  default     = "alb.local"
}

variable "self_signed_cert_organization" {
  description = "Organization name for self-signed certificate"
  type        = string
  default     = "Self-Signed"
}

variable "self_signed_cert_validity_hours" {
  description = "Validity period in hours for self-signed certificate"
  type        = number
  default     = 8760 # 1 year

  validation {
    condition     = var.self_signed_cert_validity_hours >= 24 && var.self_signed_cert_validity_hours <= 87600
    error_message = "Self-signed certificate validity must be between 24 hours and 10 years (87600 hours)."
  }
}

# -----------------------------------------------------------------------------
# Access Logs Configuration
# -----------------------------------------------------------------------------
variable "enable_access_logs" {
  description = "Enable ALB access logs to S3"
  type        = bool
  default     = true
}

variable "access_logs_retention_days" {
  description = "Number of days to retain ALB access logs before expiration"
  type        = number
  default     = 90

  validation {
    condition     = var.access_logs_retention_days >= 1 && var.access_logs_retention_days <= 3650
    error_message = "Access logs retention must be between 1 and 3650 days."
  }
}

# -----------------------------------------------------------------------------
# Target Group Configuration
# -----------------------------------------------------------------------------
variable "create_ecs_target_group" {
  description = "Create an IP-based target group for ECS Fargate"
  type        = bool
  default     = true
}

variable "create_ec2_target_group" {
  description = "Create an instance-based target group for EC2"
  type        = bool
  default     = false
}

variable "target_port" {
  description = "Port on which targets receive traffic"
  type        = number
  default     = 9080

  validation {
    condition     = var.target_port >= 1 && var.target_port <= 65535
    error_message = "Target port must be between 1 and 65535."
  }
}

# -----------------------------------------------------------------------------
# Health Check Configuration
# -----------------------------------------------------------------------------
variable "health_check_path" {
  description = "Path for health check endpoint"
  type        = string
  default     = "/health/ready"

  validation {
    condition     = can(regex("^/", var.health_check_path))
    error_message = "Health check path must start with /."
  }
}

variable "health_check_port" {
  description = "Port for health check (use 'traffic-port' for same as target)"
  type        = string
  default     = "traffic-port"
}

variable "health_check_healthy_threshold" {
  description = "Number of consecutive successful health checks before target is healthy"
  type        = number
  default     = 2

  validation {
    condition     = var.health_check_healthy_threshold >= 2 && var.health_check_healthy_threshold <= 10
    error_message = "Healthy threshold must be between 2 and 10."
  }
}

variable "health_check_unhealthy_threshold" {
  description = "Number of consecutive failed health checks before target is unhealthy"
  type        = number
  default     = 3

  validation {
    condition     = var.health_check_unhealthy_threshold >= 2 && var.health_check_unhealthy_threshold <= 10
    error_message = "Unhealthy threshold must be between 2 and 10."
  }
}

variable "health_check_timeout" {
  description = "Amount of time in seconds during which no response means a failed health check"
  type        = number
  default     = 5

  validation {
    condition     = var.health_check_timeout >= 2 && var.health_check_timeout <= 120
    error_message = "Health check timeout must be between 2 and 120 seconds."
  }
}

variable "health_check_interval" {
  description = "Approximate amount of time between health checks of an individual target"
  type        = number
  default     = 30

  validation {
    condition     = var.health_check_interval >= 5 && var.health_check_interval <= 300
    error_message = "Health check interval must be between 5 and 300 seconds."
  }
}

variable "health_check_matcher" {
  description = "HTTP codes to use when checking for a successful response from a target"
  type        = string
  default     = "200"

  validation {
    condition     = can(regex("^[0-9,-]+$", var.health_check_matcher))
    error_message = "Health check matcher must be HTTP status codes (e.g., '200', '200-299', '200,302')."
  }
}

# -----------------------------------------------------------------------------
# Stickiness Configuration
# -----------------------------------------------------------------------------
variable "stickiness_enabled" {
  description = "Enable session stickiness (load balancer generated cookie)"
  type        = bool
  default     = true
}

variable "stickiness_duration" {
  description = "Duration in seconds for session stickiness cookie"
  type        = number
  default     = 86400 # 1 day

  validation {
    condition     = var.stickiness_duration >= 1 && var.stickiness_duration <= 604800
    error_message = "Stickiness duration must be between 1 second and 7 days (604800 seconds)."
  }
}

# -----------------------------------------------------------------------------
# Security Configuration
# -----------------------------------------------------------------------------
variable "block_metrics_endpoint" {
  description = "Block public access to /metrics endpoint (returns 403 Forbidden)"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for key, value in var.tags :
      length(key) <= 128 && length(value) <= 256
    ])
    error_message = "Tag keys must be <= 128 characters and values must be <= 256 characters."
  }
}
