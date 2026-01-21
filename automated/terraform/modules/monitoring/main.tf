# =============================================================================
# Monitoring Module - Prometheus, Grafana, AlertManager
# =============================================================================
# This module creates a dedicated monitoring server with:
# - Prometheus for metrics collection
# - Grafana for visualization
# - AlertManager for alerting
# - ECS service discovery (when ecs_cluster_name is provided)
# - Static target discovery for EC2 instances
# =============================================================================

# -----------------------------------------------------------------------------
# Local Values
# -----------------------------------------------------------------------------
locals {
  # Filter out empty strings from liberty_targets
  valid_liberty_targets = [for t in var.liberty_targets : t if t != ""]
}

# -----------------------------------------------------------------------------
# Grafana Admin Credentials (Secrets Manager)
# -----------------------------------------------------------------------------
resource "random_password" "grafana_admin" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}:?"
}

resource "aws_secretsmanager_secret" "grafana_credentials" {
  name        = "${var.name_prefix}/monitoring/grafana-credentials"
  description = "Grafana admin credentials for ${var.name_prefix} monitoring server"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-grafana-credentials"
  })
}

resource "aws_secretsmanager_secret_version" "grafana_credentials" {
  secret_id = aws_secretsmanager_secret.grafana_credentials.id

  secret_string = jsonencode({
    admin_user     = "admin"
    admin_password = random_password.grafana_admin.result
  })
}

# -----------------------------------------------------------------------------
# IAM Role for Monitoring Server (ECS Service Discovery)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "monitoring" {
  name = "${var.name_prefix}-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-monitoring-role"
  })
}

resource "aws_iam_role_policy" "monitoring_ecs_discovery" {
  name = "${var.name_prefix}-ecs-discovery"
  role = aws_iam_role.monitoring.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # AWS ECS List/Describe APIs do not support resource-level permissions.
        # Per AWS documentation, these actions require Resource = "*":
        # - ecs:ListClusters, ecs:ListTasks - list operations have no ARN
        # - ecs:DescribeTasks, ecs:DescribeServices - require task/service ARNs
        #   not known until discovery runs
        # - ecs:DescribeContainerInstances, ecs:DescribeTaskDefinition - same
        # See: https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazonelasticcontainerservice.html
        # Mitigation: This role is only attached to the monitoring server instance.
        Sid    = "ECSServiceDiscovery"
        Effect = "Allow"
        Action = [
          "ecs:ListClusters",
          "ecs:ListTasks",
          "ecs:DescribeTasks",
          "ecs:DescribeServices",
          "ecs:DescribeContainerInstances",
          "ecs:DescribeTaskDefinition"
        ]
        Resource = "*"
        # Condition block not supported for these actions - AWS does not allow
        # tag-based conditions on ECS describe/list operations
      },
      {
        # AWS EC2 Describe APIs do not support resource-level permissions.
        # Per AWS documentation, ec2:DescribeInstances and ec2:DescribeNetworkInterfaces
        # require Resource = "*" - they are read-only enumeration operations.
        # See: https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazonec2.html
        # Mitigation: This role is only attached to the monitoring server instance,
        # and these are read-only operations with no modification capability.
        Sid    = "EC2DescribeForECS"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces"
        ]
        Resource = "*"
      },
      {
        Sid    = "ReadGrafanaCredentials"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.grafana_credentials.arn
      },
      {
        Sid    = "ReadAlertManagerSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        # Allow reading the AlertManager slack secret if configured
        Resource = var.alertmanager_slack_secret_arn != "" ? var.alertmanager_slack_secret_arn : aws_secretsmanager_secret.grafana_credentials.arn
      },
      {
        Sid    = "CloudWatchMetricsRead"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "monitoring" {
  name = "${var.name_prefix}-monitoring-profile"
  role = aws_iam_role.monitoring.name
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group for Monitoring Server
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "monitoring" {
  name              = "/ec2/${var.name_prefix}-monitoring"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-monitoring-logs"
  })
}

