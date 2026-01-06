# =============================================================================
# Input Variables
# =============================================================================
# All configurable parameters for the unified AWS environment.
# Variables are grouped by category for clarity and maintainability.
# Use .tfvars files to override defaults for different environments.
# =============================================================================

# -----------------------------------------------------------------------------
# General Configuration
# -----------------------------------------------------------------------------

variable "project" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "mw"

  validation {
    condition     = length(var.project) >= 2 && length(var.project) <= 10
    error_message = "Project name must be between 2 and 10 characters."
  }

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, stage, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "stage", "staging", "prod", "production"], var.environment)
    error_message = "Environment must be one of: dev, stage, staging, prod, production."
  }
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be a valid format (e.g., us-east-1, eu-west-2)."
  }
}

# -----------------------------------------------------------------------------
# Networking Configuration
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
  description = "Number of availability zones to use (minimum 2 for high availability)"
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

# -----------------------------------------------------------------------------
# EC2 Compute Configuration
# -----------------------------------------------------------------------------

variable "liberty_instance_count" {
  description = "Number of Liberty EC2 instances (set to 0 when using ECS only)"
  type        = number
  default     = 0

  validation {
    condition     = var.liberty_instance_count >= 0 && var.liberty_instance_count <= 20
    error_message = "Liberty instance count must be between 0 and 20."
  }
}

