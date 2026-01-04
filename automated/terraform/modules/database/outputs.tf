# =============================================================================
# Database Module - Outputs
# =============================================================================
# Output values for RDS PostgreSQL, ElastiCache Redis, and RDS Proxy
# =============================================================================

# -----------------------------------------------------------------------------
# RDS PostgreSQL Outputs
# -----------------------------------------------------------------------------
output "db_endpoint" {
  description = "RDS PostgreSQL endpoint address"
  value       = aws_db_instance.main.address
}

output "db_port" {
  description = "RDS PostgreSQL port"
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "Database name"
  value       = aws_db_instance.main.db_name
}

output "db_arn" {
  description = "RDS PostgreSQL ARN"
  value       = aws_db_instance.main.arn
}

output "db_identifier" {
  description = "RDS PostgreSQL identifier"
  value       = aws_db_instance.main.identifier
}

output "db_resource_id" {
  description = "RDS PostgreSQL resource ID (for IAM authentication)"
  value       = aws_db_instance.main.resource_id
}

output "db_secret_arn" {
  description = "Secrets Manager secret ARN for database credentials"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "db_secret_name" {
  description = "Secrets Manager secret name for database credentials"
  value       = aws_secretsmanager_secret.db_credentials.name
}

output "db_username" {
  description = "Database master username"
  value       = var.db_username
}

output "db_subnet_group_name" {
  description = "RDS subnet group name"
  value       = aws_db_subnet_group.main.name
}

output "db_monitoring_role_arn" {
  description = "RDS enhanced monitoring IAM role ARN"
  value       = var.db_monitoring_interval > 0 ? aws_iam_role.rds_monitoring[0].arn : null
}

# -----------------------------------------------------------------------------
# ElastiCache Redis Outputs
# -----------------------------------------------------------------------------
output "cache_endpoint" {
  description = "ElastiCache Redis primary endpoint address"
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
}

output "cache_reader_endpoint" {
  description = "ElastiCache Redis reader endpoint address (for read replicas)"
  value       = aws_elasticache_replication_group.main.reader_endpoint_address
}

output "cache_port" {
  description = "ElastiCache Redis port"
  value       = aws_elasticache_replication_group.main.port
}

output "cache_arn" {
  description = "ElastiCache Redis replication group ARN"
  value       = aws_elasticache_replication_group.main.arn
}

output "cache_id" {
  description = "ElastiCache Redis replication group ID"
  value       = aws_elasticache_replication_group.main.id
}

output "cache_auth_token_secret_arn" {
  description = "Secrets Manager secret ARN for Redis AUTH token"
  value       = aws_secretsmanager_secret.redis_auth.arn
}

output "cache_auth_token_secret_name" {
  description = "Secrets Manager secret name for Redis AUTH token"
  value       = aws_secretsmanager_secret.redis_auth.name
}

output "cache_subnet_group_name" {
  description = "ElastiCache subnet group name"
  value       = aws_elasticache_subnet_group.main.name
}

# -----------------------------------------------------------------------------
# RDS Proxy Outputs (conditional)
# -----------------------------------------------------------------------------
output "rds_proxy_endpoint" {
  description = "RDS Proxy endpoint (null if proxy not enabled)"
  value       = var.enable_rds_proxy ? aws_db_proxy.main[0].endpoint : null
}

output "rds_proxy_arn" {
  description = "RDS Proxy ARN (null if proxy not enabled)"
  value       = var.enable_rds_proxy ? aws_db_proxy.main[0].arn : null
}

output "rds_proxy_name" {
  description = "RDS Proxy name (null if proxy not enabled)"
  value       = var.enable_rds_proxy ? aws_db_proxy.main[0].name : null
}

output "rds_proxy_read_endpoint" {
  description = "RDS Proxy read-only endpoint (null if not enabled)"
  value       = var.enable_rds_proxy && var.enable_rds_proxy_read_endpoint ? aws_db_proxy_endpoint.read_only[0].endpoint : null
}

output "rds_proxy_role_arn" {
  description = "RDS Proxy IAM role ARN (null if proxy not enabled)"
  value       = var.enable_rds_proxy ? aws_iam_role.rds_proxy[0].arn : null
}

# -----------------------------------------------------------------------------
# Computed Outputs (for convenience)
# -----------------------------------------------------------------------------
output "db_effective_endpoint" {
  description = "Effective database endpoint (RDS Proxy if enabled, otherwise direct RDS endpoint)"
  value       = var.enable_rds_proxy ? aws_db_proxy.main[0].endpoint : aws_db_instance.main.address
}

output "db_connection_string" {
  description = "PostgreSQL connection string template (password from Secrets Manager)"
  value       = "postgresql://${var.db_username}:<password>@${var.enable_rds_proxy ? aws_db_proxy.main[0].endpoint : aws_db_instance.main.address}:5432/${var.db_name}?sslmode=require"
  sensitive   = false
}

output "cache_connection_string" {
  description = "Redis connection string template (auth token from Secrets Manager)"
  value       = "rediss://:@${aws_elasticache_replication_group.main.primary_endpoint_address}:6379"
  sensitive   = false
}

# -----------------------------------------------------------------------------
# Proxy Status Output
# -----------------------------------------------------------------------------
output "rds_proxy_enabled" {
  description = "Whether RDS Proxy is enabled"
  value       = var.enable_rds_proxy
}
