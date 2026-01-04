# =============================================================================
# Networking Module - Variables
# =============================================================================

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  description = "Number of availability zones to use"
  type        = number

  validation {
    condition     = var.availability_zones >= 2 && var.availability_zones <= 6
    error_message = "Availability zones must be between 2 and 6."
  }
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in the VPC"
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Enable DNS support in the VPC"
  type        = bool
  default     = true
}

variable "map_public_ip_on_launch" {
  description = "Assign public IPs to instances in public subnets"
  type        = bool
  default     = true
}

variable "public_subnet_offset" {
  description = "Offset for public subnet CIDR calculation"
  type        = number
  default     = 1
}

variable "private_subnet_offset" {
  description = "Offset for private subnet CIDR calculation"
  type        = number
  default     = 10
}

variable "enable_nat_gateway" {
  description = "Enable NAT gateway for private subnets"
  type        = bool
  default     = true
}

variable "high_availability_nat" {
  description = "Deploy NAT Gateway per AZ for high availability (+$32/month per additional NAT)"
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Enable VPC flow logs"
  type        = bool
  default     = true
}

variable "enable_flow_logs_encryption" {
  description = "Enable KMS encryption for VPC flow logs (creates a KMS key)"
  type        = bool
  default     = true
}

variable "flow_logs_traffic_type" {
  description = "Type of traffic to log (ACCEPT, REJECT, or ALL)"
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_logs_traffic_type)
    error_message = "Flow logs traffic type must be ACCEPT, REJECT, or ALL."
  }
}

variable "flow_logs_retention_days" {
  description = "Number of days to retain VPC flow logs"
  type        = number
  default     = 30
}

variable "aws_region" {
  description = "AWS region (required for KMS key policy)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