variable "liberty_instance_type" {
  description = "EC2 instance type for Liberty servers"
  type        = string
  default     = "t3.small"

  validation {
    condition     = can(regex("^[a-z][0-9][a-z]?\\.(nano|micro|small|medium|large|[0-9]*xlarge|metal)$", var.liberty_instance_type))
    error_message = "Instance type must be a valid EC2 instance type format (e.g., t3.small, m5.large)."
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
# ECS Fargate Configuration
# -----------------------------------------------------------------------------

variable "ecs_enabled" {
  description = "Enable ECS Fargate deployment"
  type        = bool
  default     = true
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

variable "ecs_min_capacity" {
  description = "Minimum number of ECS tasks for auto-scaling"
  type        = number
  default     = 2

  validation {
    condition     = var.ecs_min_capacity >= 1 && var.ecs_min_capacity <= 100
    error_message = "ECS minimum capacity must be between 1 and 100."
  }
}

variable "ecs_max_capacity" {
  description = "Maximum number of ECS tasks for auto-scaling"
  type        = number
  default     = 6

  validation {
    condition     = var.ecs_max_capacity >= 1 && var.ecs_max_capacity <= 100
    error_message = "ECS maximum capacity must be between 1 and 100."
  }
}

variable "ecs_cpu_target" {
  description = "Target CPU utilization percentage for ECS auto-scaling"
  type        = number
  default     = 70

  validation {
    condition     = var.ecs_cpu_target >= 10 && var.ecs_cpu_target <= 90
    error_message = "ECS CPU target must be between 10 and 90 percent."
  }
}

variable "ecs_memory_target" {
  description = "Target memory utilization percentage for ECS auto-scaling"
  type        = number
  default     = 80

  validation {
    condition     = var.ecs_memory_target >= 10 && var.ecs_memory_target <= 90
    error_message = "ECS memory target must be between 10 and 90 percent."
  }
}

variable "ecs_requests_per_target" {
  description = "Target requests per task for ECS auto-scaling"
  type        = number
  default     = 1000

  validation {
    condition     = var.ecs_requests_per_target >= 100 && var.ecs_requests_per_target <= 100000
    error_message = "ECS requests per target must be between 100 and 100000."
  }
}

variable "fargate_spot_weight" {
  description = "Weight for FARGATE_SPOT capacity provider (0-80). Higher values use more Spot for cost savings."
  type        = number
  default     = 70

  validation {
    condition     = var.fargate_spot_weight >= 0 && var.fargate_spot_weight <= 80
    error_message = "Fargate Spot weight must be between 0 and 80."
  }
}

# -----------------------------------------------------------------------------
# Database Configuration
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

variable "db_multi_az" {
  description = "Enable Multi-AZ deployment for RDS high availability"
  type        = bool
  default     = true
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

variable "enable_rds_proxy" {
  description = "Enable RDS Proxy for connection pooling and IAM authentication (~$11/month)"
  type        = bool
  default     = false
}

variable "rds_proxy_idle_timeout" {
  description = "Seconds before RDS Proxy closes idle connections (1-28800)"
  type        = number
  default     = 1800

  validation {
    condition     = var.rds_proxy_idle_timeout >= 1 && var.rds_proxy_idle_timeout <= 28800
    error_message = "RDS Proxy idle timeout must be between 1 and 28800 seconds."
  }
}

variable "rds_proxy_max_connections_percent" {
  description = "Maximum percentage of database connections RDS Proxy can use (1-100)"
  type        = number
  default     = 100

  validation {
    condition     = var.rds_proxy_max_connections_percent >= 1 && var.rds_proxy_max_connections_percent <= 100
    error_message = "RDS Proxy max connections percent must be between 1 and 100."
  }
}

# -----------------------------------------------------------------------------
# Cache Configuration
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
  description = "Enable Multi-AZ for ElastiCache Redis (adds replica for automatic failover)"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Load Balancer Configuration
# -----------------------------------------------------------------------------

variable "enable_https" {
  description = "Enable HTTPS listener on ALB (creates self-signed cert if certificate_arn not provided)"
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "Existing ACM certificate ARN for HTTPS (leave empty to create self-signed)"
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
# Monitoring Configuration
# -----------------------------------------------------------------------------

variable "create_monitoring_server" {
  description = "Create dedicated Prometheus/Grafana monitoring server"
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
  description = "ARN of Secrets Manager secret containing Slack webhook URL for AlertManager"
  type        = string
  default     = ""

  validation {
    condition     = var.alertmanager_slack_secret_arn == "" || can(regex("^arn:aws:secretsmanager:", var.alertmanager_slack_secret_arn))
    error_message = "AlertManager Slack secret ARN must be a valid AWS Secrets Manager ARN or empty string."
  }
}

# -----------------------------------------------------------------------------
# Management Server Configuration
# -----------------------------------------------------------------------------

variable "create_management_server" {
  description = "Create AWX/Jenkins management server for CI/CD and automation"
  type        = bool
  default     = false
}

variable "management_instance_type" {
  description = "EC2 instance type for management server (AWX needs 4GB+ RAM)"
  type        = string
  default     = "t3.medium"

  validation {
    condition     = can(regex("^[a-z][0-9][a-z]?\\.(small|medium|large|[0-9]*xlarge|metal)$", var.management_instance_type))
    error_message = "Management instance type must be a valid EC2 instance type (e.g., t3.medium, m5.large). Note: AWX requires at least 4GB RAM, so t3.small and smaller are not recommended."
  }
}

# -----------------------------------------------------------------------------
# Security Compliance Configuration
# -----------------------------------------------------------------------------

variable "enable_cloudtrail" {
  description = "Enable AWS CloudTrail for audit logging and compliance"
  type        = bool
  default     = true
}

variable "cloudtrail_log_retention_days" {
  description = "Number of days to retain CloudTrail logs in CloudWatch"
  type        = number
  default     = 90

  validation {
    condition     = var.cloudtrail_log_retention_days >= 30 && var.cloudtrail_log_retention_days <= 365
    error_message = "CloudTrail log retention must be between 30 and 365 days."
  }
}

variable "enable_guardduty" {
  description = "Enable AWS GuardDuty and Security Hub for threat detection"
  type        = bool
  default     = true
}

variable "enable_waf" {
  description = "Enable AWS WAFv2 Web Application Firewall for the ALB"
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "Maximum requests per 5-minute period per IP before rate limiting"
  type        = number
  default     = 2000

  validation {
    condition     = var.waf_rate_limit >= 100 && var.waf_rate_limit <= 20000000
    error_message = "WAF rate limit must be between 100 and 20,000,000 requests per 5-minute period."
  }
}

variable "waf_enable_logging" {
  description = "Enable WAF logging to CloudWatch Logs (additional cost)"
  type        = bool
  default     = false
}

variable "security_alert_email" {
  description = "Email address for security alerts from GuardDuty and Security Hub"
  type        = string
  default     = ""

  validation {
    condition     = var.security_alert_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.security_alert_email))
    error_message = "security_alert_email must be empty or a valid email address format."
  }
}

# -----------------------------------------------------------------------------
# Deployment Configuration
# -----------------------------------------------------------------------------

variable "enable_blue_green" {
  description = "Enable Blue-Green deployments with CodeDeploy for zero-downtime releases"
  type        = bool
  default     = false
}

variable "container_image_tag" {
  description = "Container image tag to deploy (use semantic versioning, 'latest' not allowed)"
  type        = string
  default     = "1.0.0"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$", var.container_image_tag))
    error_message = "Container image tag must be a valid Docker tag (alphanumeric, dots, hyphens, underscores, max 128 chars)."
  }

  validation {
    condition     = var.container_image_tag != "latest"
    error_message = "Using 'latest' tag is not allowed. Use a specific version tag for deterministic deployments and rollbacks."
  }
}

# -----------------------------------------------------------------------------
# X-Ray Distributed Tracing
# -----------------------------------------------------------------------------

variable "enable_xray" {
  description = "Enable AWS X-Ray for distributed tracing"
  type        = bool
  default     = false
}

variable "xray_sampling_rate" {
  description = "Default sampling rate for X-Ray traces (0.0 to 1.0, where 0.1 = 10%)"
  type        = number
  default     = 0.1

  validation {
    condition     = var.xray_sampling_rate >= 0 && var.xray_sampling_rate <= 1
    error_message = "X-Ray sampling rate must be between 0.0 and 1.0."
  }
}

# -----------------------------------------------------------------------------
# SLO/SLI Alerting Configuration
# -----------------------------------------------------------------------------

variable "enable_slo_alarms" {
  description = "Enable SLO/SLI CloudWatch alarms for availability, latency, and error rate monitoring"
  type        = bool
  default     = false
}

variable "slo_alert_email" {
  description = "Email address for SLO alerts (uses security_alert_email if not set)"
  type        = string
  default     = ""

  validation {
    condition     = var.slo_alert_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.slo_alert_email))
    error_message = "slo_alert_email must be empty or a valid email address format."
  }
}

