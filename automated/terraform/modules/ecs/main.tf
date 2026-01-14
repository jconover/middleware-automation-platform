# =============================================================================
# ECS Module - Cluster, Task Definition, Service, ECR
# =============================================================================

# -----------------------------------------------------------------------------
# CloudWatch Log Group
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.name_prefix}-liberty"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-ecs-liberty-logs"
  })
}

# -----------------------------------------------------------------------------
# ECS Cluster
# -----------------------------------------------------------------------------
resource "aws_ecs_cluster" "main" {
  name = "${var.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-cluster"
  })
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  # Baseline tasks run on FARGATE (on-demand) for reliability
  default_capacity_provider_strategy {
    base              = var.min_capacity
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
# Task Execution Role (for ECS agent)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "ecs_execution" {
  name = "${var.name_prefix}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-ecs-execution-role"
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_execution_secrets" {
  count = length(var.secrets_arns) > 0 ? 1 : 0

  name = "${var.name_prefix}-ecs-execution-secrets"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = var.secrets_arns
    }]
  })
}

# -----------------------------------------------------------------------------
# Task Role (for application container)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "ecs_task" {
  name = "${var.name_prefix}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-ecs-task-role"
  })
}

resource "aws_iam_role_policy" "ecs_task" {
  name = "${var.name_prefix}-ecs-task-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.ecs.arn}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Task Definition
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "main" {
  family                   = "${var.name_prefix}-liberty"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name  = var.container_name
      image = var.container_image

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

      environment = concat(
        var.environment_variables,
        # OpenTelemetry Configuration for Distributed Tracing
        var.enable_xray || var.otel_collector_endpoint != "" ? [
          { name = "OTEL_SERVICE_NAME", value = var.otel_service_name },
          { name = "OTEL_RESOURCE_ATTRIBUTES", value = "service.namespace=middleware-platform,deployment.environment=${var.otel_environment}" },
          { name = "OTEL_TRACES_EXPORTER", value = var.enable_xray ? "xray" : "otlp" },
          { name = "OTEL_EXPORTER_OTLP_ENDPOINT", value = var.enable_xray ? "http://localhost:2000" : var.otel_collector_endpoint },
          { name = "OTEL_PROPAGATORS", value = "tracecontext,baggage,xray" },
          { name = "OTEL_METRICS_EXPORTER", value = "none" },
          { name = "OTEL_LOGS_EXPORTER", value = "none" }
        ] : []
      )
      secrets = var.secrets

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
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = var.container_name
        }
      }

      essential = true
    }
  ])

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-liberty-task"
  })
}

# -----------------------------------------------------------------------------
# ECS Service
# -----------------------------------------------------------------------------
resource "aws_ecs_service" "main" {
  name            = "${var.name_prefix}-liberty"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = var.desired_count
  # Note: launch_type removed - using cluster default capacity providers (FARGATE + FARGATE_SPOT)

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = var.target_group_arn != null ? [1] : []
    content {
      target_group_arn = var.target_group_arn
      container_name   = var.container_name
      container_port   = 9080
    }
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
  # Note: When using CodeDeploy (Blue-Green), task_definition and load_balancer
  # are also managed externally. We always ignore these for simplicity.
  lifecycle {
    ignore_changes = [desired_count, task_definition, load_balancer]
  }

  enable_execute_command = var.enable_execute_command

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-liberty-service"
  })
}

# -----------------------------------------------------------------------------
# ECR Repository
# -----------------------------------------------------------------------------
resource "aws_ecr_repository" "main" {
  count = var.create_ecr_repository ? 1 : 0

  name                 = "${var.name_prefix}-liberty"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-liberty"
  })
}

