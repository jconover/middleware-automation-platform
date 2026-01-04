# =============================================================================
# Security Groups Module - ALB, Liberty, ECS, Database, Cache, Monitoring,
#                          Management, Bastion, RDS Proxy
# =============================================================================

# -----------------------------------------------------------------------------
# ALB Security Group
# -----------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-alb-sg"
  })
}

resource "aws_security_group_rule" "alb_http" {
  type              = "ingress"
  description       = "HTTP from anywhere"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "alb_https" {
  type              = "ingress"
  description       = "HTTPS from anywhere"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "alb_egress" {
  type              = "egress"
  description       = "All outbound traffic"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
}

# -----------------------------------------------------------------------------
# Liberty EC2 Security Group
# -----------------------------------------------------------------------------
resource "aws_security_group" "liberty" {
  count = var.create_liberty_sg ? 1 : 0

  name        = "${var.name_prefix}-liberty-sg"
  description = "Security group for Liberty EC2 instances"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-liberty-sg"
  })
}

resource "aws_security_group_rule" "liberty_http_from_alb" {
  count = var.create_liberty_sg ? 1 : 0

  type                     = "ingress"
  description              = "HTTP from ALB"
  from_port                = 9080
  to_port                  = 9080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.liberty[0].id
}

resource "aws_security_group_rule" "liberty_https_from_alb" {
  count = var.create_liberty_sg ? 1 : 0

  type                     = "ingress"
  description              = "HTTPS from ALB"
  from_port                = 9443
  to_port                  = 9443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.liberty[0].id
}

resource "aws_security_group_rule" "liberty_ssh" {
  count = var.create_liberty_sg ? 1 : 0

  type              = "ingress"
  description       = "SSH from VPC"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.liberty[0].id
}

# Metrics scraping from monitoring server
resource "aws_security_group_rule" "liberty_metrics_from_monitoring" {
  count = var.create_liberty_sg && var.create_monitoring_sg ? 1 : 0

  type                     = "ingress"
  description              = "Metrics scraping from Prometheus"
  from_port                = 9080
  to_port                  = 9080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.monitoring[0].id
  security_group_id        = aws_security_group.liberty[0].id
}

# -----------------------------------------------------------------------------
# Liberty EC2 Egress Rules (Restricted)
# -----------------------------------------------------------------------------
resource "aws_security_group_rule" "liberty_egress_https" {
  count = var.create_liberty_sg && var.restrict_egress ? 1 : 0

  type              = "egress"
  description       = "HTTPS to internet (ECR, APIs)"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.liberty[0].id
}

resource "aws_security_group_rule" "liberty_egress_db" {
  count = var.create_liberty_sg && var.restrict_egress ? 1 : 0

  type                     = "egress"
  description              = "PostgreSQL to database"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.db.id
  security_group_id        = aws_security_group.liberty[0].id
}

resource "aws_security_group_rule" "liberty_egress_cache" {
  count = var.create_liberty_sg && var.restrict_egress ? 1 : 0

  type                     = "egress"
  description              = "Redis to cache"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.cache.id
  security_group_id        = aws_security_group.liberty[0].id
}

# Legacy unrestricted egress (backward compatibility)
resource "aws_security_group_rule" "liberty_egress" {
  count = var.create_liberty_sg && !var.restrict_egress ? 1 : 0

  type              = "egress"
  description       = "All outbound traffic"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.liberty[0].id
}

# -----------------------------------------------------------------------------
# ECS Security Group
# -----------------------------------------------------------------------------
resource "aws_security_group" "ecs" {
  count = var.create_ecs_sg ? 1 : 0

  name        = "${var.name_prefix}-ecs-liberty-sg"
  description = "Security group for ECS Liberty tasks"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-ecs-liberty-sg"
  })
}

resource "aws_security_group_rule" "ecs_http_from_alb" {
  count = var.create_ecs_sg ? 1 : 0

  type                     = "ingress"
  description              = "HTTP from ALB"
  from_port                = 9080
  to_port                  = 9080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.ecs[0].id
}

resource "aws_security_group_rule" "ecs_https_from_alb" {
  count = var.create_ecs_sg ? 1 : 0

  type                     = "ingress"
  description              = "HTTPS from ALB"
  from_port                = 9443
  to_port                  = 9443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.ecs[0].id
}

# Metrics scraping from monitoring server
resource "aws_security_group_rule" "ecs_metrics_from_monitoring" {
  count = var.create_ecs_sg && var.create_monitoring_sg ? 1 : 0

  type                     = "ingress"
  description              = "Metrics scraping from Prometheus"
  from_port                = 9080
  to_port                  = 9080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.monitoring[0].id
  security_group_id        = aws_security_group.ecs[0].id
}

