# =============================================================================
# Database Module - Variables
# =============================================================================
# Input variables for RDS PostgreSQL, ElastiCache Redis, and RDS Proxy
# =============================================================================

# -----------------------------------------------------------------------------
# General
# -----------------------------------------------------------------------------
variable "name_prefix" {
  description = "Prefix for resource names (e.g., mw-prod)"
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

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------
variable "vpc_id" {
  description = "VPC ID where database resources will be deployed"
  type        = string

  validation {
    condition     = can(regex("^vpc-[a-f0-9]+$", var.vpc_id))
    error_message = "VPC ID must be a valid format (e.g., vpc-0123456789abcdef0)."
  }
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for database subnet groups"
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "At least 2 private subnets are required for high availability."
  }

  validation {
    condition = alltrue([
      for subnet_id in var.private_subnet_ids : can(regex("^subnet-[a-f0-9]+$", subnet_id))
    ])
    error_message = "All subnet IDs must be in valid format (e.g., subnet-0123456789abcdef0)."
  }
}

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------
variable "db_security_group_id" {
  description = "Security group ID for RDS database"
  type        = string

  validation {
    condition     = can(regex("^sg-[a-f0-9]+$", var.db_security_group_id))
    error_message = "Security group ID must be a valid format (e.g., sg-0123456789abcdef0)."
  }
}

variable "cache_security_group_id" {
  description = "Security group ID for ElastiCache Redis"
  type        = string

  validation {
    condition     = can(regex("^sg-[a-f0-9]+$", var.cache_security_group_id))
    error_message = "Security group ID must be a valid format (e.g., sg-0123456789abcdef0)."
  }
}

variable "rds_proxy_security_group_id" {
  description = "Security group ID for RDS Proxy (required when enable_rds_proxy is true)"
  type        = string
  default     = ""

  validation {
    condition     = var.rds_proxy_security_group_id == "" || can(regex("^sg-[a-f0-9]+$", var.rds_proxy_security_group_id))
    error_message = "RDS Proxy security group ID must be empty or a valid format (e.g., sg-0123456789abcdef0)."
  }
}

# -----------------------------------------------------------------------------
# RDS PostgreSQL Configuration
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

variable "db_allocated_storage" {
  description = "Allocated storage for RDS in GB"
  type        = number
  default     = 20

  validation {
    condition     = var.db_allocated_storage >= 20 && var.db_allocated_storage <= 65536
    error_message = "Database allocated storage must be between 20 GB and 65536 GB."
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

variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15"

  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?$", var.db_engine_version))
    error_message = "Database engine version must be a valid PostgreSQL version (e.g., 15, 15.4)."
  }
}

variable "db_multi_az" {
  description = "Enable Multi-AZ deployment for RDS high availability"
  type        = bool
  default     = true
}

variable "db_backup_retention" {
  description = "Number of days to retain RDS backups"
  type        = number
  default     = 7

  validation {
    condition     = var.db_backup_retention >= 0 && var.db_backup_retention <= 35
    error_message = "Database backup retention period must be between 0 and 35 days."
  }
}

variable "db_deletion_protection" {
  description = "Enable deletion protection for RDS instance"
  type        = bool
  default     = true
}

variable "db_performance_insights_enabled" {
  description = "Enable Performance Insights for RDS (free tier available with 7-day retention)"
  type        = bool
  default     = true
}

variable "db_monitoring_interval" {
  description = "Enhanced monitoring interval in seconds (0 to disable, valid values: 0, 1, 5, 10, 15, 30, 60)"
  type        = number
  default     = 60

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.db_monitoring_interval)
    error_message = "Monitoring interval must be one of: 0, 1, 5, 10, 15, 30, 60."
  }
}

# -----------------------------------------------------------------------------
# ElastiCache Redis Configuration
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

variable "cache_engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.cache_engine_version))
    error_message = "Cache engine version must be a valid Redis version (e.g., 7.0, 6.2)."
  }
}

variable "cache_snapshot_retention" {
  description = "Number of days to retain ElastiCache snapshots (0 to disable)"
  type        = number
  default     = 7

  validation {
    condition     = var.cache_snapshot_retention >= 0 && var.cache_snapshot_retention <= 35
    error_message = "Cache snapshot retention must be between 0 and 35 days."
  }
}

# -----------------------------------------------------------------------------
# RDS Proxy Configuration
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
# Tagging
# -----------------------------------------------------------------------------
variable "tags" {
  description = "Additional tags to apply to all resources"
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
