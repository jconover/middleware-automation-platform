# =============================================================================
# Security Groups Module - Variables
# =============================================================================

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

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
