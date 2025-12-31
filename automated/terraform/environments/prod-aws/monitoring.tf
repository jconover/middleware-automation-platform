# =============================================================================
# Monitoring Server - Prometheus & Grafana
# =============================================================================
# Dedicated server for monitoring Liberty application servers.
# Runs Prometheus for metrics collection and Grafana for visualization.
# Variables are defined in variables.tf with validation
# =============================================================================

# -----------------------------------------------------------------------------
# Grafana Admin Credentials (Secrets Manager)
# -----------------------------------------------------------------------------
resource "random_password" "grafana_admin" {
  count = var.create_monitoring_server ? 1 : 0

  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}:?"
}

resource "aws_secretsmanager_secret" "grafana_credentials" {
  count = var.create_monitoring_server ? 1 : 0

  name        = "${local.name_prefix}/monitoring/grafana-credentials"
  description = "Grafana admin credentials for ${local.name_prefix} monitoring server"

  tags = {
    Name = "${local.name_prefix}-grafana-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "grafana_credentials" {
  count = var.create_monitoring_server ? 1 : 0

  secret_id = aws_secretsmanager_secret.grafana_credentials[0].id

  secret_string = jsonencode({
    admin_user     = "admin"
    admin_password = random_password.grafana_admin[0].result
  })
}

# -----------------------------------------------------------------------------
# AlertManager Slack Webhook Secret (Optional)
# -----------------------------------------------------------------------------
# To enable AlertManager Slack notifications:
#   1. Create the secret manually in AWS Secrets Manager:
#      aws secretsmanager create-secret --name mw-prod/monitoring/alertmanager-slack \
#        --secret-string '{"slack_webhook_url":"https://hooks.slack.com/services/..."}'
#   2. Set var.alertmanager_slack_secret_arn to the secret ARN
#
# The secret should contain JSON with the key "slack_webhook_url":
#   {"slack_webhook_url": "https://hooks.slack.com/services/T.../B.../xxx"}
# -----------------------------------------------------------------------------

# Data source to look up the secret if provided
data "aws_secretsmanager_secret" "alertmanager_slack" {
  count = var.create_monitoring_server && var.alertmanager_slack_secret_arn != "" ? 1 : 0
  arn   = var.alertmanager_slack_secret_arn
}

# -----------------------------------------------------------------------------
# IAM Role for Monitoring Server (ECS Service Discovery)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "monitoring" {
  count = var.create_monitoring_server ? 1 : 0

  name = "${local.name_prefix}-monitoring-role"

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

  tags = {
    Name = "${local.name_prefix}-monitoring-role"
  }
}