resource "aws_ecr_lifecycle_policy" "main" {
  count = var.create_ecr_repository ? 1 : 0

  repository = aws_ecr_repository.main[0].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# ECR Cross-Region Replication Configuration
# -----------------------------------------------------------------------------
data "aws_caller_identity" "current" {
  count = var.ecr_replication_enabled ? 1 : 0
}

resource "aws_ecr_replication_configuration" "cross_region" {
  count = var.ecr_replication_enabled ? 1 : 0

  replication_configuration {
    rule {
      destination {
        region      = var.ecr_replication_region
        registry_id = data.aws_caller_identity.current[0].account_id
      }
      repository_filter {
        filter      = var.name_prefix
        filter_type = "PREFIX_MATCH"
      }
    }
  }
}

# =============================================================================
# Auto-Scaling Resources
# =============================================================================

# -----------------------------------------------------------------------------
# Auto Scaling Target
# -----------------------------------------------------------------------------
resource "aws_appautoscaling_target" "ecs" {
  count = var.enable_autoscaling ? 1 : 0

  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.main.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# -----------------------------------------------------------------------------
# CPU-based Scaling Policy
# -----------------------------------------------------------------------------
resource "aws_appautoscaling_policy" "cpu" {
  count = var.enable_autoscaling ? 1 : 0

  name               = "${var.name_prefix}-liberty-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.cpu_target
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
  }
}

# -----------------------------------------------------------------------------
# Memory-based Scaling Policy
# -----------------------------------------------------------------------------
resource "aws_appautoscaling_policy" "memory" {
  count = var.enable_autoscaling ? 1 : 0

  name               = "${var.name_prefix}-liberty-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = var.memory_target
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
  }
}

# -----------------------------------------------------------------------------
# Request Count Scaling Policy (based on ALB requests)
# -----------------------------------------------------------------------------
resource "aws_appautoscaling_policy" "requests" {
  count = var.enable_autoscaling && var.enable_request_scaling ? 1 : 0

  name               = "${var.name_prefix}-liberty-request-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${var.alb_arn_suffix}/${local.target_group_arn_suffix}"
    }
    target_value       = var.request_count_target
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
  }
}

# Local to extract target group ARN suffix for request count scaling
locals {
  # Extract ARN suffix from target group ARN (e.g., "targetgroup/my-tg/1234567890")
  target_group_arn_suffix = var.target_group_arn != null ? element(split(":", var.target_group_arn), length(split(":", var.target_group_arn)) - 1) : ""
}

# =============================================================================
# Blue-Green Deployment Resources (CodeDeploy)
# =============================================================================

# -----------------------------------------------------------------------------
# Green Target Group (for Blue-Green deployments)
# -----------------------------------------------------------------------------
resource "aws_lb_target_group" "green" {
  count = var.enable_blue_green ? 1 : 0

  name        = "${var.name_prefix}-liberty-green"
  port        = 9080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
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

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-liberty-green"
  })
}

# -----------------------------------------------------------------------------
# CodeDeploy Application
# -----------------------------------------------------------------------------
resource "aws_codedeploy_app" "ecs" {
  count = var.enable_blue_green ? 1 : 0

  compute_platform = "ECS"
  name             = "${var.name_prefix}-liberty"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-codedeploy-app"
  })
}

# -----------------------------------------------------------------------------
# CodeDeploy Deployment Group
# -----------------------------------------------------------------------------
resource "aws_codedeploy_deployment_group" "ecs" {
  count = var.enable_blue_green && var.listener_arn != null ? 1 : 0

  app_name               = aws_codedeploy_app.ecs[0].name
  deployment_group_name  = "${var.name_prefix}-liberty-dg"
  service_role_arn       = aws_iam_role.codedeploy[0].arn
  deployment_config_name = var.codedeploy_deployment_config

  # ECS Service configuration
  ecs_service {
    cluster_name = aws_ecs_cluster.main.name
    service_name = aws_ecs_service.main.name
  }

  # Blue-Green deployment configuration
  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  # Traffic routing via ALB
  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [var.listener_arn]
      }

      target_group {
        name = local.blue_target_group_name
      }

      target_group {
        name = local.green_target_group_name
      }
    }
  }

  # Blue-Green deployment settings
  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = var.blue_green_termination_wait_minutes
    }
  }

  # Auto-rollback configuration
  auto_rollback_configuration {
    enabled = true
    events = [
      "DEPLOYMENT_FAILURE",
      "DEPLOYMENT_STOP_ON_ALARM"
    ]
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-codedeploy-dg"
  })
}

# Locals for blue-green target group names
locals {
  # Extract target group name from ARN
  blue_target_group_name  = var.target_group_arn != null ? element(split("/", var.target_group_arn), 1) : ""
  green_target_group_name = var.enable_blue_green && var.vpc_id != null ? aws_lb_target_group.green[0].name : (var.green_target_group_arn != null ? element(split("/", var.green_target_group_arn), 1) : "")
}