variable "slo_availability_target" {
  description = "Availability SLO target as percentage (e.g., 99.9 for 99.9% availability)"
  type        = number
  default     = 99.9

  validation {
    condition     = var.slo_availability_target >= 90 && var.slo_availability_target <= 99.999
    error_message = "SLO availability target must be between 90 and 99.999 percent."
  }
}

variable "slo_latency_threshold_ms" {
  description = "p99 latency SLO threshold in milliseconds"
  type        = number
  default     = 500

  validation {
    condition     = var.slo_latency_threshold_ms >= 50 && var.slo_latency_threshold_ms <= 10000
    error_message = "SLO latency threshold must be between 50 and 10000 milliseconds."
  }
}

# -----------------------------------------------------------------------------
# Disaster Recovery Configuration
# -----------------------------------------------------------------------------

variable "enable_s3_replication" {
  description = "Enable S3 cross-region replication for disaster recovery of ALB and CloudTrail logs"
  type        = bool
  default     = false
}

variable "dr_region" {
  description = "AWS region for disaster recovery (S3 cross-region replication destination)"
  type        = string
  default     = "us-west-2"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.dr_region))
    error_message = "DR region must be a valid AWS region format (e.g., us-west-2, eu-west-1)."
  }
}

# -----------------------------------------------------------------------------
# Route53 DNS Failover Configuration
# -----------------------------------------------------------------------------

variable "domain_name" {
  description = "Domain name for Route53 DNS records (e.g., app.example.com)"
  type        = string
  default     = ""

  validation {
    condition = (
      var.domain_name == "" ||
      can(regex("^([a-z0-9]+(-[a-z0-9]+)*\\.)+[a-z]{2,}$", var.domain_name))
    )
    error_message = "Domain name must be empty or a valid DNS hostname (e.g., app.example.com)."
  }
}

variable "enable_route53_failover" {
  description = <<-EOT
    Enable Route53 health checks and DNS failover routing.
    When enabled, creates:
    - Route53 health check monitoring ALB /health/ready endpoint
    - Primary DNS record pointing to ALB
    - Secondary DNS record for failover (S3 maintenance page or DR region)
    - CloudWatch alarms for health check failures

    Prerequisites:
    - domain_name must be set
    - Route53 hosted zone must exist for the domain
  EOT
  type        = bool
  default     = false
}

variable "route53_zone_name" {
  description = <<-EOT
    Route53 hosted zone name (e.g., example.com).
    If empty, uses the domain_name variable.
    Useful when domain_name is a subdomain (e.g., app.example.com) but the
    hosted zone is the parent domain (example.com).
  EOT
  type        = string
  default     = ""

  validation {
    condition = (
      var.route53_zone_name == "" ||
      can(regex("^([a-z0-9]+(-[a-z0-9]+)*\\.)+[a-z]{2,}$", var.route53_zone_name))
    )
    error_message = "Route53 zone name must be empty or a valid DNS hostname."
  }
}

variable "route53_health_check_interval" {
  description = <<-EOT
    Interval in seconds between Route53 health checks.
    Valid values: 10 or 30 seconds.
    10-second intervals cost more but detect failures faster.
  EOT
  type        = number
  default     = 30

  validation {
    condition     = contains([10, 30], var.route53_health_check_interval)
    error_message = "Route53 health check interval must be either 10 or 30 seconds."
  }
}