# -----------------------------------------------------------------------------
# ECS Egress Rules (Restricted)
# -----------------------------------------------------------------------------
resource "aws_security_group_rule" "ecs_egress_https" {
  count = var.create_ecs_sg && var.restrict_egress ? 1 : 0

  type              = "egress"
  description       = "HTTPS to internet (ECR, APIs, Secrets Manager)"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ecs[0].id
}

resource "aws_security_group_rule" "ecs_egress_db" {
  count = var.create_ecs_sg && var.restrict_egress ? 1 : 0

  type                     = "egress"
  description              = "PostgreSQL to database"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.db.id
  security_group_id        = aws_security_group.ecs[0].id
}

resource "aws_security_group_rule" "ecs_egress_cache" {
  count = var.create_ecs_sg && var.restrict_egress ? 1 : 0

  type                     = "egress"
  description              = "Redis to cache"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.cache.id
  security_group_id        = aws_security_group.ecs[0].id
}

# Legacy unrestricted egress (backward compatibility)
resource "aws_security_group_rule" "ecs_egress" {
  count = var.create_ecs_sg && !var.restrict_egress ? 1 : 0

  type              = "egress"
  description       = "All outbound traffic"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ecs[0].id
}

# -----------------------------------------------------------------------------
# Database Security Group
# -----------------------------------------------------------------------------
resource "aws_security_group" "db" {
  name        = "${var.name_prefix}-db-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-db-sg"
  })
}

resource "aws_security_group_rule" "db_from_liberty" {
  count = var.create_liberty_sg ? 1 : 0

  type                     = "ingress"
  description              = "PostgreSQL from Liberty EC2"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.liberty[0].id
  security_group_id        = aws_security_group.db.id
}

resource "aws_security_group_rule" "db_from_ecs" {
  count = var.create_ecs_sg ? 1 : 0

  type                     = "ingress"
  description              = "PostgreSQL from ECS"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs[0].id
  security_group_id        = aws_security_group.db.id
}

resource "aws_security_group_rule" "db_from_monitoring" {
  count = var.create_monitoring_sg ? 1 : 0

  type                     = "ingress"
  description              = "PostgreSQL from monitoring (Grafana dashboards)"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.monitoring[0].id
  security_group_id        = aws_security_group.db.id
}

resource "aws_security_group_rule" "db_from_rds_proxy" {
  count = var.create_rds_proxy_sg ? 1 : 0

  type                     = "ingress"
  description              = "PostgreSQL from RDS Proxy"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rds_proxy[0].id
  security_group_id        = aws_security_group.db.id
}

# -----------------------------------------------------------------------------
# Cache Security Group
# -----------------------------------------------------------------------------
resource "aws_security_group" "cache" {
  name        = "${var.name_prefix}-cache-sg"
  description = "Security group for ElastiCache Redis"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-cache-sg"
  })
}

resource "aws_security_group_rule" "cache_from_liberty" {
  count = var.create_liberty_sg ? 1 : 0

  type                     = "ingress"
  description              = "Redis from Liberty EC2"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.liberty[0].id
  security_group_id        = aws_security_group.cache.id
}

resource "aws_security_group_rule" "cache_from_ecs" {
  count = var.create_ecs_sg ? 1 : 0

  type                     = "ingress"
  description              = "Redis from ECS"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs[0].id
  security_group_id        = aws_security_group.cache.id
}

resource "aws_security_group_rule" "cache_from_monitoring" {
  count = var.create_monitoring_sg ? 1 : 0

  type                     = "ingress"
  description              = "Redis from monitoring (Grafana dashboards)"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.monitoring[0].id
  security_group_id        = aws_security_group.cache.id
}

# =============================================================================
# Monitoring Security Group (Prometheus/Grafana)
# =============================================================================
resource "aws_security_group" "monitoring" {
  count = var.create_monitoring_sg ? 1 : 0

  name        = "${var.name_prefix}-monitoring-sg"
  description = "Security group for Prometheus/Grafana monitoring server"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-monitoring-sg"
  })
}

# -----------------------------------------------------------------------------
# Monitoring Ingress Rules
# -----------------------------------------------------------------------------
resource "aws_security_group_rule" "monitoring_ssh" {
  count = var.create_monitoring_sg ? 1 : 0

  type              = "ingress"
  description       = "SSH from allowed CIDRs"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.monitoring_allowed_cidrs
  security_group_id = aws_security_group.monitoring[0].id
}

resource "aws_security_group_rule" "monitoring_prometheus" {
  count = var.create_monitoring_sg ? 1 : 0

  type              = "ingress"
  description       = "Prometheus UI from allowed CIDRs"
  from_port         = 9090
  to_port           = 9090
  protocol          = "tcp"
  cidr_blocks       = var.monitoring_allowed_cidrs
  security_group_id = aws_security_group.monitoring[0].id
}

