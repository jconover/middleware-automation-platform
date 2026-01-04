# =============================================================================
# Variables with Validation
# =============================================================================

# -----------------------------------------------------------------------------
# General
# -----------------------------------------------------------------------------
variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be a valid format (e.g., us-east-1, eu-west-2)."
  }
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"

  validation {
    condition     = length(var.environment) >= 2 && length(var.environment) <= 20
    error_message = "Environment name must be between 2 and 20 characters."
  }

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "middleware-platform"

  validation {
    condition     = length(var.project_name) >= 3 && length(var.project_name) <= 30
    error_message = "Project name must be between 3 and 30 characters."
  }

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.10.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }

  validation {
    condition     = can(regex("^(10\\.|172\\.(1[6-9]|2[0-9]|3[0-1])\\.|192\\.168\\.)", var.vpc_cidr))
    error_message = "VPC CIDR must use private IP address space (10.0.0.0/8, 172.16.0.0/12, or 192.168.0.0/16)."
  }
}

variable "availability_zones" {
  description = "Number of availability zones to use"
  type        = number
  default     = 2

  validation {
    condition     = var.availability_zones >= 2 && var.availability_zones <= 6
    error_message = "Number of availability zones must be between 2 and 6."
  }
}

variable "high_availability_nat" {
  description = "Deploy NAT Gateway per AZ for high availability (+$32/month per additional NAT)"
  type        = bool
  default     = false
}

variable "allowed_ssh_cidr_blocks" {
  description = "CIDR blocks allowed to SSH to instances (via bastion)"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for cidr in var.allowed_ssh_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All SSH CIDR blocks must be valid IPv4 CIDR blocks."
  }
}

# -----------------------------------------------------------------------------
# EC2 Compute
# -----------------------------------------------------------------------------
variable "liberty_instance_type" {
  description = "EC2 instance type for Liberty servers"
  type        = string
  default     = "t3.small"

  validation {
    condition     = can(regex("^[a-z][0-9][a-z]?\\.(nano|micro|small|medium|large|[0-9]*xlarge|metal)$", var.liberty_instance_type))
    error_message = "Instance type must be a valid EC2 instance type format (e.g., t3.small, m5.large)."
  }
}

variable "liberty_instance_count" {
  description = "Number of Liberty EC2 instances (set to 0 when using ECS only)"
  type        = number
  default     = 2

  validation {
    condition     = var.liberty_instance_count >= 0 && var.liberty_instance_count <= 20
    error_message = "Liberty instance count must be between 0 and 20."
  }
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key for EC2 access"
  type        = string
  default     = "~/.ssh/ansible_ed25519.pub"

  validation {
    condition     = length(var.ssh_public_key_path) > 0
    error_message = "SSH public key path cannot be empty."
  }
}

# -----------------------------------------------------------------------------
# ECS Fargate
# -----------------------------------------------------------------------------
variable "ecs_enabled" {
  description = "Enable ECS Fargate deployment"
  type        = bool
  default     = true
}

variable "enable_blue_green" {
  description = "Enable Blue-Green deployments with CodeDeploy for zero-downtime releases"
  type        = bool
  default     = false
}

variable "container_image_tag" {
  description = "Container image tag to deploy (use semantic versioning for traceability)"
  type        = string
  default     = "1.0.0"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$", var.container_image_tag))
    error_message = "Container image tag must be a valid Docker tag (alphanumeric, dots, hyphens, underscores, max 128 chars)."
  }

  validation {
    condition     = var.container_image_tag != "latest"
    error_message = "Using 'latest' tag is not allowed for production deployments. Use a specific version tag for deterministic deployments and rollbacks."
  }
}

variable "ecs_task_cpu" {
  description = "CPU units for ECS task (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 512

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.ecs_task_cpu)
    error_message = "ECS task CPU must be one of: 256, 512, 1024, 2048, 4096."
  }
}

variable "ecs_task_memory" {
  description = "Memory for ECS task in MB (must be compatible with CPU)"
  type        = number
  default     = 1024

  validation {
    condition     = var.ecs_task_memory >= 512 && var.ecs_task_memory <= 30720
    error_message = "ECS task memory must be between 512 MB and 30720 MB."
  }
}

variable "ecs_desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 2

  validation {
    condition     = var.ecs_desired_count >= 0 && var.ecs_desired_count <= 100
    error_message = "ECS desired count must be between 0 and 100."
  }
}

# -----------------------------------------------------------------------------
# ECS Auto Scaling
# -----------------------------------------------------------------------------
variable "ecs_min_capacity" {
  description = "Minimum number of ECS tasks"
  type        = number
  default     = 2

  validation {
    condition     = var.ecs_min_capacity >= 0 && var.ecs_min_capacity <= 100
    error_message = "ECS minimum capacity must be between 0 and 100."
  }
}