variable "route53_health_check_failure_threshold" {
  description = <<-EOT
    Number of consecutive health check failures before Route53 considers the endpoint unhealthy.
    Range: 1-10. Lower values trigger failover faster but may cause false positives.
    Recommended: 3 for production (allows for transient issues).
  EOT
  type        = number
  default     = 3

  validation {
    condition     = var.route53_health_check_failure_threshold >= 1 && var.route53_health_check_failure_threshold <= 10
    error_message = "Route53 health check failure threshold must be between 1 and 10."
  }
}

variable "route53_health_check_regions" {
  description = <<-EOT
    AWS regions from which Route53 performs health checks.
    Health checks are performed from multiple regions for redundancy.
    At least 3 regions are recommended for reliable health check results.

    Available regions:
    - us-east-1, us-west-1, us-west-2
    - eu-west-1, ap-southeast-1, ap-northeast-1
    - sa-east-1
  EOT
  type        = list(string)
  default     = ["us-east-1", "us-west-1", "eu-west-1"]

  validation {
    condition     = length(var.route53_health_check_regions) >= 3
    error_message = "At least 3 health check regions are required for reliable results."
  }
}

variable "route53_latency_threshold_ms" {
  description = <<-EOT
    Threshold in milliseconds for Route53 latency alarm.
    Triggers a warning when average TTFB exceeds this value.
    Default: 500ms (matches the p95 latency SLO).
  EOT
  type        = number
  default     = 500

  validation {
    condition     = var.route53_latency_threshold_ms >= 100 && var.route53_latency_threshold_ms <= 10000
    error_message = "Route53 latency threshold must be between 100 and 10000 milliseconds."
  }
}

variable "enable_maintenance_page" {
  description = <<-EOT
    Create an S3-hosted maintenance page as the failover target.
    When enabled, traffic is routed to a static maintenance page when the
    primary ALB is unhealthy.

    When disabled, you must provide dr_alb_dns_name and dr_alb_zone_id for
    a DR region ALB as the failover target.
  EOT
  type        = bool
  default     = true
}

variable "create_www_record" {
  description = <<-EOT
    Create a www subdomain CNAME record pointing to the apex domain.
    When enabled, www.example.com will redirect to example.com.
  EOT
  type        = bool
  default     = true
}

variable "dr_alb_dns_name" {
  description = <<-EOT
    DNS name of the DR region ALB for failover.
    Only used when enable_maintenance_page = false.
    Example: my-dr-alb-123456.us-west-2.elb.amazonaws.com
  EOT
  type        = string
  default     = ""

  validation {
    condition = (
      var.dr_alb_dns_name == "" ||
      can(regex("^[a-z0-9-]+\\.[a-z0-9-]+\\.elb\\.amazonaws\\.com$", var.dr_alb_dns_name))
    )
    error_message = "DR ALB DNS name must be empty or a valid ALB DNS name."
  }
}

variable "dr_alb_zone_id" {
  description = <<-EOT
    Route53 hosted zone ID of the DR region ALB.
    Only used when enable_maintenance_page = false.
    Find this value from the ALB in the DR region.
  EOT
  type        = string
  default     = ""

  validation {
    condition = (
      var.dr_alb_zone_id == "" ||
      can(regex("^Z[A-Z0-9]+$", var.dr_alb_zone_id))
    )
    error_message = "DR ALB zone ID must be empty or a valid Route53 zone ID (starts with Z)."
  }
}

# -----------------------------------------------------------------------------
# Access Control Configuration
# -----------------------------------------------------------------------------

variable "management_allowed_cidrs" {
  description = <<-EOT
    CIDR blocks allowed to access management interfaces (SSH, Grafana, Prometheus, AWX).
    REQUIRED - You must explicitly set this for security reasons.
    Use 'curl -s ifconfig.me' to find your public IP.
  EOT
  type        = list(string)

  validation {
    condition = alltrue([
      for cidr in var.management_allowed_cidrs : can(cidrhost(cidr, 0))
    ])
    error_message = "All management allowed CIDR blocks must be valid IPv4 CIDR blocks."
  }

  validation {
    condition     = length(var.management_allowed_cidrs) > 0
    error_message = "management_allowed_cidrs must contain at least one CIDR block."
  }

  validation {
    condition     = !contains(var.management_allowed_cidrs, "0.0.0.0/0")
    error_message = "management_allowed_cidrs cannot include 0.0.0.0/0 - this would expose management interfaces to the entire internet."
  }
}

variable "allowed_ssh_cidr_blocks" {
  description = "CIDR blocks allowed to SSH to instances (via bastion or monitoring server)"
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
# Tagging Configuration
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