resource "aws_security_group_rule" "monitoring_grafana" {
  count = var.create_monitoring_sg ? 1 : 0

  type              = "ingress"
  description       = "Grafana UI from allowed CIDRs"
  from_port         = 3000
  to_port           = 3000
  protocol          = "tcp"
  cidr_blocks       = var.monitoring_allowed_cidrs
  security_group_id = aws_security_group.monitoring[0].id
}

resource "aws_security_group_rule" "monitoring_alertmanager" {
  count = var.create_monitoring_sg ? 1 : 0

  type              = "ingress"
  description       = "AlertManager UI from allowed CIDRs"
  from_port         = 9093
  to_port           = 9093
  protocol          = "tcp"
  cidr_blocks       = var.monitoring_allowed_cidrs
  security_group_id = aws_security_group.monitoring[0].id
}

resource "aws_security_group_rule" "monitoring_http_internal" {
  count = var.create_monitoring_sg ? 1 : 0

  type              = "ingress"
  description       = "HTTP from VPC (internal access)"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.monitoring[0].id
}

resource "aws_security_group_rule" "monitoring_https_internal" {
  count = var.create_monitoring_sg ? 1 : 0

  type              = "ingress"
  description       = "HTTPS from VPC (internal access)"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.monitoring[0].id
}

# -----------------------------------------------------------------------------
# Monitoring Egress Rules
# -----------------------------------------------------------------------------
resource "aws_security_group_rule" "monitoring_egress_https" {
  count = var.create_monitoring_sg ? 1 : 0

  type              = "egress"
  description       = "HTTPS to internet (AWS APIs, package updates)"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.monitoring[0].id
}

resource "aws_security_group_rule" "monitoring_egress_http" {
  count = var.create_monitoring_sg ? 1 : 0

  type              = "egress"
  description       = "HTTP to internet (package updates)"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.monitoring[0].id
}

resource "aws_security_group_rule" "monitoring_egress_db" {
  count = var.create_monitoring_sg ? 1 : 0

  type                     = "egress"
  description              = "PostgreSQL to database (Grafana dashboards)"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.db.id
  security_group_id        = aws_security_group.monitoring[0].id
}

resource "aws_security_group_rule" "monitoring_egress_cache" {
  count = var.create_monitoring_sg ? 1 : 0

  type                     = "egress"
  description              = "Redis to cache (Grafana dashboards)"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.cache.id
  security_group_id        = aws_security_group.monitoring[0].id
}

resource "aws_security_group_rule" "monitoring_egress_liberty_metrics" {
  count = var.create_monitoring_sg && var.create_liberty_sg ? 1 : 0

  type                     = "egress"
  description              = "Metrics scraping to Liberty EC2"
  from_port                = 9080
  to_port                  = 9080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.liberty[0].id
  security_group_id        = aws_security_group.monitoring[0].id
}

resource "aws_security_group_rule" "monitoring_egress_ecs_metrics" {
  count = var.create_monitoring_sg && var.create_ecs_sg ? 1 : 0

  type                     = "egress"
  description              = "Metrics scraping to ECS tasks"
  from_port                = 9080
  to_port                  = 9080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs[0].id
  security_group_id        = aws_security_group.monitoring[0].id
}

# =============================================================================
# Management Security Group (AWX/Jenkins)
# =============================================================================
resource "aws_security_group" "management" {
  count = var.create_management_sg ? 1 : 0

  name        = "${var.name_prefix}-management-sg"
  description = "Security group for AWX/Jenkins management server"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-management-sg"
  })
}

# -----------------------------------------------------------------------------
# Management Ingress Rules
# -----------------------------------------------------------------------------
resource "aws_security_group_rule" "management_ssh" {
  count = var.create_management_sg ? 1 : 0

  type              = "ingress"
  description       = "SSH from allowed CIDRs"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.management_allowed_cidrs
  security_group_id = aws_security_group.management[0].id
}

resource "aws_security_group_rule" "management_http" {
  count = var.create_management_sg ? 1 : 0

  type              = "ingress"
  description       = "HTTP from allowed CIDRs"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = var.management_allowed_cidrs
  security_group_id = aws_security_group.management[0].id
}

resource "aws_security_group_rule" "management_https" {
  count = var.create_management_sg ? 1 : 0

  type              = "ingress"
  description       = "HTTPS from allowed CIDRs"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = var.management_allowed_cidrs
  security_group_id = aws_security_group.management[0].id
}

resource "aws_security_group_rule" "management_awx" {
  count = var.create_management_sg ? 1 : 0

  type              = "ingress"
  description       = "AWX web UI from allowed CIDRs"
  from_port         = 8052
  to_port           = 8052
  protocol          = "tcp"
  cidr_blocks       = var.management_allowed_cidrs
  security_group_id = aws_security_group.management[0].id
}