# -----------------------------------------------------------------------------
# IAM Role for CodeDeploy
# -----------------------------------------------------------------------------
resource "aws_iam_role" "codedeploy" {
  count = var.enable_blue_green ? 1 : 0

  name = "${var.name_prefix}-codedeploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codedeploy.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-codedeploy-role"
  })
}

# -----------------------------------------------------------------------------
# IAM Policy Attachment for CodeDeploy
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "codedeploy_ecs" {
  count = var.enable_blue_green ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
  role       = aws_iam_role.codedeploy[0].name
}

# -----------------------------------------------------------------------------
# Additional IAM Policy for CodeDeploy (ECS-specific permissions)
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "codedeploy_ecs_permissions" {
  count = var.enable_blue_green ? 1 : 0

  name = "${var.name_prefix}-codedeploy-ecs-policy"
  role = aws_iam_role.codedeploy[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECSTaskDefinitionPermissions"
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:CreateTaskSet",
          "ecs:UpdateServicePrimaryTaskSet",
          "ecs:DeleteTaskSet"
        ]
        Resource = [
          aws_ecs_cluster.main.arn,
          "arn:aws:ecs:${var.aws_region}:*:service/${aws_ecs_cluster.main.name}/*",
          "arn:aws:ecs:${var.aws_region}:*:task-set/${aws_ecs_cluster.main.name}/*"
        ]
      },
      {
        Sid    = "ELBPermissions"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:ModifyRule"
        ]
        Resource = "*"
      },
      {
        Sid    = "PassRole"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = [
          aws_iam_role.ecs_execution.arn,
          aws_iam_role.ecs_task.arn
        ]
        Condition = {
          StringEqualsIfExists = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      },
      {
        Sid    = "S3ArtifactAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "arn:aws:s3:::*codedeploy*/*"
      }
    ]
  })
}

# =============================================================================
# X-Ray / OpenTelemetry Resources
# =============================================================================

# -----------------------------------------------------------------------------
# IAM Policy for X-Ray
# -----------------------------------------------------------------------------
resource "aws_iam_policy" "xray" {
  count = var.enable_xray ? 1 : 0

  name        = "${var.name_prefix}-xray-policy"
  description = "Allow ECS tasks to send traces to X-Ray"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "XRayAccess"
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets",
          "xray:GetSamplingStatisticSummaries"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-xray-policy"
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_xray" {
  count = var.enable_xray ? 1 : 0

  role       = aws_iam_role.ecs_task.name
  policy_arn = aws_iam_policy.xray[0].arn
}

# =============================================================================
# SLO Alarms Resources
# =============================================================================

# -----------------------------------------------------------------------------
# High CPU Utilization Alarm
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  count = var.enable_slo_alarms ? 1 : 0

  alarm_name          = "${var.name_prefix}-ecs-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = var.slo_cpu_threshold
  alarm_description   = "ECS service CPU utilization above ${var.slo_cpu_threshold}%"

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.main.name
  }

  alarm_actions = var.sns_topic_arn != null ? [var.sns_topic_arn] : []
  ok_actions    = var.sns_topic_arn != null ? [var.sns_topic_arn] : []

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-ecs-cpu-high-alarm"
  })
}

# -----------------------------------------------------------------------------
# High Memory Utilization Alarm
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "memory_high" {
  count = var.enable_slo_alarms ? 1 : 0

  alarm_name          = "${var.name_prefix}-ecs-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = var.slo_memory_threshold
  alarm_description   = "ECS service memory utilization above ${var.slo_memory_threshold}%"

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.main.name
  }

  alarm_actions = var.sns_topic_arn != null ? [var.sns_topic_arn] : []
  ok_actions    = var.sns_topic_arn != null ? [var.sns_topic_arn] : []

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-ecs-memory-high-alarm"
  })
}

# -----------------------------------------------------------------------------
# Unhealthy Tasks Alarm (for deployment rollback triggers)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "unhealthy_tasks" {
  count = var.enable_slo_alarms && var.enable_request_scaling ? 1 : 0

  alarm_name          = "${var.name_prefix}-ecs-unhealthy-tasks"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "Triggers when ECS tasks become unhealthy"

  dimensions = {
    TargetGroup  = local.target_group_arn_suffix
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = var.sns_topic_arn != null ? [var.sns_topic_arn] : []
  ok_actions    = var.sns_topic_arn != null ? [var.sns_topic_arn] : []

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-ecs-unhealthy-alarm"
  })
}
