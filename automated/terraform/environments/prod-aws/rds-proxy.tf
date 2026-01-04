# =============================================================================
# RDS Proxy - Connection Pooling and IAM Authentication
# =============================================================================
# Provides connection pooling and IAM authentication for PostgreSQL.
# Benefits:
#   - Connection pooling reduces database load from Lambda/Fargate
#   - IAM authentication eliminates password management
#   - Automatic failover handling improves availability
#   - Connection multiplexing improves scalability
# =============================================================================

# -----------------------------------------------------------------------------
# RDS Proxy
# -----------------------------------------------------------------------------
resource "aws_db_proxy" "main" {
  count = var.enable_rds_proxy ? 1 : 0

  name                   = "${local.name_prefix}-rds-proxy"
  engine_family          = "POSTGRESQL"
  role_arn               = aws_iam_role.rds_proxy[0].arn
  vpc_subnet_ids         = module.networking.private_subnet_ids
  vpc_security_group_ids = [aws_security_group.rds_proxy[0].id]

  auth {
    auth_scheme               = "SECRETS"
    iam_auth                  = var.rds_proxy_require_iam ? "REQUIRED" : "DISABLED"
    secret_arn                = aws_secretsmanager_secret.db_credentials.arn
    client_password_auth_type = "POSTGRES_SCRAM_SHA_256"
  }

  require_tls         = true
  idle_client_timeout = var.rds_proxy_idle_timeout
  debug_logging       = false

  tags = {
    Name = "${local.name_prefix}-rds-proxy"
  }
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
  db_proxy_endpoint_name = "${local.name_prefix}-proxy-ro"
  vpc_subnet_ids         = module.networking.private_subnet_ids
  vpc_security_group_ids = [aws_security_group.rds_proxy[0].id]
  target_role            = "READ_ONLY"

  tags = {
    Name = "${local.name_prefix}-rds-proxy-read-only"
  }
}

# -----------------------------------------------------------------------------
# RDS Proxy Security Group
# -----------------------------------------------------------------------------
resource "aws_security_group" "rds_proxy" {
  count = var.enable_rds_proxy ? 1 : 0

  name        = "${local.name_prefix}-rds-proxy-sg"
  description = "Security group for RDS Proxy"
  vpc_id      = module.networking.vpc_id

  # Allow PostgreSQL from ECS tasks
  ingress {
    description     = "PostgreSQL from ECS Liberty tasks"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_liberty.id]
  }

  # Allow PostgreSQL from EC2 Liberty instances (if enabled)
  dynamic "ingress" {
    for_each = var.liberty_instance_count > 0 ? [1] : []
    content {
      description     = "PostgreSQL from EC2 Liberty instances"
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = [aws_security_group.liberty.id]
    }
  }

  # Egress to RDS
  egress {
    description     = "PostgreSQL to RDS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.db.id]
  }

  tags = {
    Name = "${local.name_prefix}-rds-proxy-sg"
  }
}

# -----------------------------------------------------------------------------
# Allow RDS Proxy to connect to RDS (Ingress rule on DB security group)
# -----------------------------------------------------------------------------
resource "aws_security_group_rule" "db_from_rds_proxy" {
  count = var.enable_rds_proxy ? 1 : 0

  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = aws_security_group.rds_proxy[0].id
  description              = "PostgreSQL from RDS Proxy"
}

# -----------------------------------------------------------------------------
# Update ECS egress to allow RDS Proxy connections
# -----------------------------------------------------------------------------
resource "aws_security_group_rule" "ecs_liberty_egress_to_rds_proxy" {
  count = var.enable_rds_proxy ? 1 : 0

  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ecs_liberty.id
  source_security_group_id = aws_security_group.rds_proxy[0].id
  description              = "PostgreSQL to RDS Proxy"
}

# -----------------------------------------------------------------------------
# Update EC2 Liberty egress to allow RDS Proxy connections (if EC2 enabled)
# -----------------------------------------------------------------------------
resource "aws_security_group_rule" "liberty_egress_to_rds_proxy" {
  count = var.enable_rds_proxy && var.liberty_instance_count > 0 ? 1 : 0

  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.liberty.id
  source_security_group_id = aws_security_group.rds_proxy[0].id
  description              = "PostgreSQL to RDS Proxy"
}

# -----------------------------------------------------------------------------
# IAM Role for RDS Proxy (to access Secrets Manager)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "rds_proxy" {
  count = var.enable_rds_proxy ? 1 : 0

  name = "${local.name_prefix}-rds-proxy-role"

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

  tags = {
    Name = "${local.name_prefix}-rds-proxy-role"
  }
}

# -----------------------------------------------------------------------------
# IAM Policy for RDS Proxy (Secrets Manager Access)
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "rds_proxy_secrets" {
  count = var.enable_rds_proxy ? 1 : 0

  name = "${local.name_prefix}-rds-proxy-secrets"
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
# IAM Policy for ECS Tasks to use IAM Authentication with RDS Proxy
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "ecs_task_rds_proxy_connect" {
  count = var.enable_rds_proxy && var.rds_proxy_require_iam ? 1 : 0

  name = "${local.name_prefix}-ecs-rds-proxy-connect"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RDSProxyConnect"
        Effect = "Allow"
        Action = [
          "rds-db:connect"
        ]
        Resource = [
          "arn:aws:rds-db:${var.aws_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_db_proxy.main[0].id}/${var.db_username}"
        ]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms for RDS Proxy
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "rds_proxy_connections" {
  count = var.enable_rds_proxy ? 1 : 0

  alarm_name          = "${local.name_prefix}-rds-proxy-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.rds_proxy_max_connections_percent * 0.8

  dimensions = {
    DBProxyName = aws_db_proxy.main[0].name
  }

  alarm_description = "RDS Proxy connections approaching limit"
  alarm_actions     = []

  tags = {
    Name = "${local.name_prefix}-rds-proxy-connections-alarm"
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_proxy_client_connections_exceeded" {
  count = var.enable_rds_proxy ? 1 : 0

  alarm_name          = "${local.name_prefix}-rds-proxy-client-connections-exceeded"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ClientConnectionsNoTls"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0

  dimensions = {
    DBProxyName = aws_db_proxy.main[0].name
  }

  alarm_description = "RDS Proxy receiving non-TLS connections (should be 0)"
  alarm_actions     = []

  tags = {
    Name = "${local.name_prefix}-rds-proxy-no-tls-alarm"
  }
}