# -----------------------------------------------------------------------------
# Management Egress Rules
# -----------------------------------------------------------------------------
resource "aws_security_group_rule" "management_egress_vpc" {
  count = var.create_management_sg ? 1 : 0

  type              = "egress"
  description       = "All traffic to VPC (Ansible/deployment)"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.management[0].id
}

resource "aws_security_group_rule" "management_egress_https" {
  count = var.create_management_sg ? 1 : 0

  type              = "egress"
  description       = "HTTPS to internet (Git, package updates, APIs)"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.management[0].id
}

resource "aws_security_group_rule" "management_egress_http" {
  count = var.create_management_sg ? 1 : 0

  type              = "egress"
  description       = "HTTP to internet (package updates)"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.management[0].id
}

# =============================================================================
# Bastion Security Group (Optional)
# =============================================================================
resource "aws_security_group" "bastion" {
  count = var.create_bastion_sg ? 1 : 0

  name        = "${var.name_prefix}-bastion-sg"
  description = "Security group for bastion host"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-bastion-sg"
  })
}

# -----------------------------------------------------------------------------
# Bastion Ingress Rules
# -----------------------------------------------------------------------------
resource "aws_security_group_rule" "bastion_ssh" {
  count = var.create_bastion_sg ? 1 : 0

  type              = "ingress"
  description       = "SSH from allowed CIDRs only"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.bastion_allowed_cidrs
  security_group_id = aws_security_group.bastion[0].id
}

# -----------------------------------------------------------------------------
# Bastion Egress Rules
# -----------------------------------------------------------------------------
resource "aws_security_group_rule" "bastion_egress_ssh_vpc" {
  count = var.create_bastion_sg ? 1 : 0

  type              = "egress"
  description       = "SSH to VPC instances"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.bastion[0].id
}

resource "aws_security_group_rule" "bastion_egress_https" {
  count = var.create_bastion_sg ? 1 : 0

  type              = "egress"
  description       = "HTTPS to internet (package updates)"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.bastion[0].id
}

resource "aws_security_group_rule" "bastion_egress_http" {
  count = var.create_bastion_sg ? 1 : 0

  type              = "egress"
  description       = "HTTP to internet (package updates)"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.bastion[0].id
}

# =============================================================================
# RDS Proxy Security Group (Optional)
# =============================================================================
resource "aws_security_group" "rds_proxy" {
  count = var.create_rds_proxy_sg ? 1 : 0

  name        = "${var.name_prefix}-rds-proxy-sg"
  description = "Security group for RDS Proxy"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rds-proxy-sg"
  })
}

# -----------------------------------------------------------------------------
# RDS Proxy Ingress Rules
# -----------------------------------------------------------------------------
resource "aws_security_group_rule" "rds_proxy_from_liberty" {
  count = var.create_rds_proxy_sg && var.create_liberty_sg ? 1 : 0

  type                     = "ingress"
  description              = "PostgreSQL from Liberty EC2"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.liberty[0].id
  security_group_id        = aws_security_group.rds_proxy[0].id
}

resource "aws_security_group_rule" "rds_proxy_from_ecs" {
  count = var.create_rds_proxy_sg && var.create_ecs_sg ? 1 : 0

  type                     = "ingress"
  description              = "PostgreSQL from ECS"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs[0].id
  security_group_id        = aws_security_group.rds_proxy[0].id
}

# -----------------------------------------------------------------------------
# RDS Proxy Egress Rules
# -----------------------------------------------------------------------------
resource "aws_security_group_rule" "rds_proxy_egress_db" {
  count = var.create_rds_proxy_sg ? 1 : 0

  type                     = "egress"
  description              = "PostgreSQL to RDS"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.db.id
  security_group_id        = aws_security_group.rds_proxy[0].id
}

# =============================================================================
# Cross-SG Rules: Allow bastion SSH to other instances
# =============================================================================
resource "aws_security_group_rule" "liberty_ssh_from_bastion" {
  count = var.create_liberty_sg && var.create_bastion_sg ? 1 : 0

  type                     = "ingress"
  description              = "SSH from bastion"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion[0].id
  security_group_id        = aws_security_group.liberty[0].id
}

resource "aws_security_group_rule" "monitoring_ssh_from_bastion" {
  count = var.create_monitoring_sg && var.create_bastion_sg ? 1 : 0

  type                     = "ingress"
  description              = "SSH from bastion"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion[0].id
  security_group_id        = aws_security_group.monitoring[0].id
}

resource "aws_security_group_rule" "management_ssh_from_bastion" {
  count = var.create_management_sg && var.create_bastion_sg ? 1 : 0

  type                     = "ingress"
  description              = "SSH from bastion"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion[0].id
  security_group_id        = aws_security_group.management[0].id
}
