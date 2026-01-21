# =============================================================================
# Monitoring Module - Variables
# =============================================================================

# -----------------------------------------------------------------------------
# Required Variables
# -----------------------------------------------------------------------------
variable "name_prefix" {
  description = "Prefix for resource names (e.g., 'mw-prod')"
  type        = string

  validation {
    condition     = length(var.name_prefix) >= 2 && length(var.name_prefix) <= 30
    error_message = "Name prefix must be between 2 and 30 characters."
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

variable "vpc_id" {
  description = "VPC ID where the monitoring server will be deployed"
  type        = string

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "VPC ID must start with 'vpc-'."
  }
}

variable "subnet_id" {
  description = "Subnet ID for the monitoring server (typically a public subnet)"
  type        = string

  validation {
    condition     = can(regex("^subnet-", var.subnet_id))
    error_message = "Subnet ID must start with 'subnet-'."
  }
}

variable "ami_id" {
  description = "AMI ID for the monitoring server (Ubuntu recommended)"
  type        = string

  validation {
    condition     = can(regex("^ami-", var.ami_id))
    error_message = "AMI ID must start with 'ami-'."
  }
}

variable "ssh_key_name" {
  description = "Name of the SSH key pair for EC2 access"
  type        = string

  validation {
    condition     = length(var.ssh_key_name) > 0
    error_message = "SSH key name cannot be empty."
  }
}

# -----------------------------------------------------------------------------
# Security Group Configuration
# -----------------------------------------------------------------------------
variable "create_security_group" {
  description = "Whether to create a security group for the monitoring server"
  type        = bool
  default     = true
}

variable "security_group_id" {
  description = "Existing security group ID (required if create_security_group is false)"
  type        = string
  default     = ""

  validation {
    condition     = var.security_group_id == "" || can(regex("^sg-", var.security_group_id))
    error_message = "Security group ID must be empty or start with 'sg-'."
  }
}

variable "allowed_cidrs" {
  description = <<-EOT
    CIDR blocks allowed to access monitoring server (SSH, Prometheus, Grafana, AlertManager).
    Required if create_security_group is true.

    Examples:
      - Single IP:     ["203.0.113.50/32"]
      - Office range:  ["203.0.113.0/24"]
      - VPN + Office:  ["10.0.0.0/8", "203.0.113.0/24"]

    Find your public IP: curl -s ifconfig.me
  EOT
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for cidr in var.allowed_cidrs : can(cidrhost(cidr, 0))
    ])
    error_message = "All allowed CIDR blocks must be valid IPv4 CIDR blocks."
  }

  validation {
    condition     = !contains(var.allowed_cidrs, "0.0.0.0/0")
    error_message = "allowed_cidrs cannot include 0.0.0.0/0 - this would expose management interfaces to the entire internet."
  }
}

variable "vpc_cidr" {
  description = "VPC CIDR block (for egress rules to scrape metrics within VPC)"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "target_security_group_id" {
  description = "Security group ID of scrape targets (Liberty instances). If provided, ingress rules will be added to allow monitoring."
  type        = string
  default     = ""

  validation {
    condition     = var.target_security_group_id == "" || can(regex("^sg-", var.target_security_group_id))
    error_message = "Target security group ID must be empty or start with 'sg-'."
  }
}

variable "enable_target_monitoring_rules" {
  description = "Whether to create security group rules for monitoring targets. Use this instead of checking target_security_group_id to avoid plan-time issues."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Instance Configuration
# -----------------------------------------------------------------------------
variable "instance_type" {
  description = "EC2 instance type for monitoring server"
  type        = string
  default     = "t3.small"

  validation {
    condition     = can(regex("^[a-z][0-9][a-z]?\\.(nano|micro|small|medium|large|[0-9]*xlarge|metal)$", var.instance_type))
    error_message = "Instance type must be a valid EC2 instance type format (e.g., t3.small, m5.large)."
  }
}

variable "root_volume_size" {
  description = "Root volume size in GB (should accommodate metrics storage)"
  type        = number
  default     = 30

  validation {
    condition     = var.root_volume_size >= 20 && var.root_volume_size <= 500
    error_message = "Root volume size must be between 20 and 500 GB."
  }
}

variable "create_elastic_ip" {
  description = "Whether to create and associate an Elastic IP for stable public access"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# ECS Service Discovery
# -----------------------------------------------------------------------------
variable "ecs_cluster_name" {
  description = "Name of the ECS cluster for service discovery. If empty, ECS discovery is disabled."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Prometheus Configuration
# -----------------------------------------------------------------------------
variable "prometheus_retention_days" {
  description = "Number of days to retain Prometheus metrics data"
  type        = number
  default     = 15

  validation {
    condition     = var.prometheus_retention_days >= 1 && var.prometheus_retention_days <= 365
    error_message = "Prometheus retention must be between 1 and 365 days."
  }
}

variable "liberty_targets" {
  description = <<-EOT
    List of static Liberty targets for Prometheus scraping (for EC2 deployments).
    Format: ["ip1:port", "ip2:port"] or ["ip1", "ip2"] (port 9080 assumed).
    Leave empty if only using ECS service discovery.

    Examples:
      - With ports: ["10.0.1.10:9080", "10.0.1.11:9080"]
      - Without ports: ["10.0.1.10", "10.0.1.11"]
  EOT
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Grafana Configuration
# -----------------------------------------------------------------------------
variable "grafana_version" {
  description = "Grafana version to install (uses apt repository, so 'latest' uses repo default)"
  type        = string
  default     = "latest"
}

# -----------------------------------------------------------------------------
# AlertManager Configuration
# -----------------------------------------------------------------------------
variable "alertmanager_slack_secret_arn" {
  description = <<-EOT
    ARN of AWS Secrets Manager secret containing Slack webhook URL for AlertManager.
    The secret should contain JSON: {"slack_webhook_url": "https://hooks.slack.com/services/..."}
    If empty, AlertManager will be installed but Slack notifications will be disabled.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.alertmanager_slack_secret_arn == "" || can(regex("^arn:aws:secretsmanager:", var.alertmanager_slack_secret_arn))
    error_message = "AlertManager Slack secret ARN must be a valid AWS Secrets Manager ARN or empty string."
  }
}

variable "alertmanager_config" {
  description = <<-EOT
    AlertManager configuration options.
    - slack_channel: Default Slack channel for alerts (e.g., "#middleware-alerts")
    - critical_channel: Slack channel for critical alerts (e.g., "#middleware-critical")
    - email_to: Email address for alert notifications (optional)
    - email_from: Email sender address (required if email_to is set)
    - smtp_host: SMTP server for email notifications (required if email_to is set)
  EOT
  type = object({
    slack_channel    = optional(string, "#middleware-alerts")
    critical_channel = optional(string, "#middleware-critical")
    email_to         = optional(string, "")
    email_from       = optional(string, "")
    smtp_host        = optional(string, "")
  })
  default = {
    slack_channel    = "#middleware-alerts"
    critical_channel = "#middleware-critical"
    email_to         = ""
    email_from       = ""
    smtp_host        = ""
  }
}

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "Log retention must be a valid CloudWatch retention period."
  }
}

# -----------------------------------------------------------------------------
# Tagging
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
