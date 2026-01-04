# =============================================================================
# Outputs
# =============================================================================
# Key outputs from all modules for use by other configurations, scripts,
# or for display after terraform apply.
# =============================================================================

# -----------------------------------------------------------------------------
# VPC and Networking Outputs
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = module.networking.vpc_cidr
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = module.networking.private_subnet_ids
}

output "nat_gateway_public_ips" {
  description = "Public IPs of the NAT gateways"
  value       = module.networking.nat_gateway_public_ips
}

# -----------------------------------------------------------------------------
# Load Balancer Outputs
# -----------------------------------------------------------------------------

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.loadbalancer.alb_dns_name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = module.loadbalancer.alb_arn
}

output "alb_zone_id" {
  description = "Canonical hosted zone ID of the ALB (for Route 53 alias records)"
  value       = module.loadbalancer.alb_zone_id
}

output "app_url" {
  description = "Application URL (HTTPS if certificate available, HTTP otherwise)"
  value       = module.loadbalancer.app_url
}

output "ecs_target_group_arn" {
  description = "ARN of the ECS target group"
  value       = module.loadbalancer.ecs_target_group_arn
}

output "ec2_target_group_arn" {
  description = "ARN of the EC2 target group"
  value       = module.loadbalancer.ec2_target_group_arn
}

# -----------------------------------------------------------------------------
# Database Outputs
# -----------------------------------------------------------------------------

output "db_endpoint" {
  description = "RDS PostgreSQL endpoint address"
  value       = module.database.db_endpoint
}

output "db_effective_endpoint" {
  description = "Effective database endpoint (RDS Proxy if enabled, otherwise direct RDS endpoint)"
  value       = module.database.db_effective_endpoint
}

output "db_port" {
  description = "RDS PostgreSQL port"
  value       = module.database.db_port
}

output "db_name" {
  description = "Database name"
  value       = module.database.db_name
}

output "db_secret_arn" {
  description = "Secrets Manager secret ARN for database credentials"
  value       = module.database.db_secret_arn
  sensitive   = true
}

output "rds_proxy_endpoint" {
  description = "RDS Proxy endpoint (null if proxy not enabled)"
  value       = module.database.rds_proxy_endpoint
}

output "rds_proxy_enabled" {
  description = "Whether RDS Proxy is enabled"
  value       = module.database.rds_proxy_enabled
}

output "cache_endpoint" {
  description = "ElastiCache Redis primary endpoint address"
  value       = module.database.cache_endpoint
}

output "cache_reader_endpoint" {
  description = "ElastiCache Redis reader endpoint address"
  value       = module.database.cache_reader_endpoint
}

output "cache_port" {
  description = "ElastiCache Redis port"
  value       = module.database.cache_port
}

output "cache_auth_token_secret_arn" {
  description = "Secrets Manager secret ARN for Redis AUTH token"
  value       = module.database.cache_auth_token_secret_arn
  sensitive   = true
}

# -----------------------------------------------------------------------------
# ECS Outputs (Conditional)
# -----------------------------------------------------------------------------

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = var.ecs_enabled ? module.ecs[0].cluster_name : null
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = var.ecs_enabled ? module.ecs[0].cluster_arn : null
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = var.ecs_enabled ? module.ecs[0].service_name : null
}

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = var.ecs_enabled ? module.ecs[0].ecr_repository_url : null
}

output "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = var.ecs_enabled ? module.ecs[0].task_execution_role_arn : null
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task role"
  value       = var.ecs_enabled ? module.ecs[0].task_role_arn : null
}

output "ecs_log_group_name" {
  description = "Name of the ECS CloudWatch log group"
  value       = var.ecs_enabled ? module.ecs[0].log_group_name : null
}

output "ecs_autoscaling_enabled" {
  description = "Whether ECS auto-scaling is enabled"
  value       = var.ecs_enabled ? module.ecs[0].autoscaling_enabled : null
}

# -----------------------------------------------------------------------------
# EC2 Compute Outputs (Conditional)
# -----------------------------------------------------------------------------

output "liberty_instance_ids" {
  description = "List of Liberty EC2 instance IDs"
  value       = var.liberty_instance_count > 0 ? module.compute[0].instance_ids : []
}

output "liberty_instance_private_ips" {
  description = "List of Liberty EC2 private IP addresses"
  value       = var.liberty_instance_count > 0 ? module.compute[0].instance_private_ips : []
}

output "liberty_instance_private_dns" {
  description = "List of Liberty EC2 private DNS names"
  value       = var.liberty_instance_count > 0 ? module.compute[0].instance_private_dns : []
}

