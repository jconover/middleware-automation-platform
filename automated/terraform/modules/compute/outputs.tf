# =============================================================================
# Compute Module - Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# Instance Outputs
# -----------------------------------------------------------------------------
output "instance_ids" {
  description = "List of EC2 instance IDs"
  value       = aws_instance.this[*].id
}

output "instance_arns" {
  description = "List of EC2 instance ARNs"
  value       = aws_instance.this[*].arn
}

output "instance_private_ips" {
  description = "List of private IP addresses"
  value       = aws_instance.this[*].private_ip
}

output "instance_public_ips" {
  description = "List of public IP addresses (if assigned)"
  value       = aws_instance.this[*].public_ip
}

output "instance_private_dns" {
  description = "List of private DNS names"
  value       = aws_instance.this[*].private_dns
}

output "instance_public_dns" {
  description = "List of public DNS names (if applicable)"
  value       = aws_instance.this[*].public_dns
}

output "instance_availability_zones" {
  description = "List of availability zones for each instance"
  value       = aws_instance.this[*].availability_zone
}

output "instance_subnet_ids" {
  description = "List of subnet IDs for each instance"
  value       = aws_instance.this[*].subnet_id
}

# -----------------------------------------------------------------------------
# AMI Output
# -----------------------------------------------------------------------------
output "ami_id" {
  description = "AMI ID used for instances"
  value       = local.ami_id
}

# -----------------------------------------------------------------------------
# IAM Outputs
# -----------------------------------------------------------------------------
output "iam_role_arn" {
  description = "ARN of the IAM role (null if not created)"
  value       = var.create_iam_role ? aws_iam_role.this[0].arn : null
}

output "iam_role_name" {
  description = "Name of the IAM role (null if not created)"
  value       = var.create_iam_role ? aws_iam_role.this[0].name : null
}

output "iam_role_id" {
  description = "ID of the IAM role (null if not created)"
  value       = var.create_iam_role ? aws_iam_role.this[0].id : null
}

output "iam_instance_profile_arn" {
  description = "ARN of the IAM instance profile (null if not created)"
  value       = var.create_iam_role ? aws_iam_instance_profile.this[0].arn : null
}

output "iam_instance_profile_name" {
  description = "Name of the IAM instance profile"
  value       = local.instance_profile_name
}

output "iam_instance_profile_id" {
  description = "ID of the IAM instance profile (null if not created)"
  value       = var.create_iam_role ? aws_iam_instance_profile.this[0].id : null
}

# -----------------------------------------------------------------------------
# SSH Key Outputs
# -----------------------------------------------------------------------------
output "ssh_key_name" {
  description = "Name of the SSH key pair"
  value       = local.key_name
}

output "ssh_key_id" {
  description = "ID of the SSH key pair (null if not created)"
  value       = var.create_key_pair ? aws_key_pair.this[0].id : null
}

output "ssh_key_fingerprint" {
  description = "Fingerprint of the SSH key pair (null if not created)"
  value       = var.create_key_pair ? aws_key_pair.this[0].fingerprint : null
}

# -----------------------------------------------------------------------------
# CloudWatch Outputs
# -----------------------------------------------------------------------------
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group (null if not created)"
  value       = var.create_cloudwatch_log_group ? aws_cloudwatch_log_group.this[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group (null if not created)"
  value       = var.create_cloudwatch_log_group ? aws_cloudwatch_log_group.this[0].arn : null
}

# -----------------------------------------------------------------------------
# Computed Outputs for Integration
# -----------------------------------------------------------------------------
output "instances" {
  description = "Map of instance details for integration with other resources"
  value = {
    for idx, instance in aws_instance.this : idx => {
      id                = instance.id
      arn               = instance.arn
      private_ip        = instance.private_ip
      public_ip         = instance.public_ip
      private_dns       = instance.private_dns
      public_dns        = instance.public_dns
      availability_zone = instance.availability_zone
      subnet_id         = instance.subnet_id
    }
  }
}

output "instance_count" {
  description = "Number of instances created"
  value       = var.instance_count
}
