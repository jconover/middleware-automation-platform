# =============================================================================
# AWS CodeDeploy for ECS Blue-Green Deployments
# =============================================================================
# This module creates CodeDeploy resources for zero-downtime ECS deployments
# with automatic rollback capabilities.
# =============================================================================

# -----------------------------------------------------------------------------
# Green Target Group (for Blue-Green deployments)
# -----------------------------------------------------------------------------
resource "aws_lb_target_group" "liberty_ecs_green" {
  count = var.ecs_enabled && var.enable_blue_green ? 1 : 0

  name        = "${local.name_prefix}-liberty-ecs-green"
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
    Name = "${local.name_prefix}-liberty-ecs-green"
  }
}

# -----------------------------------------------------------------------------
# CodeDeploy Application
# -----------------------------------------------------------------------------
resource "aws_codedeploy_app" "ecs_liberty" {
  count = var.ecs_enabled && var.enable_blue_green ? 1 : 0

  compute_platform = "ECS"
  name             = "${local.name_prefix}-liberty"

  tags = {
    Name = "${local.name_prefix}-codedeploy-app"
  }
}

# -----------------------------------------------------------------------------
# CodeDeploy Deployment Group
# -----------------------------------------------------------------------------
resource "aws_codedeploy_deployment_group" "ecs_liberty" {
  count = var.ecs_enabled && var.enable_blue_green ? 1 : 0

  app_name               = aws_codedeploy_app.ecs_liberty[0].name
  deployment_group_name  = "${local.name_prefix}-liberty-dg"
  service_role_arn       = aws_iam_role.codedeploy[0].arn
  deployment_config_name = "CodeDeployDefault.ECSLinear10PercentEvery1Minutes"

  # ECS Service configuration
  ecs_service {
    cluster_name = aws_ecs_cluster.main[0].name
    service_name = aws_ecs_service.liberty[0].name
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
        listener_arns = [aws_lb_listener.http.arn]
      }

      target_group {
        name = aws_lb_target_group.liberty_ecs[0].name
      }

      target_group {
        name = aws_lb_target_group.liberty_ecs_green[0].name
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
      termination_wait_time_in_minutes = 5
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

  tags = {
    Name = "${local.name_prefix}-codedeploy-dg"
  }
}

# -----------------------------------------------------------------------------
# IAM Role for CodeDeploy
# -----------------------------------------------------------------------------
resource "aws_iam_role" "codedeploy" {
  count = var.ecs_enabled && var.enable_blue_green ? 1 : 0

  name = "${local.name_prefix}-codedeploy-role"

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

  tags = {
    Name = "${local.name_prefix}-codedeploy-role"
  }
}

# -----------------------------------------------------------------------------
# IAM Policy Attachment for CodeDeploy
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "codedeploy_ecs" {
  count = var.ecs_enabled && var.enable_blue_green ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
  role       = aws_iam_role.codedeploy[0].name
}

# -----------------------------------------------------------------------------
# Additional IAM Policy for CodeDeploy (ECS-specific permissions)
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "codedeploy_ecs_permissions" {
  count = var.ecs_enabled && var.enable_blue_green ? 1 : 0

  name = "${local.name_prefix}-codedeploy-ecs-policy"
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
          aws_ecs_cluster.main[0].arn,
          "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:service/${aws_ecs_cluster.main[0].name}/*",
          "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:task-set/${aws_ecs_cluster.main[0].name}/*"
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

# -----------------------------------------------------------------------------
# CloudWatch Alarm for Deployment Rollback (Optional but recommended)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "ecs_unhealthy_tasks" {
  count = var.ecs_enabled && var.enable_blue_green ? 1 : 0

  alarm_name          = "${local.name_prefix}-ecs-unhealthy-tasks"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "Triggers rollback when ECS tasks become unhealthy during deployment"

  dimensions = {
    TargetGroup  = aws_lb_target_group.liberty_ecs[0].arn_suffix
    LoadBalancer = aws_lb.main.arn_suffix
  }

  tags = {
    Name = "${local.name_prefix}-ecs-unhealthy-alarm"
  }
}
