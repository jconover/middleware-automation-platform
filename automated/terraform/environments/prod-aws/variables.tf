# =============================================================================
# Variables
# =============================================================================

# -----------------------------------------------------------------------------
# General
# -----------------------------------------------------------------------------
variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "middleware-platform"
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "availability_zones" {
  description = "Number of availability zones to use"
  type        = number
  default     = 2
}

# -----------------------------------------------------------------------------
# Compute
# -----------------------------------------------------------------------------
variable "liberty_instance_type" {
  description = "EC2 instance type for Liberty servers"
  type        = string
  default     = "t3.small"
}

variable "liberty_instance_count" {
  description = "Number of Liberty EC2 instances"
  type        = number
  default     = 2
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key for EC2 access"
  type        = string
  default     = "~/.ssh/ansible_ed25519.pub"
}

variable "allowed_ssh_cidr_blocks" {
  description = "CIDR blocks allowed to SSH to instances (via bastion)"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Database
# -----------------------------------------------------------------------------
variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "appuser"
}

variable "db_allocated_storage" {
  description = "Allocated storage for RDS in GB"
  type        = number
  default     = 20
}

variable "db_backup_retention_period" {
  description = "Number of days to retain RDS backups"
  type        = number
  default     = 7
}

# -----------------------------------------------------------------------------
# Cache
# -----------------------------------------------------------------------------
variable "cache_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.micro"
}

# -----------------------------------------------------------------------------
# SSL/TLS
# -----------------------------------------------------------------------------
variable "domain_name" {
  description = "Domain name for ACM certificate (e.g., app.example.com)"
  type        = string
  default     = ""
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
}

# -----------------------------------------------------------------------------
# Tagging
# -----------------------------------------------------------------------------
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
