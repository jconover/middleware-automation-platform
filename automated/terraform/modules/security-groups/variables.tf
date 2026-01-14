# =============================================================================
# Security Groups Module - Variables
# =============================================================================

# -----------------------------------------------------------------------------
# Core Variables
# -----------------------------------------------------------------------------
variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Security Group Creation Flags
# -----------------------------------------------------------------------------
variable "create_liberty_sg" {
  description = "Create security group for Liberty EC2 instances"
  type        = bool
  default     = true
}

variable "create_ecs_sg" {
  description = "Create security group for ECS tasks"
  type        = bool
  default     = true
}

variable "create_monitoring_sg" {
  description = "Create security group for Prometheus/Grafana monitoring server"
  type        = bool
  default     = false
}

variable "create_management_sg" {
  description = "Create security group for AWX/Jenkins management server"
  type        = bool
  default     = false
}

variable "create_bastion_sg" {
  description = "Create security group for bastion host"
  type        = bool
  default     = false
}

variable "create_rds_proxy_sg" {
  description = "Create security group for RDS Proxy"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Egress Restriction
# -----------------------------------------------------------------------------
variable "restrict_egress" {
  description = "Restrict egress rules for ECS and Liberty SGs to specific ports (HTTPS, DB, Cache) instead of allowing all traffic. Recommended for security."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Allowed CIDRs for New Security Groups
# -----------------------------------------------------------------------------
variable "monitoring_allowed_cidrs" {
  description = "CIDR blocks allowed to access monitoring services (SSH, Prometheus, Grafana, AlertManager)"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.monitoring_allowed_cidrs : can(cidrhost(cidr, 0))])
    error_message = "All monitoring_allowed_cidrs must be valid CIDR blocks."
  }
}

variable "management_allowed_cidrs" {
  description = "CIDR blocks allowed to access management services (SSH, HTTP, HTTPS, AWX)"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.management_allowed_cidrs : can(cidrhost(cidr, 0))])
    error_message = "All management_allowed_cidrs must be valid CIDR blocks."
  }
}

variable "bastion_allowed_cidrs" {
  description = "CIDR blocks allowed to SSH to bastion host"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.bastion_allowed_cidrs : can(cidrhost(cidr, 0))])
    error_message = "All bastion_allowed_cidrs must be valid CIDR blocks."
  }
}
