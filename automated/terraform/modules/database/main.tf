# =============================================================================
# Database Module - Main Resources
# =============================================================================
# Creates RDS PostgreSQL, ElastiCache Redis, Secrets Manager secrets,
# and optional RDS Proxy for connection pooling
# =============================================================================

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# Random Passwords
# -----------------------------------------------------------------------------
resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "redis_auth" {
  length  = 32
  special = false # Redis auth token has character restrictions
}

# -----------------------------------------------------------------------------
# Database Credentials (Secrets Manager)
# -----------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${var.name_prefix}/database/credentials"
  description = "Database credentials for ${var.name_prefix}"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-db-credentials"
  })
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
  name        = "${var.name_prefix}-db-subnet"
  description = "Database subnet group for ${var.name_prefix}"
  subnet_ids  = var.private_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-db-subnet"
  })
}

# -----------------------------------------------------------------------------
# RDS Enhanced Monitoring Role
# -----------------------------------------------------------------------------
resource "aws_iam_role" "rds_monitoring" {
  count = var.db_monitoring_interval > 0 ? 1 : 0

  name = "${var.name_prefix}-rds-monitoring"

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

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rds-monitoring"
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  count = var.db_monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.rds_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# -----------------------------------------------------------------------------
# RDS PostgreSQL
# -----------------------------------------------------------------------------
resource "aws_db_instance" "main" {
  identifier = "${var.name_prefix}-postgres"

  engine                = "postgres"
  engine_version        = var.db_engine_version
  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_allocated_storage * 2 # Enable autoscaling up to 2x

  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.db_security_group_id]

  # Backup configuration
  backup_retention_period = var.db_backup_retention
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Performance Insights (free tier available)
  performance_insights_enabled          = var.db_performance_insights_enabled
  performance_insights_retention_period = var.db_performance_insights_enabled ? 7 : null

  # Monitoring
  monitoring_interval = var.db_monitoring_interval
  monitoring_role_arn = var.db_monitoring_interval > 0 ? aws_iam_role.rds_monitoring[0].arn : null

  # Other settings
  multi_az                  = var.db_multi_az
  publicly_accessible       = false
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name_prefix}-postgres-final"
  deletion_protection       = var.db_deletion_protection

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-postgres"
  })
}

# -----------------------------------------------------------------------------
# ElastiCache Subnet Group
# -----------------------------------------------------------------------------
resource "aws_elasticache_subnet_group" "main" {
  name        = "${var.name_prefix}-cache-subnet"
  description = "Cache subnet group for ${var.name_prefix}"
  subnet_ids  = var.private_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-cache-subnet"
  })
}

# -----------------------------------------------------------------------------
# ElastiCache Redis (Replication Group for encryption support)
# -----------------------------------------------------------------------------
resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "${var.name_prefix}-redis"
  description          = "Redis cluster for ${var.name_prefix}"

  engine               = "redis"
  engine_version       = var.cache_engine_version
  node_type            = var.cache_node_type
  num_cache_clusters   = var.cache_multi_az ? 2 : 1
  parameter_group_name = "default.redis${split(".", var.cache_engine_version)[0]}"
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [var.cache_security_group_id]

  # Multi-AZ configuration for high availability
  automatic_failover_enabled = var.cache_multi_az
  multi_az_enabled           = var.cache_multi_az

  # Encryption settings
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  # AUTH token for Redis authentication
  auth_token = random_password.redis_auth.result

  # Snapshot configuration
  snapshot_retention_limit = var.cache_multi_az ? var.cache_snapshot_retention : min(var.cache_snapshot_retention, 1)
  snapshot_window          = "05:00-06:00"
  maintenance_window       = "sun:06:00-sun:07:00"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-redis"
  })
}

# -----------------------------------------------------------------------------
# Redis AUTH Token Secret (for application access)
# -----------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "redis_auth" {
  name        = "${var.name_prefix}/redis/auth-token"
  description = "Redis AUTH token for ${var.name_prefix}"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-redis-auth"
  })
}

resource "aws_secretsmanager_secret_version" "redis_auth" {
  secret_id = aws_secretsmanager_secret.redis_auth.id

  secret_string = jsonencode({
    auth_token = random_password.redis_auth.result
    host       = aws_elasticache_replication_group.main.primary_endpoint_address
    port       = 6379
  })
}

# =============================================================================
# RDS Proxy Resources (Conditional)
# =============================================================================