# -----------------------------------------------------------------------------
# Security Group (optional - can use external SG)
# -----------------------------------------------------------------------------
resource "aws_security_group" "monitoring" {
  count = var.create_security_group ? 1 : 0

  name        = "${var.name_prefix}-monitoring-sg"
  description = "Security group for Prometheus/Grafana monitoring server"
  vpc_id      = var.vpc_id

  # SSH
  ingress {
    description = "SSH from allowed CIDRs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  # Prometheus
  ingress {
    description = "Prometheus from allowed CIDRs"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  # Grafana
  ingress {
    description = "Grafana from allowed CIDRs"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  # AlertManager
  ingress {
    description = "AlertManager from allowed CIDRs"
    from_port   = 9093
    to_port     = 9093
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  # Least-privilege egress rules
  egress {
    description = "HTTPS to external APIs (package updates, AWS APIs)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP to VPC for metrics scraping (Liberty, Node Exporter)"
    from_port   = 9080
    to_port     = 9080
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Node Exporter metrics from VPC"
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-monitoring-sg"
  })
}

# -----------------------------------------------------------------------------
# Elastic IP (stable public IP)
# -----------------------------------------------------------------------------
resource "aws_eip" "monitoring" {
  count = var.create_elastic_ip ? 1 : 0

  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-monitoring-eip"
  })
}

resource "aws_eip_association" "monitoring" {
  count = var.create_elastic_ip ? 1 : 0

  instance_id   = aws_instance.monitoring.id
  allocation_id = aws_eip.monitoring[0].id
}

# -----------------------------------------------------------------------------
# User Data with Gzip Compression
# -----------------------------------------------------------------------------
# The monitoring user-data script exceeds EC2's 16 KB limit (~20 KB).
# Using cloudinit_config with gzip compression reduces it to ~6-7 KB.
# -----------------------------------------------------------------------------
data "cloudinit_config" "monitoring" {
  gzip          = true
  base64_encode = true

  part {
    content_type = "text/x-shellscript"
    content = templatefile("${path.module}/templates/monitoring-user-data.sh", {
      name_prefix                   = var.name_prefix
      aws_region                    = var.aws_region
      ecs_enabled                   = var.ecs_cluster_name != ""
      ecs_cluster_name              = var.ecs_cluster_name
      grafana_credentials_secret_id = aws_secretsmanager_secret.grafana_credentials.id
      alertmanager_slack_secret_id  = var.alertmanager_slack_secret_arn
      prometheus_retention_days     = var.prometheus_retention_days
      grafana_version               = var.grafana_version
      liberty_targets               = local.valid_liberty_targets
      alertmanager_config           = var.alertmanager_config
    })
  }
}

# -----------------------------------------------------------------------------
# EC2 Instance
# -----------------------------------------------------------------------------
resource "aws_instance" "monitoring" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.ssh_key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.create_security_group ? [aws_security_group.monitoring[0].id] : [var.security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.monitoring.name

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true

    tags = merge(var.tags, {
      Name = "${var.name_prefix}-monitoring-root"
    })
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = data.cloudinit_config.monitoring.rendered

  tags = merge(var.tags, {
    Name         = "${var.name_prefix}-monitoring"
    Role         = "monitoring"
    AnsibleGroup = "monitoring_servers"
  })

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

# -----------------------------------------------------------------------------
# Security Group Rules for Target Scraping (optional)
# -----------------------------------------------------------------------------
# These rules allow the monitoring server to scrape metrics from targets.
# Only created when target_security_group_id is provided.

resource "aws_security_group_rule" "target_metrics_from_monitoring" {
  count = var.enable_target_monitoring_rules ? 1 : 0

  type                     = "ingress"
  from_port                = 9080
  to_port                  = 9080
  protocol                 = "tcp"
  security_group_id        = var.target_security_group_id
  source_security_group_id = var.create_security_group ? aws_security_group.monitoring[0].id : var.security_group_id
  description              = "Liberty metrics from monitoring server"
}

resource "aws_security_group_rule" "target_node_exporter_from_monitoring" {
  count = var.enable_target_monitoring_rules ? 1 : 0

  type                     = "ingress"
  from_port                = 9100
  to_port                  = 9100
  protocol                 = "tcp"
  security_group_id        = var.target_security_group_id
  source_security_group_id = var.create_security_group ? aws_security_group.monitoring[0].id : var.security_group_id
  description              = "Node exporter from monitoring server"
}
