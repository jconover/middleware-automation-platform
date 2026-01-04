# =============================================================================
# Security Groups Module - Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# Core Security Group IDs
# -----------------------------------------------------------------------------
output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "liberty_security_group_id" {
  description = "ID of the Liberty EC2 security group"
  value       = var.create_liberty_sg ? aws_security_group.liberty[0].id : null
}

output "ecs_security_group_id" {
  description = "ID of the ECS security group"
  value       = var.create_ecs_sg ? aws_security_group.ecs[0].id : null
}

output "db_security_group_id" {
  description = "ID of the database security group"
  value       = aws_security_group.db.id
}

output "cache_security_group_id" {
  description = "ID of the cache security group"
  value       = aws_security_group.cache.id
}

# -----------------------------------------------------------------------------
# New Security Group IDs
# -----------------------------------------------------------------------------
output "monitoring_security_group_id" {
  description = "ID of the monitoring (Prometheus/Grafana) security group"
  value       = var.create_monitoring_sg ? aws_security_group.monitoring[0].id : null
}

output "management_security_group_id" {
  description = "ID of the management (AWX/Jenkins) security group"
  value       = var.create_management_sg ? aws_security_group.management[0].id : null
}

output "bastion_security_group_id" {
  description = "ID of the bastion host security group"
  value       = var.create_bastion_sg ? aws_security_group.bastion[0].id : null
}

output "rds_proxy_security_group_id" {
  description = "ID of the RDS Proxy security group"
  value       = var.create_rds_proxy_sg ? aws_security_group.rds_proxy[0].id : null
}

# -----------------------------------------------------------------------------
# Security Group ARNs (useful for IAM policies)
# -----------------------------------------------------------------------------
output "alb_security_group_arn" {
  description = "ARN of the ALB security group"
  value       = aws_security_group.alb.arn
}

output "liberty_security_group_arn" {
  description = "ARN of the Liberty EC2 security group"
  value       = var.create_liberty_sg ? aws_security_group.liberty[0].arn : null
}

output "ecs_security_group_arn" {
  description = "ARN of the ECS security group"
  value       = var.create_ecs_sg ? aws_security_group.ecs[0].arn : null
}

output "db_security_group_arn" {
  description = "ARN of the database security group"
  value       = aws_security_group.db.arn
}

output "cache_security_group_arn" {
  description = "ARN of the cache security group"
  value       = aws_security_group.cache.arn
}

output "monitoring_security_group_arn" {
  description = "ARN of the monitoring security group"
  value       = var.create_monitoring_sg ? aws_security_group.monitoring[0].arn : null
}

output "management_security_group_arn" {
  description = "ARN of the management security group"
  value       = var.create_management_sg ? aws_security_group.management[0].arn : null
}

output "bastion_security_group_arn" {
  description = "ARN of the bastion security group"
  value       = var.create_bastion_sg ? aws_security_group.bastion[0].arn : null
}

output "rds_proxy_security_group_arn" {
  description = "ARN of the RDS Proxy security group"
  value       = var.create_rds_proxy_sg ? aws_security_group.rds_proxy[0].arn : null
}

# -----------------------------------------------------------------------------
# Aggregated Outputs (for convenience)
# -----------------------------------------------------------------------------
output "all_security_group_ids" {
  description = "Map of all created security group IDs"
  value = {
    alb        = aws_security_group.alb.id
    liberty    = var.create_liberty_sg ? aws_security_group.liberty[0].id : null
    ecs        = var.create_ecs_sg ? aws_security_group.ecs[0].id : null
    db         = aws_security_group.db.id
    cache      = aws_security_group.cache.id
    monitoring = var.create_monitoring_sg ? aws_security_group.monitoring[0].id : null
    management = var.create_management_sg ? aws_security_group.management[0].id : null
    bastion    = var.create_bastion_sg ? aws_security_group.bastion[0].id : null
    rds_proxy  = var.create_rds_proxy_sg ? aws_security_group.rds_proxy[0].id : null
  }
}

output "application_security_group_ids" {
  description = "List of security group IDs for application workloads (Liberty EC2 and/or ECS)"
  value = compact([
    var.create_liberty_sg ? aws_security_group.liberty[0].id : "",
    var.create_ecs_sg ? aws_security_group.ecs[0].id : ""
  ])
}
