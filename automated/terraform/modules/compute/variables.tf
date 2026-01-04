# =============================================================================
# Compute Module - Variables
# =============================================================================

# -----------------------------------------------------------------------------
# General Configuration
# -----------------------------------------------------------------------------
variable "name_prefix" {
  description = "Prefix for resource names (e.g., 'mw-prod-liberty')"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,60}[a-z0-9]$", var.name_prefix))
    error_message = "Name prefix must be 3-62 characters, lowercase alphanumeric with hyphens, not starting or ending with hyphen."
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
# Instance Configuration
# -----------------------------------------------------------------------------
variable "instance_count" {
  description = "Number of EC2 instances to create"
  type        = number
  default     = 1

  validation {
    condition     = var.instance_count >= 0 && var.instance_count <= 100
    error_message = "Instance count must be between 0 and 100."
  }
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"

  validation {
    condition     = can(regex("^[a-z][0-9][a-z]?\\.(nano|micro|small|medium|large|[0-9]*xlarge|metal)$", var.instance_type))
    error_message = "Instance type must be a valid EC2 instance type format (e.g., t3.small, m5.large)."
  }
}

variable "ami_id" {
  description = "AMI ID for instances. If null, latest Ubuntu 22.04 LTS is used."
  type        = string
  default     = null

  validation {
    condition     = var.ami_id == null || can(regex("^ami-[a-f0-9]{8,17}$", var.ami_id))
    error_message = "AMI ID must be null or a valid AMI ID format (ami-xxxxxxxxx)."
  }
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------
variable "subnet_ids" {
  description = "List of subnet IDs to distribute instances across"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "At least one subnet ID must be provided."
  }

  validation {
    condition = alltrue([
      for id in var.subnet_ids : can(regex("^subnet-[a-f0-9]{8,17}$", id))
    ])
    error_message = "All subnet IDs must be valid format (subnet-xxxxxxxxx)."
  }
}

variable "security_group_ids" {
  description = "List of security group IDs to attach to instances"
  type        = list(string)

  validation {
    condition     = length(var.security_group_ids) > 0
    error_message = "At least one security group ID must be provided."
  }

  validation {
    condition = alltrue([
      for id in var.security_group_ids : can(regex("^sg-[a-f0-9]{8,17}$", id))
    ])
    error_message = "All security group IDs must be valid format (sg-xxxxxxxxx)."
  }
}

variable "availability_zone" {
  description = "Specific availability zone for all instances (overrides subnet distribution)"
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# SSH Key Configuration
# -----------------------------------------------------------------------------
variable "create_key_pair" {
  description = "Whether to create a new SSH key pair"
  type        = bool
  default     = true
}

variable "ssh_public_key" {
  description = "SSH public key content for the key pair (required if create_key_pair is true)"
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = var.ssh_public_key == null || can(regex("^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp)", var.ssh_public_key))
    error_message = "SSH public key must be null or a valid SSH public key format."
  }
}

variable "existing_key_name" {
  description = "Name of existing SSH key pair to use (required if create_key_pair is false)"
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# IAM Configuration
# -----------------------------------------------------------------------------
variable "create_iam_role" {
  description = "Whether to create a new IAM role and instance profile"
  type        = bool
  default     = true
}

variable "existing_instance_profile_name" {
  description = "Name of existing IAM instance profile (required if create_iam_role is false)"
  type        = string
  default     = null
}

variable "enable_ssm" {
  description = "Attach SSM managed policy for Systems Manager access"
  type        = bool
  default     = true
}

variable "iam_managed_policy_arns" {
  description = "List of IAM managed policy ARNs to attach to the role"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for arn in var.iam_managed_policy_arns : can(regex("^arn:aws:iam::(aws|[0-9]{12}):policy/", arn))
    ])
    error_message = "All IAM policy ARNs must be valid format."
  }
}

variable "iam_inline_policy_statements" {
  description = "List of IAM policy statements to include in inline policy"
  type = list(object({
    Effect   = string
    Action   = list(string)
    Resource = list(string)
  }))
  default = []
}

# -----------------------------------------------------------------------------
# Storage Configuration
# -----------------------------------------------------------------------------
variable "root_volume_size" {
  description = "Size of root EBS volume in GB"
  type        = number
  default     = 30

  validation {
    condition     = var.root_volume_size >= 8 && var.root_volume_size <= 16384
    error_message = "Root volume size must be between 8 and 16384 GB."
  }
}

variable "root_volume_type" {
  description = "Type of root EBS volume"
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2", "st1", "sc1"], var.root_volume_type)
    error_message = "Root volume type must be one of: gp2, gp3, io1, io2, st1, sc1."
  }
}

variable "root_volume_encrypted" {
  description = "Whether to encrypt the root EBS volume"
  type        = bool
  default     = true
}

variable "root_volume_kms_key_id" {
  description = "KMS key ID for root volume encryption (uses AWS managed key if null)"
  type        = string
  default     = null
}

variable "root_volume_delete_on_termination" {
  description = "Whether to delete root volume on instance termination"
  type        = bool
  default     = true
}

variable "additional_ebs_volumes" {
  description = "List of additional EBS volumes to attach"
  type = list(object({
    device_name           = string
    volume_size           = number
    volume_type           = optional(string, "gp3")
    encrypted             = optional(bool, true)
    kms_key_id            = optional(string)
    delete_on_termination = optional(bool, true)
  }))
  default = []
}

# -----------------------------------------------------------------------------
# User Data Configuration
# -----------------------------------------------------------------------------
variable "user_data_base64" {
  description = "Base64-encoded user data (takes precedence over user_data_template)"
  type        = string
  default     = null
}

variable "user_data_template" {
  description = "Path to user data template file"
  type        = string
  default     = null
}

variable "user_data_template_vars" {
  description = "Variables to pass to user data template (aws_region, name_prefix, instance_id are added automatically)"
  type        = map(any)
  default     = {}
}

# -----------------------------------------------------------------------------
# Instance Metadata Service Configuration
# -----------------------------------------------------------------------------
variable "require_imdsv2" {
  description = "Require IMDSv2 for instance metadata (recommended for security)"
  type        = bool
  default     = true
}

variable "imds_hop_limit" {
  description = "HTTP PUT response hop limit for IMDS"
  type        = number
  default     = 1

  validation {
    condition     = var.imds_hop_limit >= 1 && var.imds_hop_limit <= 64
    error_message = "IMDS hop limit must be between 1 and 64."
  }
}

# -----------------------------------------------------------------------------
# Monitoring Configuration
# -----------------------------------------------------------------------------
variable "detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring (1-minute intervals)"
  type        = bool
  default     = false
}

variable "create_cloudwatch_log_group" {
  description = "Create CloudWatch log group for instance logs"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention value."
  }
}

variable "log_group_kms_key_id" {
  description = "KMS key ID for CloudWatch log group encryption"
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Placement Configuration
# -----------------------------------------------------------------------------
variable "tenancy" {
  description = "Instance tenancy (default, dedicated, or host)"
  type        = string
  default     = "default"

  validation {
    condition     = contains(["default", "dedicated", "host"], var.tenancy)
    error_message = "Tenancy must be one of: default, dedicated, host."
  }
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

variable "instance_tags" {
  description = "Additional tags to apply only to EC2 instances (merged with tags)"
  type        = map(string)
  default     = {}
}