variable "fargate_spot_weight" {
  description = "Weight for FARGATE_SPOT capacity provider (0-80). Tasks above baseline use this ratio of Spot vs On-Demand. Default 70 means 70% Spot, 30% On-Demand for scaling tasks."
  type        = number
  default     = 70

  validation {
    condition     = var.fargate_spot_weight >= 0 && var.fargate_spot_weight <= 80
    error_message = "Fargate Spot weight must be between 0 and 80. Values above 80 risk insufficient on-demand capacity during Spot interruptions."
  }
}

variable "ecs_max_capacity" {
  description = "Maximum number of ECS tasks"
  type        = number
  default     = 6

  validation {
    condition     = var.ecs_max_capacity >= 1 && var.ecs_max_capacity <= 100
    error_message = "ECS maximum capacity must be between 1 and 100."
  }
}

variable "ecs_cpu_target" {
  description = "Target CPU utilization percentage for scaling"
  type        = number
  default     = 70

  validation {
    condition     = var.ecs_cpu_target >= 10 && var.ecs_cpu_target <= 90
    error_message = "ECS CPU target must be between 10 and 90 percent."
  }
}

variable "ecs_memory_target" {
  description = "Target memory utilization percentage for scaling"
  type        = number
  default     = 80

  validation {
    condition     = var.ecs_memory_target >= 10 && var.ecs_memory_target <= 90
    error_message = "ECS memory target must be between 10 and 90 percent."
  }
}

variable "ecs_requests_per_target" {
  description = "Target requests per task for scaling"
  type        = number
  default     = 1000

  validation {
    condition     = var.ecs_requests_per_target >= 100 && var.ecs_requests_per_target <= 100000
    error_message = "ECS requests per target must be between 100 and 100000."
  }
}

# -----------------------------------------------------------------------------
# Monitoring Server
# -----------------------------------------------------------------------------
variable "create_monitoring_server" {
  description = "Whether to create the dedicated monitoring server"
  type        = bool
  default     = true
}

variable "monitoring_instance_type" {
  description = "EC2 instance type for monitoring server"
  type        = string
  default     = "t3.small"

  validation {
    condition     = can(regex("^[a-z][0-9][a-z]?\\.(nano|micro|small|medium|large|[0-9]*xlarge|metal)$", var.monitoring_instance_type))
    error_message = "Monitoring instance type must be a valid EC2 instance type format."
  }
}

variable "alertmanager_slack_secret_arn" {
  description = <<-EOT
    ARN of AWS Secrets Manager secret containing Slack webhook URL for AlertManager.
    The secret should contain JSON: {"slack_webhook_url": "https://hooks.slack.com/services/..."}
    If empty, AlertManager will be installed but notifications will be disabled.
    Create the secret with:
      aws secretsmanager create-secret --name mw-prod/monitoring/alertmanager-slack \
        --secret-string '{"slack_webhook_url":"https://hooks.slack.com/services/T.../B.../xxx"}'
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.alertmanager_slack_secret_arn == "" || can(regex("^arn:aws:secretsmanager:", var.alertmanager_slack_secret_arn))
    error_message = "AlertManager Slack secret ARN must be a valid AWS Secrets Manager ARN or empty string."
  }
}

# -----------------------------------------------------------------------------
# Management Server
# -----------------------------------------------------------------------------
variable "create_management_server" {
  description = "Whether to create the AWX/Jenkins management server"
  type        = bool
  default     = true
}

variable "management_instance_type" {
  description = "EC2 instance type for management server (AWX needs 4GB+ RAM)"
  type        = string
  default     = "t3.medium"

  validation {
    condition     = can(regex("^[a-z][0-9][a-z]?\\.(small|medium|large|[0-9]*xlarge|metal)$", var.management_instance_type))
    error_message = "Management instance type must be at least small size (AWX requires 4GB+ RAM)."
  }
}

variable "management_allowed_cidrs" {
  description = <<-EOT
    CIDR blocks allowed to access management server (SSH, AWX, Grafana, Prometheus).
    REQUIRED - You must explicitly set this for security reasons.

    Examples:
      - Single IP:     ["203.0.113.50/32"]
      - Office range:  ["203.0.113.0/24"]
      - VPN + Office:  ["10.0.0.0/8", "203.0.113.0/24"]

    Find your public IP: curl -s ifconfig.me
  EOT
  type        = list(string)
  # No default - force explicit configuration for security

  validation {
    condition = alltrue([
      for cidr in var.management_allowed_cidrs : can(cidrhost(cidr, 0))
    ])
    error_message = "All management allowed CIDR blocks must be valid IPv4 CIDR blocks."
  }

  validation {
    condition     = length(var.management_allowed_cidrs) > 0
    error_message = "management_allowed_cidrs must contain at least one CIDR block. Use 'curl -s ifconfig.me' to find your public IP."
  }

  validation {
    condition     = !contains(var.management_allowed_cidrs, "0.0.0.0/0")
    error_message = "management_allowed_cidrs cannot include 0.0.0.0/0 - this would expose management interfaces to the entire internet. Use specific CIDR blocks for your office, VPN, or IP address."
  }
}