output "liberty_ssh_key_name" {
  description = "Name of the SSH key pair for Liberty instances"
  value       = var.liberty_instance_count > 0 ? module.compute[0].ssh_key_name : null
}

output "liberty_iam_role_arn" {
  description = "ARN of the Liberty EC2 IAM role"
  value       = var.liberty_instance_count > 0 ? module.compute[0].iam_role_arn : null
}

# -----------------------------------------------------------------------------
# Monitoring Outputs (Conditional)
# -----------------------------------------------------------------------------

output "monitoring_instance_id" {
  description = "ID of the monitoring EC2 instance"
  value       = var.create_monitoring_server ? module.monitoring[0].instance_id : null
}

output "monitoring_public_ip" {
  description = "Public IP of the monitoring server"
  value       = var.create_monitoring_server ? module.monitoring[0].instance_public_ip : null
}

output "grafana_url" {
  description = "Grafana Web UI URL"
  value       = var.create_monitoring_server ? module.monitoring[0].grafana_url : null
}

output "prometheus_url" {
  description = "Prometheus Web UI URL"
  value       = var.create_monitoring_server ? module.monitoring[0].prometheus_url : null
}

output "alertmanager_url" {
  description = "AlertManager Web UI URL"
  value       = var.create_monitoring_server ? module.monitoring[0].alertmanager_url : null
}

output "grafana_secret_arn" {
  description = "ARN of the Secrets Manager secret containing Grafana admin credentials"
  value       = var.create_monitoring_server ? module.monitoring[0].grafana_secret_arn : null
  sensitive   = true
}

output "monitoring_ssh_command" {
  description = "SSH command to connect to the monitoring server"
  value       = var.create_monitoring_server ? module.monitoring[0].ssh_command : null
}

# -----------------------------------------------------------------------------
# Security Compliance Outputs
# -----------------------------------------------------------------------------

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail"
  value       = module.security_compliance.cloudtrail_arn
}

output "cloudtrail_s3_bucket" {
  description = "Name of the S3 bucket for CloudTrail logs"
  value       = module.security_compliance.cloudtrail_s3_bucket
}

output "guardduty_detector_id" {
  description = "ID of the GuardDuty detector"
  value       = module.security_compliance.guardduty_detector_id
}

output "security_hub_arn" {
  description = "ARN of the Security Hub account"
  value       = module.security_compliance.security_hub_arn
}

output "waf_web_acl_arn" {
  description = "ARN of the WAF Web ACL"
  value       = module.security_compliance.waf_web_acl_arn
}

output "security_enabled_features" {
  description = "Map of enabled security features"
  value       = module.security_compliance.enabled_features
}

output "security_alerts_sns_topic_arn" {
  description = "ARN of the SNS topic for security alerts"
  value       = module.security_compliance.security_alerts_sns_topic_arn
}

# -----------------------------------------------------------------------------
# Security Groups Outputs
# -----------------------------------------------------------------------------

output "security_group_ids" {
  description = "Map of all security group IDs"
  value       = module.security_groups.all_security_group_ids
}

# -----------------------------------------------------------------------------
# ECR Push Commands
# -----------------------------------------------------------------------------

output "ecr_push_commands" {
  description = "Commands to build and push container image to ECR"
  value = var.ecs_enabled ? join("\n", [
    "# Authenticate Docker to ECR",
    "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com",
    "",
    "# Build container from project root (multi-stage build compiles sample-app from source)",
    "docker build -t ${module.ecs[0].ecr_repository_url}:${var.container_image_tag} -f containers/liberty/Containerfile .",
    "",
    "# Push to ECR",
    "docker push ${module.ecs[0].ecr_repository_url}:${var.container_image_tag}",
    "",
    "# Force new ECS deployment",
    "aws ecs update-service --cluster ${module.ecs[0].cluster_name} --service ${module.ecs[0].service_name} --force-new-deployment --region ${var.aws_region}"
  ]) : null
}

# -----------------------------------------------------------------------------
# Deployment Summary
# -----------------------------------------------------------------------------

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    environment     = var.environment
    region          = var.aws_region
    vpc_id          = module.networking.vpc_id
    ecs_enabled     = var.ecs_enabled
    ec2_count       = var.liberty_instance_count
    monitoring      = var.create_monitoring_server
    app_url         = module.loadbalancer.app_url
    db_endpoint     = module.database.db_effective_endpoint
    cache_endpoint  = module.database.cache_endpoint
    grafana_url     = var.create_monitoring_server ? module.monitoring[0].grafana_url : null
    waf_enabled     = var.enable_waf
    guardduty_enabled = var.enable_guardduty
    cloudtrail_enabled = var.enable_cloudtrail
  }
}
