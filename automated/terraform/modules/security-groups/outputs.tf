# =============================================================================
# Security Groups Module - Outputs
# =============================================================================

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