# -----------------------------------------------------------------------------
# Database
# -----------------------------------------------------------------------------
variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"

  validation {
    condition     = can(regex("^db\\.[a-z][0-9][a-z]?\\.(micro|small|medium|large|[0-9]*xlarge)$", var.db_instance_class))
    error_message = "Database instance class must be a valid RDS format (e.g., db.t3.micro)."
  }
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "appdb"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.db_name))
    error_message = "Database name must start with a letter and contain only alphanumeric characters and underscores (max 63 characters)."
  }
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "appuser"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,15}$", var.db_username))
    error_message = "Database username must start with a letter and contain only alphanumeric characters and underscores (max 16 characters)."
  }

  validation {
    condition     = !contains(["admin", "root", "postgres", "mysql", "rdsadmin"], lower(var.db_username))
    error_message = "Database username cannot be a reserved word (admin, root, postgres, mysql, rdsadmin)."
  }
}

variable "db_allocated_storage" {
  description = "Allocated storage for RDS in GB"
  type        = number
  default     = 20

  validation {
    condition     = var.db_allocated_storage >= 20 && var.db_allocated_storage <= 65536
    error_message = "Database allocated storage must be between 20 GB and 65536 GB."
  }
}

variable "db_backup_retention_period" {
  description = "Number of days to retain RDS backups"
  type        = number
  default     = 7

  validation {
    condition     = var.db_backup_retention_period >= 0 && var.db_backup_retention_period <= 35
    error_message = "Database backup retention period must be between 0 and 35 days."
  }
}

# -----------------------------------------------------------------------------
# RDS Proxy
# -----------------------------------------------------------------------------
variable "enable_rds_proxy" {
  description = <<-EOT
    Enable RDS Proxy for connection pooling and IAM authentication.
    Benefits:
    - Connection pooling reduces database load from Lambda/Fargate
    - IAM authentication eliminates password management
    - Automatic failover handling improves availability
    - Connection multiplexing improves scalability

    Cost: ~$0.015 per proxy hour (~$11/month) + $0.015 per million requests
  EOT
  type        = bool
  default     = false
}

variable "rds_proxy_idle_timeout" {
  description = <<-EOT
    Time in seconds that a connection can remain idle before RDS Proxy closes it.
    Range: 1-28800 seconds (1 second to 8 hours).
    Lower values free up connections faster; higher values reduce reconnection overhead.
  EOT
  type        = number
  default     = 1800

  validation {
    condition     = var.rds_proxy_idle_timeout >= 1 && var.rds_proxy_idle_timeout <= 28800
    error_message = "RDS Proxy idle timeout must be between 1 and 28800 seconds."
  }
}

variable "rds_proxy_max_connections_percent" {
  description = <<-EOT
    Maximum percentage of available database connections that RDS Proxy can use.
    Range: 1-100. Default: 100 (use all available connections).
    Lower values reserve connections for other clients (e.g., admin access).
  EOT
  type        = number
  default     = 100

  validation {
    condition     = var.rds_proxy_max_connections_percent >= 1 && var.rds_proxy_max_connections_percent <= 100
    error_message = "RDS Proxy max connections percent must be between 1 and 100."
  }
}

variable "rds_proxy_require_iam" {
  description = <<-EOT
    Require IAM authentication for RDS Proxy connections.
    When enabled, applications must use IAM credentials instead of passwords.
    Provides stronger security but requires application code changes.
  EOT
  type        = bool
  default     = false
}

variable "enable_rds_proxy_read_endpoint" {
  description = <<-EOT
    Create a read-only endpoint for RDS Proxy.
    Useful for read scaling when combined with RDS read replicas.
    Note: Requires RDS read replica to be effective.
  EOT
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Cache
# -----------------------------------------------------------------------------
variable "cache_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.micro"

  validation {
    condition     = can(regex("^cache\\.[a-z][0-9][a-z]?\\.(micro|small|medium|large|[0-9]*xlarge)$", var.cache_node_type))
    error_message = "Cache node type must be a valid ElastiCache format (e.g., cache.t3.micro)."
  }
}

