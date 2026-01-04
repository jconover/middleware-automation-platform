# =============================================================================
# Monitoring Module - Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# Instance Outputs
# -----------------------------------------------------------------------------
output "instance_id" {
  description = "ID of the monitoring EC2 instance"
  value       = aws_instance.monitoring.id
}

output "instance_public_ip" {
  description = "Public IP of the monitoring server (Elastic IP if created, otherwise instance IP)"
  value       = var.create_elastic_ip ? aws_eip.monitoring[0].public_ip : aws_instance.monitoring.public_ip
}

output "instance_private_ip" {
  description = "Private IP of the monitoring server"
  value       = aws_instance.monitoring.private_ip
}

# -----------------------------------------------------------------------------
# Service URLs
# -----------------------------------------------------------------------------
output "grafana_url" {
  description = "Grafana Web UI URL"
  value       = "http://${var.create_elastic_ip ? aws_eip.monitoring[0].public_ip : aws_instance.monitoring.public_ip}:3000"
}

output "prometheus_url" {
  description = "Prometheus Web UI URL"
  value       = "http://${var.create_elastic_ip ? aws_eip.monitoring[0].public_ip : aws_instance.monitoring.public_ip}:9090"
}

output "alertmanager_url" {
  description = "AlertManager Web UI URL"
  value       = "http://${var.create_elastic_ip ? aws_eip.monitoring[0].public_ip : aws_instance.monitoring.public_ip}:9093"
}

# -----------------------------------------------------------------------------
# SSH Access
# -----------------------------------------------------------------------------
output "ssh_command" {
  description = "SSH command to connect to the monitoring server"
  value       = "ssh -i ~/.ssh/${var.ssh_key_name} ubuntu@${var.create_elastic_ip ? aws_eip.monitoring[0].public_ip : aws_instance.monitoring.public_ip}"
}

# -----------------------------------------------------------------------------
# Secrets Manager
# -----------------------------------------------------------------------------
output "grafana_secret_arn" {
  description = "ARN of the Secrets Manager secret containing Grafana admin credentials"
  value       = aws_secretsmanager_secret.grafana_credentials.arn
  sensitive   = true
}

output "grafana_secret_id" {
  description = "ID of the Secrets Manager secret containing Grafana admin credentials"
  value       = aws_secretsmanager_secret.grafana_credentials.id
  sensitive   = true
}

output "grafana_admin_password_command" {
  description = "AWS CLI command to retrieve Grafana admin password"
  value       = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.grafana_credentials.id} --query SecretString --output text | jq -r .admin_password"
  sensitive   = true
}

# -----------------------------------------------------------------------------
# IAM
# -----------------------------------------------------------------------------
output "iam_role_arn" {
  description = "ARN of the IAM role for the monitoring server"
  value       = aws_iam_role.monitoring.arn
}

output "iam_role_name" {
  description = "Name of the IAM role for the monitoring server"
  value       = aws_iam_role.monitoring.name
}

output "instance_profile_arn" {
  description = "ARN of the IAM instance profile for the monitoring server"
  value       = aws_iam_instance_profile.monitoring.arn
}

output "instance_profile_name" {
  description = "Name of the IAM instance profile for the monitoring server"
  value       = aws_iam_instance_profile.monitoring.name
}

# -----------------------------------------------------------------------------
# Security Group
# -----------------------------------------------------------------------------
output "security_group_id" {
  description = "ID of the monitoring server security group (if created by module)"
  value       = var.create_security_group ? aws_security_group.monitoring[0].id : var.security_group_id
}

# -----------------------------------------------------------------------------
# Elastic IP
# -----------------------------------------------------------------------------
output "elastic_ip_id" {
  description = "Allocation ID of the Elastic IP (if created)"
  value       = var.create_elastic_ip ? aws_eip.monitoring[0].id : null
}

output "elastic_ip_public_ip" {
  description = "Public IP address of the Elastic IP (if created)"
  value       = var.create_elastic_ip ? aws_eip.monitoring[0].public_ip : null
}

# -----------------------------------------------------------------------------
# CloudWatch
# -----------------------------------------------------------------------------
output "log_group_name" {
  description = "Name of the CloudWatch log group for monitoring server"
  value       = aws_cloudwatch_log_group.monitoring.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group for monitoring server"
  value       = aws_cloudwatch_log_group.monitoring.arn
}

# -----------------------------------------------------------------------------
# Configuration Status
# -----------------------------------------------------------------------------
output "ecs_discovery_enabled" {
  description = "Whether ECS service discovery is enabled"
  value       = var.ecs_cluster_name != ""
}

output "alertmanager_slack_configured" {
  description = "Whether AlertManager Slack notifications are configured"
  value       = var.alertmanager_slack_secret_arn != ""
}

output "static_targets_configured" {
  description = "Whether static Liberty targets are configured for EC2 scraping"
  value       = length([for t in var.liberty_targets : t if t != ""]) > 0
}