resource "aws_iam_role_policy" "monitoring_ecs_discovery" {
  count = var.create_monitoring_server ? 1 : 0

  name = "${local.name_prefix}-ecs-discovery"
  role = aws_iam_role.monitoring[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
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
      },
      {
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
        Resource = aws_secretsmanager_secret.grafana_credentials[0].arn
      },
      {
        Sid    = "ReadAlertManagerSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        # Allow reading the AlertManager slack secret if configured
        Resource = var.alertmanager_slack_secret_arn != "" ? var.alertmanager_slack_secret_arn : aws_secretsmanager_secret.grafana_credentials[0].arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "monitoring" {
  count = var.create_monitoring_server ? 1 : 0

  name = "${local.name_prefix}-monitoring-profile"
  role = aws_iam_role.monitoring[0].name
}

# -----------------------------------------------------------------------------
# Security Group
# -----------------------------------------------------------------------------
resource "aws_security_group" "monitoring" {
  count = var.create_monitoring_server ? 1 : 0

  name        = "${local.name_prefix}-monitoring-sg"
  description = "Security group for Prometheus/Grafana monitoring server"
  vpc_id      = aws_vpc.main.id

  # SSH
  ingress {
    description = "SSH from allowed CIDRs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.management_allowed_cidrs
  }

  # Prometheus
  ingress {
    description = "Prometheus from allowed CIDRs"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = var.management_allowed_cidrs
  }

  # Grafana
  ingress {
    description = "Grafana from allowed CIDRs"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = var.management_allowed_cidrs
  }

  # AlertManager (optional, for future use)
  ingress {
    description = "AlertManager from allowed CIDRs"
    from_port   = 9093
    to_port     = 9093
    protocol    = "tcp"
    cidr_blocks = var.management_allowed_cidrs
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-monitoring-sg"
  }
}

# -----------------------------------------------------------------------------
# Elastic IP (stable public IP)
# -----------------------------------------------------------------------------
resource "aws_eip" "monitoring" {
  count = var.create_monitoring_server ? 1 : 0

  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-monitoring-eip"
  }
}

resource "aws_eip_association" "monitoring" {
  count = var.create_monitoring_server ? 1 : 0

  instance_id   = aws_instance.monitoring[0].id
  allocation_id = aws_eip.monitoring[0].id
}

# -----------------------------------------------------------------------------
# EC2 Instance
# -----------------------------------------------------------------------------
resource "aws_instance" "monitoring" {
  count = var.create_monitoring_server ? 1 : 0

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.monitoring_instance_type
  key_name               = aws_key_pair.deployer.key_name
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.monitoring[0].id]
  iam_instance_profile   = aws_iam_instance_profile.monitoring[0].name

  root_block_device {
    volume_size           = 30 # Space for metrics storage
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "${local.name_prefix}-monitoring-root"
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(templatefile("${path.module}/templates/monitoring-user-data.sh", {
    liberty1_ip                   = length(aws_instance.liberty) > 0 ? aws_instance.liberty[0].private_ip : ""
    liberty2_ip                   = length(aws_instance.liberty) > 1 ? aws_instance.liberty[1].private_ip : (length(aws_instance.liberty) > 0 ? aws_instance.liberty[0].private_ip : "")
    aws_region                    = var.aws_region
    ecs_enabled                   = var.ecs_enabled
    ecs_cluster_name              = var.ecs_enabled ? aws_ecs_cluster.main[0].name : ""
    grafana_credentials_secret_id = aws_secretsmanager_secret.grafana_credentials[0].id
    alertmanager_slack_secret_id  = var.alertmanager_slack_secret_arn != "" ? var.alertmanager_slack_secret_arn : ""
  }))

  tags = {
    Name         = "${local.name_prefix}-monitoring"
    Role         = "monitoring"
    AnsibleGroup = "monitoring_servers"
  }

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

# -----------------------------------------------------------------------------
# Allow monitoring server to scrape Liberty metrics
# -----------------------------------------------------------------------------
resource "aws_security_group_rule" "liberty_metrics_from_monitoring" {
  count = var.create_monitoring_server ? 1 : 0

  type                     = "ingress"
  from_port                = 9080
  to_port                  = 9080
  protocol                 = "tcp"
  security_group_id        = aws_security_group.liberty.id
  source_security_group_id = aws_security_group.monitoring[0].id
  description              = "Liberty metrics from monitoring server"
}

resource "aws_security_group_rule" "liberty_node_exporter_from_monitoring" {
  count = var.create_monitoring_server ? 1 : 0

  type                     = "ingress"
  from_port                = 9100
  to_port                  = 9100
  protocol                 = "tcp"
  security_group_id        = aws_security_group.liberty.id
  source_security_group_id = aws_security_group.monitoring[0].id
  description              = "Node exporter from monitoring server"
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "monitoring_public_ip" {
  description = "Public IP of the monitoring server"
  value       = var.create_monitoring_server ? aws_eip.monitoring[0].public_ip : null
}

output "monitoring_private_ip" {
  description = "Private IP of the monitoring server"
  value       = var.create_monitoring_server ? aws_instance.monitoring[0].private_ip : null
}

output "prometheus_url" {
  description = "Prometheus Web UI URL"
  value       = var.create_monitoring_server ? "http://${aws_eip.monitoring[0].public_ip}:9090" : null
}

output "grafana_url" {
  description = "Grafana Web UI URL"
  value       = var.create_monitoring_server ? "http://${aws_eip.monitoring[0].public_ip}:3000" : null
}

output "monitoring_ssh_command" {
  description = "SSH command to connect to monitoring server"
  value       = var.create_monitoring_server ? "ssh -i ~/.ssh/ansible_ed25519 ubuntu@${aws_eip.monitoring[0].public_ip}" : null
}

output "grafana_credentials_secret_arn" {
  description = "ARN of the Secrets Manager secret containing Grafana admin credentials"
  value       = var.create_monitoring_server ? aws_secretsmanager_secret.grafana_credentials[0].arn : null
  sensitive   = true
}

output "grafana_admin_password_command" {
  description = "AWS CLI command to retrieve Grafana admin password"
  value       = var.create_monitoring_server ? "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.grafana_credentials[0].id} --query SecretString --output text | jq -r .admin_password" : null
  sensitive   = true
}

output "alertmanager_url" {
  description = "AlertManager Web UI URL"
  value       = var.create_monitoring_server ? "http://${aws_eip.monitoring[0].public_ip}:9093" : null
}

output "alertmanager_slack_configured" {
  description = "Whether AlertManager Slack notifications are configured"
  value       = var.alertmanager_slack_secret_arn != ""
}
