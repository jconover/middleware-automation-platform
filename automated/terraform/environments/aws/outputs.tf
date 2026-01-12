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
# Management Server Outputs (Conditional)
# -----------------------------------------------------------------------------

output "management_instance_id" {
  description = "ID of the management EC2 instance"
  value       = var.create_management_server ? aws_instance.management[0].id : null
}

output "management_public_ip" {
  description = "Public IP of the management server"
  value       = var.create_management_server ? aws_eip.management[0].public_ip : null
}

output "management_private_ip" {
  description = "Private IP of the management server"
  value       = var.create_management_server ? aws_instance.management[0].private_ip : null
}

output "awx_url" {
  description = "AWX Web UI URL"
  value       = var.create_management_server ? "http://${aws_eip.management[0].public_ip}:30080" : null
}

output "awx_admin_password_command" {
  description = "Command to get AWX admin password"
  value       = var.create_management_server ? "ssh ubuntu@${aws_eip.management[0].public_ip} 'sudo kubectl get secret awx-admin-password -n awx -o jsonpath=\"{.data.password}\" | base64 -d'" : null
  sensitive   = true
}

output "management_ssh_command" {
  description = "SSH command to connect to management server"
  value       = var.create_management_server ? "ssh -i ~/.ssh/ansible_ed25519 ubuntu@${aws_eip.management[0].public_ip}" : null
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
# SLO/SLI Alerting Outputs
# -----------------------------------------------------------------------------

output "slo_sns_topic_arn" {
  description = "ARN of the SNS topic for SLO alerts"
  value       = var.enable_slo_alarms && (var.ecs_enabled || var.liberty_instance_count > 0) ? aws_sns_topic.slo_alerts[0].arn : null
}

output "slo_composite_alarm_arn" {
  description = "ARN of the composite SLO health alarm"
  value       = var.enable_slo_alarms && (var.ecs_enabled || var.liberty_instance_count > 0) ? aws_cloudwatch_composite_alarm.slo_overall_health[0].arn : null
}

output "slo_alarms" {
  description = "Map of all SLO alarm ARNs"
  value = var.enable_slo_alarms && (var.ecs_enabled || var.liberty_instance_count > 0) ? {
    availability_critical = aws_cloudwatch_metric_alarm.slo_availability_critical[0].arn
    availability_warning  = aws_cloudwatch_metric_alarm.slo_availability_warning[0].arn
    latency_p99_critical  = aws_cloudwatch_metric_alarm.slo_latency_p99_critical[0].arn
    latency_p99_warning   = aws_cloudwatch_metric_alarm.slo_latency_p99_warning[0].arn
    latency_tail_critical = aws_cloudwatch_metric_alarm.slo_latency_tail_critical[0].arn
    error_rate_breach     = aws_cloudwatch_metric_alarm.slo_error_rate_breach[0].arn
    error_rate_warning    = aws_cloudwatch_metric_alarm.slo_error_rate_warning[0].arn
    unhealthy_targets     = aws_cloudwatch_metric_alarm.slo_unhealthy_targets[0].arn
    low_healthy_targets   = aws_cloudwatch_metric_alarm.slo_low_healthy_targets[0].arn
    overall_health        = aws_cloudwatch_composite_alarm.slo_overall_health[0].arn
  } : null
}

output "slo_configuration" {
  description = "SLO configuration summary"
  value = var.enable_slo_alarms ? {
    enabled              = true
    availability_target  = var.slo_availability_target
    latency_threshold_ms = var.slo_latency_threshold_ms
    alert_email          = var.slo_alert_email != "" ? var.slo_alert_email : var.security_alert_email
    monitoring_ecs       = var.ecs_enabled
    monitoring_ec2       = !var.ecs_enabled && var.liberty_instance_count > 0
    } : {
    enabled = false
  }
}

# -----------------------------------------------------------------------------
# S3 Cross-Region Replication Outputs
# -----------------------------------------------------------------------------

output "s3_replication_enabled" {
  description = "Whether S3 cross-region replication is enabled"
  value       = var.enable_s3_replication
}

output "dr_bucket_arn" {
  description = "ARN of the DR destination bucket for ALB logs"
  value       = var.enable_s3_replication ? aws_s3_bucket.alb_logs_dr[0].arn : null
}

output "dr_region" {
  description = "DR region for S3 replication"
  value       = var.enable_s3_replication ? var.dr_region : null
}

output "alb_logs_dr_bucket" {
  description = "ALB logs DR destination bucket name"
  value       = var.enable_s3_replication ? aws_s3_bucket.alb_logs_dr[0].id : null
}

output "cloudtrail_logs_dr_bucket" {
  description = "CloudTrail logs DR destination bucket name"
  value       = var.enable_s3_replication && var.enable_cloudtrail ? aws_s3_bucket.cloudtrail_dr[0].id : null
}

output "cloudtrail_logs_dr_bucket_arn" {
  description = "CloudTrail logs DR destination bucket ARN"
  value       = var.enable_s3_replication && var.enable_cloudtrail ? aws_s3_bucket.cloudtrail_dr[0].arn : null
}

output "s3_replication_role_arn" {
  description = "IAM role ARN used for S3 replication"
  value       = var.enable_s3_replication ? aws_iam_role.s3_replication[0].arn : null
}

output "dr_kms_key_arn" {
  description = "KMS key ARN in DR region for replication encryption"
  value       = var.enable_s3_replication ? aws_kms_key.dr_replication[0].arn : null
}

output "s3_replication_configuration" {
  description = "Summary of S3 cross-region replication configuration"
  value = var.enable_s3_replication ? {
    enabled                   = true
    source_region             = var.aws_region
    destination_region        = var.dr_region
    alb_logs_source           = module.loadbalancer.alb_logs_bucket_id
    alb_logs_destination      = aws_s3_bucket.alb_logs_dr[0].id
    cloudtrail_source         = var.enable_cloudtrail ? module.security_compliance.cloudtrail_s3_bucket : null
    cloudtrail_destination    = var.enable_cloudtrail ? aws_s3_bucket.cloudtrail_dr[0].id : null
    replication_time_control  = "15 minutes"
    delete_marker_replication = true
    encryption                = "KMS"
    } : {
    enabled = false
    message = "S3 cross-region replication is disabled. Set enable_s3_replication = true to enable DR."
  }
}

# -----------------------------------------------------------------------------
# Route53 DNS Failover Outputs
# -----------------------------------------------------------------------------

output "route53_health_check_id" {
  description = "ID of the Route53 health check for the ALB"
  value       = local.route53_enabled ? aws_route53_health_check.alb_primary[0].id : null
}

output "route53_health_check_fqdn" {
  description = "FQDN being monitored by the Route53 health check"
  value       = local.route53_enabled ? aws_route53_health_check.alb_primary[0].fqdn : null
}

output "route53_primary_record" {
  description = "Route53 primary failover record FQDN"
  value       = local.route53_enabled ? aws_route53_record.primary[0].fqdn : null
}

output "maintenance_page_url" {
  description = "URL of the S3 maintenance page (for testing)"
  value       = local.route53_enabled && var.enable_maintenance_page ? "http://${aws_s3_bucket_website_configuration.maintenance[0].website_endpoint}" : null
}

output "route53_failover_configuration" {
  description = "Route53 failover configuration summary"
  value = local.route53_enabled ? {
    enabled               = true
    domain                = var.domain_name
    hosted_zone_id        = data.aws_route53_zone.main[0].zone_id
    health_check_id       = aws_route53_health_check.alb_primary[0].id
    health_check_type     = local.has_certificate ? "HTTPS" : "HTTP"
    health_check_path     = "/health/ready"
    health_check_interval = var.route53_health_check_interval
    failure_threshold     = var.route53_health_check_failure_threshold
    maintenance_page      = var.enable_maintenance_page
    maintenance_bucket    = var.enable_maintenance_page ? aws_s3_bucket.maintenance[0].bucket : null
    maintenance_url       = var.enable_maintenance_page ? "http://${aws_s3_bucket_website_configuration.maintenance[0].website_endpoint}" : null
    cloudwatch_alarm      = aws_cloudwatch_metric_alarm.route53_health_check[0].alarm_name
    } : {
    enabled = false
    message = "Route53 failover is disabled. Set domain_name and enable_route53_failover = true to enable."
  }
}

# -----------------------------------------------------------------------------
# Security Groups Outputs
# -----------------------------------------------------------------------------

output "security_group_ids" {
  description = "Map of all security group IDs"
  value       = module.security_groups.all_security_group_ids
}

# -----------------------------------------------------------------------------
# ECR Cross-Region Replication Outputs
# -----------------------------------------------------------------------------

output "ecr_replication_enabled" {
  description = "Whether ECR cross-region replication is enabled"
  value       = var.enable_ecr_replication && var.ecs_enabled
}

output "ecr_dr_repository_url" {
  description = "ECR DR repository URL for container images"
  value       = var.enable_ecr_replication && var.ecs_enabled ? aws_ecr_repository.liberty_dr[0].repository_url : null
}

output "ecr_dr_repository_arn" {
  description = "ECR DR repository ARN"
  value       = var.enable_ecr_replication && var.ecs_enabled ? aws_ecr_repository.liberty_dr[0].arn : null
}

output "ecr_replication_configuration" {
  description = "Summary of ECR cross-region replication configuration"
  value = var.enable_ecr_replication && var.ecs_enabled ? {
    enabled            = true
    source_region      = var.aws_region
    destination_region = var.dr_region
    source_repository  = module.ecs[0].ecr_repository_url
    dr_repository      = aws_ecr_repository.liberty_dr[0].repository_url
    filter_prefix      = local.name_prefix
    filter_type        = "PREFIX_MATCH"
    image_scanning     = true
    encryption         = "AES256"
    lifecycle_policy   = "7 days untagged, keep last 10 tagged"
    } : {
    enabled = false
    message = "ECR cross-region replication is disabled. Set enable_ecr_replication = true and ecs_enabled = true to enable."
  }
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
    environment             = var.environment
    region                  = var.aws_region
    vpc_id                  = module.networking.vpc_id
    ecs_enabled             = var.ecs_enabled
    ec2_count               = var.liberty_instance_count
    monitoring              = var.create_monitoring_server
    management              = var.create_management_server
    app_url                 = module.loadbalancer.app_url
    db_endpoint             = module.database.db_effective_endpoint
    cache_endpoint          = module.database.cache_endpoint
    grafana_url             = var.create_monitoring_server ? module.monitoring[0].grafana_url : null
    awx_url                 = var.create_management_server ? "http://${aws_eip.management[0].public_ip}:30080" : null
    waf_enabled             = var.enable_waf
    guardduty_enabled       = var.enable_guardduty
    cloudtrail_enabled      = var.enable_cloudtrail
    slo_alarms_enabled      = var.enable_slo_alarms
    s3_replication_enabled  = var.enable_s3_replication
    ecr_replication_enabled = var.enable_ecr_replication && var.ecs_enabled
    dr_region               = var.enable_s3_replication || var.enable_ecr_replication ? var.dr_region : null
  }
}
