# =============================================================================
# Security Groups Module - ALB, Liberty, ECS, Database, Cache
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

resource "aws_security_group_rule" "liberty_egress" {
  count = var.create_liberty_sg ? 1 : 0

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

resource "aws_security_group_rule" "ecs_egress" {
  count = var.create_ecs_sg ? 1 : 0

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