variable "cache_multi_az" {
  description = "Enable Multi-AZ for ElastiCache Redis (adds replica in second AZ for automatic failover)"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# SSL/TLS
# -----------------------------------------------------------------------------
variable "domain_name" {
  description = "Domain name for ACM certificate (e.g., app.example.com)"
  type        = string
  default     = ""

  validation {
    condition = (
      var.domain_name == "" ||
      can(regex("^([a-z0-9]+(-[a-z0-9]+)*\\.)+[a-z]{2,}$", var.domain_name))
    )
    error_message = "Domain name must be empty or a valid domain format (e.g., app.example.com)."
  }
}

variable "create_certificate" {
  description = "Whether to create an ACM certificate"
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "Existing ACM certificate ARN (if not creating new)"
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

# -----------------------------------------------------------------------------
# CloudTrail
# -----------------------------------------------------------------------------
variable "enable_cloudtrail" {
  description = "Enable AWS CloudTrail for audit logging and compliance"
  type        = bool
  default     = true
}

variable "cloudtrail_log_retention_days" {
  description = "Number of days to retain CloudTrail logs in CloudWatch before transitioning to Glacier"
  type        = number
  default     = 90

  validation {
    condition     = var.cloudtrail_log_retention_days >= 30 && var.cloudtrail_log_retention_days <= 365
    error_message = "CloudTrail log retention must be between 30 and 365 days."
  }
}

# -----------------------------------------------------------------------------
# Security Services (GuardDuty / Security Hub)
# -----------------------------------------------------------------------------
variable "enable_guardduty" {
  description = <<-EOT
    Enable AWS GuardDuty and Security Hub for threat detection and security posture management.
    This creates:
    - GuardDuty Detector with S3 logs and EBS malware protection
    - Security Hub with CIS AWS Foundations and AWS Foundational Security benchmarks
    - EventBridge rules for alerting on high-severity findings
  EOT
  type        = bool
  default     = true
}

variable "security_alert_email" {
  description = <<-EOT
    Email address for security alerts from GuardDuty and Security Hub.
    Leave empty to disable email notifications (GuardDuty/Security Hub will still be enabled).
    The email will receive notifications for:
    - GuardDuty findings with severity >= 7 (High/Critical)
    - Security Hub findings with CRITICAL or HIGH severity

    IMPORTANT: The subscriber must confirm the email subscription after deployment.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.security_alert_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.security_alert_email))
    error_message = "security_alert_email must be empty or a valid email address format."
  }
}

# -----------------------------------------------------------------------------
# WAF (Web Application Firewall)
# -----------------------------------------------------------------------------
variable "enable_waf" {
  description = <<-EOT
    Enable AWS WAFv2 Web Application Firewall for the ALB.
    Provides protection against:
    - OWASP Top 10 web exploits (XSS, path traversal, etc.)
    - SQL injection attacks
    - Known bad inputs and malicious patterns
    - DDoS via rate limiting
  EOT
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = <<-EOT
    Maximum requests per 5-minute period per IP address before rate limiting kicks in.
    Requests exceeding this limit are blocked. Default: 2000 requests/5 minutes.

    Guidelines:
    - Low traffic sites: 1000-2000
    - Medium traffic: 2000-5000
    - High traffic/API: 5000-10000
  EOT
  type        = number
  default     = 2000

  validation {
    condition     = var.waf_rate_limit >= 100 && var.waf_rate_limit <= 20000000
    error_message = "WAF rate limit must be between 100 and 20,000,000 requests per 5-minute period."
  }
}

variable "waf_enable_logging" {
  description = <<-EOT
    Enable WAF logging to CloudWatch Logs.
    When enabled, creates a log group with 30-day retention for:
    - Blocked requests
    - Matched rules
    - Request details (with authorization and cookie headers redacted)

    Note: WAF logging incurs additional CloudWatch Logs costs.
  EOT
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Distributed Tracing (OpenTelemetry)
# -----------------------------------------------------------------------------
variable "otel_collector_endpoint" {
  description = <<-EOT
    OpenTelemetry Collector endpoint for trace export when not using X-Ray.
    This is used when enable_xray = false.

    For self-hosted OTEL Collector, use the internal endpoint:
      http://otel-collector.internal:4317

    For AWS Distro for OpenTelemetry (ADOT), leave empty and set enable_xray = true.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.otel_collector_endpoint == "" || can(regex("^https?://", var.otel_collector_endpoint))
    error_message = "OTEL collector endpoint must be empty or a valid HTTP/HTTPS URL."
  }
}

# -----------------------------------------------------------------------------
# Tagging
# -----------------------------------------------------------------------------
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for key, value in var.additional_tags :
      length(key) <= 128 && length(value) <= 256
    ])
    error_message = "Tag keys must be <= 128 characters and values must be <= 256 characters."
  }
}
