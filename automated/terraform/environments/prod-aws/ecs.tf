# =============================================================================
# ECS Fargate - Cluster, Task Definition, and Service
# =============================================================================
# Variables are defined in variables.tf with validation

# -----------------------------------------------------------------------------
# CloudWatch Log Group
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "ecs_liberty" {
  name              = "/ecs/${local.name_prefix}-liberty"
  retention_in_days = 30

  tags = {
    Name = "${local.name_prefix}-ecs-liberty-logs"
  }
}

# -----------------------------------------------------------------------------
# ECS Cluster
# -----------------------------------------------------------------------------
resource "aws_ecs_cluster" "main" {
  count = var.ecs_enabled ? 1 : 0

  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${local.name_prefix}-cluster"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  count = var.ecs_enabled ? 1 : 0

  cluster_name       = aws_ecs_cluster.main[0].name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  # Baseline tasks run on FARGATE (on-demand) for reliability
  default_capacity_provider_strategy {
    base              = var.ecs_min_capacity
    weight            = 100 - var.fargate_spot_weight
    capacity_provider = "FARGATE"
  }

  # Tasks above baseline use FARGATE_SPOT for cost savings (up to 70% cheaper)
  # Spot tasks may be interrupted with 2-minute warning when AWS needs capacity
  dynamic "default_capacity_provider_strategy" {
    for_each = var.fargate_spot_weight > 0 ? [1] : []
    content {
      base              = 0
      weight            = var.fargate_spot_weight
      capacity_provider = "FARGATE_SPOT"
    }
  }
}

# -----------------------------------------------------------------------------
# ECS Task Definition
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "liberty" {
  count = var.ecs_enabled ? 1 : 0

  family                   = "${local.name_prefix}-liberty"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name  = "liberty"
      image = "${aws_ecr_repository.liberty.repository_url}:${var.container_image_tag}"

      portMappings = [
        {
          containerPort = 9080
          protocol      = "tcp"
        },
        {
          containerPort = 9443
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "DB_HOST", value = aws_db_instance.main.address },
        { name = "DB_PORT", value = tostring(aws_db_instance.main.port) },
        { name = "DB_NAME", value = var.db_name },
        { name = "REDIS_HOST", value = aws_elasticache_replication_group.main.primary_endpoint_address },
        { name = "REDIS_PORT", value = "6379" }
      ]

      secrets = [
        {
          name      = "DB_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:password::"
        },
        {
          name      = "DB_USERNAME"
          valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:username::"
        }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:9080/health/ready || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_liberty.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "liberty"
        }
      }

      essential = true
    }
  ])

  tags = {
    Name = "${local.name_prefix}-liberty-task"
  }
}

# -----------------------------------------------------------------------------
# ECS Service
# -----------------------------------------------------------------------------
resource "aws_ecs_service" "liberty" {
  count = var.ecs_enabled ? 1 : 0

  name            = "${local.name_prefix}-liberty"
  cluster         = aws_ecs_cluster.main[0].id
  task_definition = aws_ecs_task_definition.liberty[0].arn
  desired_count   = var.ecs_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_liberty.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.liberty_ecs[0].arn
    container_name   = "liberty"
    container_port   = 9080
  }

  # Circuit breaker only available with ECS deployment controller (not CODE_DEPLOY)
  dynamic "deployment_circuit_breaker" {
    for_each = var.enable_blue_green ? [] : [1]
    content {
      enable   = true
      rollback = true
    }
  }

  deployment_controller {
    # Use CODE_DEPLOY for Blue-Green deployments, otherwise standard ECS rolling updates
    type = var.enable_blue_green ? "CODE_DEPLOY" : "ECS"
  }

  # Allow external changes to desired_count (for auto-scaling)
  # When using CodeDeploy (Blue-Green), also ignore task_definition and load_balancer
  # as CodeDeploy manages these during deployments
  lifecycle {
    ignore_changes = [desired_count, task_definition, load_balancer]
  }

  # Enable ECS Exec for debugging
  enable_execute_command = true

  tags = {
    Name = "${local.name_prefix}-liberty-service"
  }

  depends_on = [aws_lb_listener_rule.ecs_liberty]
}

# -----------------------------------------------------------------------------
# ECS Security Group
# -----------------------------------------------------------------------------
resource "aws_security_group" "ecs_liberty" {
  name        = "${local.name_prefix}-ecs-liberty-sg"
  description = "Security group for ECS Liberty tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 9080
    to_port         = 9080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "HTTPS from ALB"
    from_port       = 9443
    to_port         = 9443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Least-privilege egress rules (HTTPS inline, DB/Cache via aws_security_group_rule to avoid cycles)
  egress {
    description = "HTTPS to external APIs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-ecs-liberty-sg"
  }
}

# -----------------------------------------------------------------------------
# ECS Liberty Egress Rules (separate to avoid dependency cycles)
# -----------------------------------------------------------------------------
resource "aws_security_group_rule" "ecs_liberty_egress_to_db" {
  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ecs_liberty.id
  source_security_group_id = aws_security_group.db.id
  description              = "PostgreSQL to RDS"
}

resource "aws_security_group_rule" "ecs_liberty_egress_to_cache" {
  type                     = "egress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ecs_liberty.id
  source_security_group_id = aws_security_group.cache.id
  description              = "Redis to ElastiCache"
}

# -----------------------------------------------------------------------------
# Allow ECS tasks to access RDS and Redis (ingress rules)
# -----------------------------------------------------------------------------
resource "aws_security_group_rule" "db_from_ecs" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = aws_security_group.ecs_liberty.id
  description              = "PostgreSQL from ECS Liberty tasks"
}

resource "aws_security_group_rule" "cache_from_ecs" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cache.id
  source_security_group_id = aws_security_group.ecs_liberty.id
  description              = "Redis from ECS Liberty tasks"
}

# -----------------------------------------------------------------------------
# Allow monitoring server to scrape ECS task metrics
# -----------------------------------------------------------------------------
resource "aws_security_group_rule" "ecs_metrics_from_monitoring" {
  count = var.create_monitoring_server ? 1 : 0

  type                     = "ingress"
  from_port                = 9080
  to_port                  = 9080
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ecs_liberty.id
  source_security_group_id = aws_security_group.monitoring[0].id
  description              = "Liberty metrics from monitoring server (Prometheus ECS SD)"
}

# -----------------------------------------------------------------------------
# ECS Target Group (for ALB)
# -----------------------------------------------------------------------------
resource "aws_lb_target_group" "liberty_ecs" {
  count = var.ecs_enabled ? 1 : 0

  name        = "${local.name_prefix}-liberty-ecs-tg"
  port        = 9080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip" # Required for Fargate

  health_check {
    enabled             = true
    path                = "/health/ready"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = true
  }

  tags = {
    Name = "${local.name_prefix}-liberty-ecs-tg"
  }
}

# -----------------------------------------------------------------------------
# ALB Listener Rule for EC2 Rollback (routes to EC2 when X-Target: ec2 header)
# Default traffic now goes to ECS. Use this header to test EC2 instances.
# -----------------------------------------------------------------------------
resource "aws_lb_listener_rule" "ecs_liberty" {
  count = var.ecs_enabled ? 1 : 0

  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.liberty.arn
  }

  # Route to EC2 when header X-Target: ec2 is present (for rollback/testing)
  condition {
    http_header {
      http_header_name = "X-Target"
      values           = ["ec2"]
    }
  }

  tags = {
    Name = "${local.name_prefix}-ec2-rollback-rule"
  }
}
