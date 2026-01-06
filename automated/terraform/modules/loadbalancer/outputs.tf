# =============================================================================
# Load Balancer Module - Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# ALB Outputs
# -----------------------------------------------------------------------------
output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Canonical hosted zone ID of the ALB (for Route 53 alias records)"
  value       = aws_lb.main.zone_id
}

output "alb_arn_suffix" {
  description = "ARN suffix of the ALB (for CloudWatch metrics)"
  value       = aws_lb.main.arn_suffix
}

output "alb_id" {
  description = "ID of the Application Load Balancer"
  value       = aws_lb.main.id
}

# -----------------------------------------------------------------------------
# Listener Outputs
# -----------------------------------------------------------------------------
output "http_listener_arn" {
  description = "ARN of the HTTP listener (port 80)"
  value       = aws_lb_listener.http.arn
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener (port 443), null if HTTPS is not enabled"
  value       = length(aws_lb_listener.https) > 0 ? aws_lb_listener.https[0].arn : null
}

# -----------------------------------------------------------------------------
# Target Group Outputs
# -----------------------------------------------------------------------------
output "ecs_target_group_arn" {
  description = "ARN of the ECS target group (IP-based for Fargate)"
  value       = var.create_ecs_target_group ? aws_lb_target_group.ecs[0].arn : null
}

output "ecs_target_group_arn_suffix" {
  description = "ARN suffix of the ECS target group (for CloudWatch metrics)"
  value       = var.create_ecs_target_group ? aws_lb_target_group.ecs[0].arn_suffix : null
}

output "ecs_target_group_name" {
  description = "Name of the ECS target group"
  value       = var.create_ecs_target_group ? aws_lb_target_group.ecs[0].name : null
}

output "ec2_target_group_arn" {
  description = "ARN of the EC2 target group (instance-based)"
  value       = var.create_ec2_target_group ? aws_lb_target_group.ec2[0].arn : null
}

output "ec2_target_group_arn_suffix" {
  description = "ARN suffix of the EC2 target group (for CloudWatch metrics)"
  value       = var.create_ec2_target_group ? aws_lb_target_group.ec2[0].arn_suffix : null
}

output "ec2_target_group_name" {
  description = "Name of the EC2 target group"
  value       = var.create_ec2_target_group ? aws_lb_target_group.ec2[0].name : null
}

# -----------------------------------------------------------------------------
# Access Logs Outputs
# -----------------------------------------------------------------------------
output "access_logs_bucket_name" {
  description = "Name of the S3 bucket for ALB access logs"
  value       = var.enable_access_logs ? aws_s3_bucket.alb_logs[0].id : null
}

output "access_logs_bucket_arn" {
  description = "ARN of the S3 bucket for ALB access logs"
  value       = var.enable_access_logs ? aws_s3_bucket.alb_logs[0].arn : null
}

# -----------------------------------------------------------------------------
# Aliases for S3 Replication and SLO Alarm Configuration
# -----------------------------------------------------------------------------
output "alb_logs_bucket_arn" {
  description = "ARN of the ALB access logs S3 bucket (alias for access_logs_bucket_arn)"
  value       = var.enable_access_logs ? aws_s3_bucket.alb_logs[0].arn : null
}

output "alb_logs_bucket_id" {
  description = "Name/ID of the ALB access logs S3 bucket (alias for access_logs_bucket_name)"
  value       = var.enable_access_logs ? aws_s3_bucket.alb_logs[0].id : null
}

# -----------------------------------------------------------------------------
# Certificate Outputs
# -----------------------------------------------------------------------------
output "effective_certificate_arn" {
  description = "ARN of the certificate being used (provided or self-signed)"
  value       = local.effective_certificate_arn != "" ? local.effective_certificate_arn : null
}

output "is_using_self_signed_cert" {
  description = "Whether the ALB is using a self-signed certificate"
  value       = var.enable_https && var.certificate_arn == "" && length(aws_acm_certificate.self_signed) > 0
}

# -----------------------------------------------------------------------------
# URL Outputs
# -----------------------------------------------------------------------------
output "app_url" {
  description = "Application URL (HTTPS if certificate available, HTTP otherwise)"
  value       = local.has_certificate ? "https://${aws_lb.main.dns_name}" : "http://${aws_lb.main.dns_name}"
}

# -----------------------------------------------------------------------------
# Configuration Summary
# -----------------------------------------------------------------------------
output "configuration" {
  description = "Load balancer configuration summary"
  value = {
    name                     = aws_lb.main.name
    dns_name                 = aws_lb.main.dns_name
    internal                 = var.internal
    deletion_protection      = var.enable_deletion_protection
    https_enabled            = local.has_certificate
    access_logs_enabled      = var.enable_access_logs
    access_logs_retention    = var.access_logs_retention_days
    ecs_target_group         = var.create_ecs_target_group
    ec2_target_group         = var.create_ec2_target_group
    stickiness_enabled       = var.stickiness_enabled
    stickiness_duration      = var.stickiness_duration
    health_check_path        = var.health_check_path
    metrics_endpoint_blocked = var.block_metrics_endpoint
  }
}
