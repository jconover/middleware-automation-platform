# =============================================================================
# Database - RDS PostgreSQL and ElastiCache Redis
# =============================================================================

# -----------------------------------------------------------------------------
# Database Credentials (Secrets Manager)
# -----------------------------------------------------------------------------
resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# -----------------------------------------------------------------------------
# Redis AUTH Token
# -----------------------------------------------------------------------------
resource "random_password" "redis_auth" {
  length  = 32
  special = false # Redis auth token has character restrictions
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${local.name_prefix}/database/credentials"
  description = "Database credentials for ${local.name_prefix}"

  tags = {
    Name = "${local.name_prefix}-db-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id

  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    host     = aws_db_instance.main.address
    port     = 5432
    dbname   = var.db_name
    engine   = "postgres"
  })
}

# -----------------------------------------------------------------------------
# RDS Subnet Group
# -----------------------------------------------------------------------------
resource "aws_db_subnet_group" "main" {
  name        = "${local.name_prefix}-db-subnet"
  description = "Database subnet group for ${local.name_prefix}"
  subnet_ids  = module.networking.private_subnet_ids

  tags = {
    Name = "${local.name_prefix}-db-subnet"
  }
}

# -----------------------------------------------------------------------------
# RDS PostgreSQL
# -----------------------------------------------------------------------------
resource "aws_db_instance" "main" {
  identifier = "${local.name_prefix}-postgres"

  engine                = "postgres"
  engine_version        = "15"
  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_allocated_storage * 2 # Enable autoscaling up to 2x

  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]

  # Backup configuration
  backup_retention_period = var.db_backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Performance Insights (free tier available)
  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  # Monitoring
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  # Other settings
  multi_az                  = true
  publicly_accessible       = false
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name_prefix}-postgres-final"
  deletion_protection       = true

  tags = {
    Name = "${local.name_prefix}-postgres"
  }
}

# -----------------------------------------------------------------------------
# RDS Read Replica (Disaster Recovery)
# -----------------------------------------------------------------------------
resource "aws_db_instance" "replica" {
  count = var.db_create_read_replica ? 1 : 0

  identifier = "${local.name_prefix}-postgres-replica"

  # Source database for replication
  replicate_source_db = aws_db_instance.main.identifier

  # Instance configuration (inherits engine, storage settings from source)
  instance_class = var.db_replica_instance_class != "" ? var.db_replica_instance_class : var.db_instance_class

  # Storage (inherited from source, but can enable autoscaling)
  max_allocated_storage = var.db_allocated_storage * 2

  # Performance Insights enabled for replica monitoring
  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  # Enhanced Monitoring (uses same role as primary)
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  # Network settings
  # Note: For read replica, we don't specify db_subnet_group_name or vpc_security_group_ids
  # as they are inherited from the source. However, we can override if needed.
  vpc_security_group_ids = [aws_security_group.db.id]

  # Replica-specific settings
  publicly_accessible = false
  skip_final_snapshot = true # Replicas don't need final snapshot

  # Backup configuration (replicas can have independent backups)
  backup_retention_period = 0 # Set to 0 for replica, primary handles backups

  # Auto minor version upgrade
  auto_minor_version_upgrade = true

  tags = {
    Name        = "${local.name_prefix}-postgres-replica"
    Role        = "read-replica"
    ReplicaOf   = aws_db_instance.main.identifier
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# RDS Enhanced Monitoring Role
# -----------------------------------------------------------------------------
resource "aws_iam_role" "rds_monitoring" {
  name = "${local.name_prefix}-rds-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "monitoring.rds.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# -----------------------------------------------------------------------------
# ElastiCache Subnet Group
# -----------------------------------------------------------------------------
resource "aws_elasticache_subnet_group" "main" {
  name        = "${local.name_prefix}-cache-subnet"
  description = "Cache subnet group for ${local.name_prefix}"
  subnet_ids  = module.networking.private_subnet_ids

  tags = {
    Name = "${local.name_prefix}-cache-subnet"
  }
}

# -----------------------------------------------------------------------------
# ElastiCache Redis (Replication Group for encryption support)
# -----------------------------------------------------------------------------
resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "${local.name_prefix}-redis"
  description          = "Redis cluster for ${local.name_prefix}"

  engine               = "redis"
  engine_version       = "7.0"
  node_type            = var.cache_node_type
  num_cache_clusters   = var.cache_multi_az ? 2 : 1
  parameter_group_name = "default.redis7"
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.cache.id]

  # Multi-AZ configuration for high availability
  automatic_failover_enabled = var.cache_multi_az
  multi_az_enabled           = var.cache_multi_az

  # Encryption settings
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  # AUTH token for Redis authentication
  auth_token = random_password.redis_auth.result

  # Increased snapshot retention when multi-az is enabled for DR
  snapshot_retention_limit = var.cache_multi_az ? 7 : 1
  snapshot_window          = "05:00-06:00"
  maintenance_window       = "sun:06:00-sun:07:00"

  tags = {
    Name = "${local.name_prefix}-redis"
  }
}

# -----------------------------------------------------------------------------
# Redis AUTH Token Secret (for application access)
# -----------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "redis_auth" {
  name        = "${local.name_prefix}/redis/auth-token"
  description = "Redis AUTH token for ${local.name_prefix}"

  tags = {
    Name = "${local.name_prefix}-redis-auth"
  }
}

resource "aws_secretsmanager_secret_version" "redis_auth" {
  secret_id = aws_secretsmanager_secret.redis_auth.id

  secret_string = jsonencode({
    auth_token = random_password.redis_auth.result
    host       = aws_elasticache_replication_group.main.primary_endpoint_address
    port       = 6379
  })
}