# -----------------------------------------------------------------------------
# IAM Role for RDS Proxy (to access Secrets Manager)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "rds_proxy" {
  count = var.enable_rds_proxy ? 1 : 0

  name = "${var.name_prefix}-rds-proxy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "rds.amazonaws.com"
      }
    }]
  })

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rds-proxy-role"
  })
}

# -----------------------------------------------------------------------------
# IAM Policy for RDS Proxy (Secrets Manager Access)
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "rds_proxy_secrets" {
  count = var.enable_rds_proxy ? 1 : 0

  name = "${var.name_prefix}-rds-proxy-secrets"
  role = aws_iam_role.rds_proxy[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GetSecretValue"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.db_credentials.arn
        ]
      },
      {
        Sid    = "DecryptSecretValue"
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# RDS Proxy
# -----------------------------------------------------------------------------
resource "aws_db_proxy" "main" {
  count = var.enable_rds_proxy ? 1 : 0

  name                   = "${var.name_prefix}-rds-proxy"
  engine_family          = "POSTGRESQL"
  role_arn               = aws_iam_role.rds_proxy[0].arn
  vpc_subnet_ids         = var.private_subnet_ids
  vpc_security_group_ids = [var.rds_proxy_security_group_id]

  auth {
    auth_scheme               = "SECRETS"
    iam_auth                  = var.rds_proxy_require_iam ? "REQUIRED" : "DISABLED"
    secret_arn                = aws_secretsmanager_secret.db_credentials.arn
    client_password_auth_type = "POSTGRES_SCRAM_SHA_256"
  }

  require_tls         = true
  idle_client_timeout = var.rds_proxy_idle_timeout
  debug_logging       = false

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rds-proxy"
  })
}

# -----------------------------------------------------------------------------
# RDS Proxy Default Target Group (Connection Pool Settings)
# -----------------------------------------------------------------------------
resource "aws_db_proxy_default_target_group" "main" {
  count = var.enable_rds_proxy ? 1 : 0

  db_proxy_name = aws_db_proxy.main[0].name

  connection_pool_config {
    max_connections_percent      = var.rds_proxy_max_connections_percent
    max_idle_connections_percent = 50
    connection_borrow_timeout    = 120
    session_pinning_filters      = ["EXCLUDE_VARIABLE_SETS"]
  }
}

# -----------------------------------------------------------------------------
# RDS Proxy Target (Link to RDS Instance)
# -----------------------------------------------------------------------------
resource "aws_db_proxy_target" "main" {
  count = var.enable_rds_proxy ? 1 : 0

  db_proxy_name          = aws_db_proxy.main[0].name
  target_group_name      = aws_db_proxy_default_target_group.main[0].name
  db_instance_identifier = aws_db_instance.main.identifier
}

# -----------------------------------------------------------------------------
# RDS Proxy Read-Only Endpoint (Optional)
# -----------------------------------------------------------------------------
resource "aws_db_proxy_endpoint" "read_only" {
  count = var.enable_rds_proxy && var.enable_rds_proxy_read_endpoint ? 1 : 0

  db_proxy_name          = aws_db_proxy.main[0].name
  db_proxy_endpoint_name = "${var.name_prefix}-proxy-ro"
  vpc_subnet_ids         = var.private_subnet_ids
  vpc_security_group_ids = [var.rds_proxy_security_group_id]
  target_role            = "READ_ONLY"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rds-proxy-read-only"
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms for RDS Proxy
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "rds_proxy_connections" {
  count = var.enable_rds_proxy ? 1 : 0

  alarm_name          = "${var.name_prefix}-rds-proxy-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ClientConnections"
  namespace           = "AWS/RDSProxy"
  period              = 300
  statistic           = "Average"
  threshold           = 80 # Alert at 80 connections (adjust via variable if needed)

  dimensions = {
    ProxyName = aws_db_proxy.main[0].name
  }

  alarm_description = "RDS Proxy client connections exceeding threshold"
  alarm_actions     = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rds-proxy-connections-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "rds_proxy_no_tls" {
  count = var.enable_rds_proxy ? 1 : 0

  alarm_name          = "${var.name_prefix}-rds-proxy-client-connections-no-tls"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ClientConnectionsNoTLS"
  namespace           = "AWS/RDSProxy"
  period              = 60
  statistic           = "Sum"
  threshold           = 0

  dimensions = {
    ProxyName = aws_db_proxy.main[0].name
  }

  alarm_description = "RDS Proxy receiving non-TLS connections (should be 0)"
  alarm_actions     = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rds-proxy-no-tls-alarm"
  })
}
