# =============================================================================
# Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# VPC Outputs
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
  description = "IDs of the public subnets"
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.networking.private_subnet_ids
}

# -----------------------------------------------------------------------------
# ALB Outputs
# -----------------------------------------------------------------------------
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.main.zone_id
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

output "app_url" {
  description = "Application URL"
  value       = local.has_certificate ? "https://${var.domain_name}" : "http://${aws_lb.main.dns_name}"
}

# -----------------------------------------------------------------------------
# EC2 Outputs
# -----------------------------------------------------------------------------
output "liberty_instance_ids" {
  description = "IDs of the Liberty EC2 instances"
  value       = aws_instance.liberty[*].id
}

output "liberty_private_ips" {
  description = "Private IPs of the Liberty EC2 instances"
  value       = aws_instance.liberty[*].private_ip
}

output "liberty_instance_profiles" {
  description = "IAM instance profiles attached to Liberty instances"
  value       = aws_iam_instance_profile.liberty.name
}

# -----------------------------------------------------------------------------
# Database Outputs
# -----------------------------------------------------------------------------
output "db_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = aws_db_instance.main.endpoint
}

output "db_address" {
  description = "RDS PostgreSQL address (hostname only)"
  value       = aws_db_instance.main.address
}

output "db_port" {
  description = "RDS PostgreSQL port"
  value       = aws_db_instance.main.port
}

output "db_credentials_secret_arn" {
  description = "ARN of the Secrets Manager secret containing DB credentials"
  value       = aws_secretsmanager_secret.db_credentials.arn
  sensitive   = true
}

# -----------------------------------------------------------------------------
# RDS Read Replica Outputs
# -----------------------------------------------------------------------------
output "db_replica_endpoint" {
  description = "RDS PostgreSQL read replica endpoint (hostname:port)"
  value       = var.db_create_read_replica ? aws_db_instance.replica[0].endpoint : null
}

output "db_replica_address" {
  description = "RDS PostgreSQL read replica address (hostname only)"
  value       = var.db_create_read_replica ? aws_db_instance.replica[0].address : null
}

output "db_replica_arn" {
  description = "ARN of the RDS read replica"
  value       = var.db_create_read_replica ? aws_db_instance.replica[0].arn : null
}

output "db_replica_configuration" {
  description = "RDS read replica configuration summary"
  value = var.db_create_read_replica ? {
    enabled              = true
    endpoint             = aws_db_instance.replica[0].endpoint
    address              = aws_db_instance.replica[0].address
    instance_class       = aws_db_instance.replica[0].instance_class
    performance_insights = true
    source_db            = aws_db_instance.main.identifier
    promotion_tier       = "Can be promoted to standalone primary"
    use_case             = "Read scaling and disaster recovery"
    } : {
    enabled = false
    message = "RDS read replica is disabled. Set db_create_read_replica = true to enable disaster recovery."
  }
}

# -----------------------------------------------------------------------------
# RDS Proxy Outputs
# -----------------------------------------------------------------------------
output "rds_proxy_endpoint" {
  description = "RDS Proxy endpoint (use this instead of direct RDS endpoint when proxy is enabled)"
  value       = var.enable_rds_proxy ? aws_db_proxy.main[0].endpoint : null
}

output "rds_proxy_arn" {
  description = "ARN of the RDS Proxy"
  value       = var.enable_rds_proxy ? aws_db_proxy.main[0].arn : null
}

output "rds_proxy_read_endpoint" {
  description = "RDS Proxy read-only endpoint (for read scaling)"
  value       = var.enable_rds_proxy && var.enable_rds_proxy_read_endpoint ? aws_db_proxy_endpoint.read_only[0].endpoint : null
}

output "rds_proxy_configuration" {
  description = "RDS Proxy configuration summary"
  value = var.enable_rds_proxy ? {
    enabled                 = true
    endpoint                = aws_db_proxy.main[0].endpoint
    read_endpoint           = var.enable_rds_proxy_read_endpoint ? aws_db_proxy_endpoint.read_only[0].endpoint : null
    iam_auth_required       = var.rds_proxy_require_iam
    idle_timeout_seconds    = var.rds_proxy_idle_timeout
    max_connections_percent = var.rds_proxy_max_connections_percent
    tls_required            = true
    } : {
    enabled = false
    message = "RDS Proxy is disabled. Set enable_rds_proxy = true to enable connection pooling and IAM authentication."
  }
}

output "db_effective_endpoint" {
  description = "Effective database endpoint (RDS Proxy if enabled, otherwise direct RDS)"
  value       = var.enable_rds_proxy ? aws_db_proxy.main[0].endpoint : aws_db_instance.main.address
}

# -----------------------------------------------------------------------------
# Cache Outputs
# -----------------------------------------------------------------------------
output "redis_endpoint" {
  description = "ElastiCache Redis endpoint"
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
}

output "redis_port" {
  description = "ElastiCache Redis port"
  value       = 6379
}

# -----------------------------------------------------------------------------
# Security Group Outputs
# -----------------------------------------------------------------------------
output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "liberty_security_group_id" {
  description = "ID of the Liberty security group"
  value       = aws_security_group.liberty.id
}

output "db_security_group_id" {
  description = "ID of the database security group"
  value       = aws_security_group.db.id
}

# -----------------------------------------------------------------------------
# SSH Access
# -----------------------------------------------------------------------------
output "ssh_key_name" {
  description = "Name of the SSH key pair"
  value       = aws_key_pair.deployer.key_name
}

# -----------------------------------------------------------------------------
# ECR Outputs
# -----------------------------------------------------------------------------
output "ecr_repository_url" {
  description = "URL of the ECR repository for Liberty images"
  value       = aws_ecr_repository.liberty.repository_url
}

output "ecr_repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.liberty.arn
}

output "ecr_push_commands" {
  description = "Commands to build and push Liberty image to ECR"
  value       = <<-EOT

    # Login to ECR
    aws ecr get-login-password --region ${data.aws_region.current.name} | \
      podman login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com

    # Build the image (from repo root)
    mvn -f sample-app/pom.xml clean package
    cp sample-app/target/*.war containers/liberty/apps/
    podman build -t liberty-app:latest containers/liberty/

    # Tag and push
    podman tag liberty-app:latest ${aws_ecr_repository.liberty.repository_url}:latest
    podman push ${aws_ecr_repository.liberty.repository_url}:latest

  EOT
}

# -----------------------------------------------------------------------------
# ECR Cross-Region Replication Outputs
# -----------------------------------------------------------------------------
output "ecr_dr_repository_url" {
  description = "URL of the ECR repository in the DR region for Liberty images"
  value       = var.ecr_replication_enabled ? aws_ecr_repository.liberty_dr[0].repository_url : null
}

output "ecr_dr_repository_arn" {
  description = "ARN of the ECR repository in the DR region"
  value       = var.ecr_replication_enabled ? aws_ecr_repository.liberty_dr[0].arn : null
}

output "ecr_replication_configuration" {
  description = "ECR cross-region replication configuration summary"
  value = var.ecr_replication_enabled ? {
    enabled            = true
    primary_region     = data.aws_region.current.name
    primary_repository = aws_ecr_repository.liberty.repository_url
    dr_region          = var.ecr_replication_region
    dr_repository      = aws_ecr_repository.liberty_dr[0].repository_url
    replication_filter = "${local.name_prefix}-liberty"
    auto_sync          = "Images are automatically replicated on push"
    } : {
    enabled = false
    message = "ECR cross-region replication is disabled. Set ecr_replication_enabled = true to enable disaster recovery for container images."
  }
}

# -----------------------------------------------------------------------------
# ECS Outputs
# -----------------------------------------------------------------------------
output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = var.ecs_enabled ? aws_ecs_cluster.main[0].name : null
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = var.ecs_enabled ? aws_ecs_service.liberty[0].name : null
}

output "ecs_scaling_config" {
  description = "ECS auto-scaling configuration"
  value = var.ecs_enabled ? {
    min_capacity        = var.ecs_min_capacity
    max_capacity        = var.ecs_max_capacity
    cpu_target          = var.ecs_cpu_target
    memory_target       = var.ecs_memory_target
    requests_per_target = var.ecs_requests_per_target
  } : null
}

# -----------------------------------------------------------------------------
# CodeDeploy Blue-Green Deployment Outputs
# -----------------------------------------------------------------------------
output "codedeploy_app_name" {
  description = "Name of the CodeDeploy application for ECS Blue-Green deployments"
  value       = var.ecs_enabled && var.enable_blue_green ? aws_codedeploy_app.ecs_liberty[0].name : null
}

output "codedeploy_deployment_group_name" {
  description = "Name of the CodeDeploy deployment group"
  value       = var.ecs_enabled && var.enable_blue_green ? aws_codedeploy_deployment_group.ecs_liberty[0].deployment_group_name : null
}

output "blue_green_deployment_config" {
  description = "Blue-Green deployment configuration summary"
  value = var.ecs_enabled && var.enable_blue_green ? {
    enabled              = true
    app_name             = aws_codedeploy_app.ecs_liberty[0].name
    deployment_group     = aws_codedeploy_deployment_group.ecs_liberty[0].deployment_group_name
    deployment_config    = "CodeDeployDefault.ECSLinear10PercentEvery1Minutes"
    blue_target_group    = aws_lb_target_group.liberty_ecs[0].name
    green_target_group   = aws_lb_target_group.liberty_ecs_green[0].name
    auto_rollback        = true
    termination_wait_min = 5
    } : {
    enabled = false
    message = "Blue-Green deployments are disabled. Set enable_blue_green = true to enable."
  }
}

# -----------------------------------------------------------------------------
# Ansible Inventory Helper
# -----------------------------------------------------------------------------
output "ansible_inventory" {
  description = "Ansible inventory content for this environment"
  value       = <<-EOT

    # Add this to your Ansible inventory or use AWS EC2 dynamic inventory
    # File: automated/ansible/inventory/prod-aws.yml

    [liberty_servers]
    %{for idx, instance in aws_instance.liberty~}
    liberty-prod-0${idx + 1} ansible_host=${instance.private_ip} liberty_server_name=appServer0${idx + 1}
    %{endfor~}

    [liberty_servers:vars]
    ansible_user=ansible
    ansible_ssh_private_key_file=~/.ssh/id_rsa

    # Database connection
    db_host=${aws_db_instance.main.address}
    db_port=${aws_db_instance.main.port}
    db_name=${var.db_name}

    # Redis connection
    redis_host=${aws_elasticache_replication_group.main.primary_endpoint_address}
    redis_port=6379

  EOT
}

# -----------------------------------------------------------------------------
# Cost Estimation
# -----------------------------------------------------------------------------
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown"
  value       = <<-EOT

    ═══════════════════════════════════════════════════════
    ESTIMATED MONTHLY COSTS (us-east-1)
    ═══════════════════════════════════════════════════════

    EC2 Liberty ${var.liberty_instance_type} x${var.liberty_instance_count}:  ~$${var.liberty_instance_count * 15}
    EC2 Management t3.medium:                        ~$30
    RDS ${var.db_instance_class}:                    ~$15
    ElastiCache ${var.cache_node_type}:              ~$12
    Application Load Balancer:                       ~$20
    NAT Gateway + Data Transfer:                     ~$35
    Elastic IP (management):                         ~$4
    S3 (logs/state):                                 ~$5
    CloudWatch Logs:                                 ~$5
    ───────────────────────────────────────────────────────
    TOTAL:                                           ~$${(var.liberty_instance_count * 15) + 30 + 15 + 12 + 20 + 35 + 4 + 5 + 5}

    Note: Actual costs may vary based on usage patterns.
    Management server can be stopped when not in use to save ~$30/month.

  EOT
}

# -----------------------------------------------------------------------------
# GuardDuty and Security Hub Outputs
# -----------------------------------------------------------------------------
output "guardduty_detector_id" {
  description = "ID of the GuardDuty detector"
  value       = var.enable_guardduty ? aws_guardduty_detector.main[0].id : null
}

output "securityhub_enabled" {
  description = "Whether Security Hub is enabled"
  value       = var.enable_guardduty
}

output "security_alerts_topic_arn" {
  description = "ARN of the SNS topic for security alerts"
  value       = var.enable_guardduty && var.security_alert_email != "" ? aws_sns_topic.security_alerts[0].arn : null
}

output "security_configuration" {
  description = "Summary of security services configuration"
  value = var.enable_guardduty ? {
    guardduty_enabled        = true
    guardduty_detector_id    = aws_guardduty_detector.main[0].id
    s3_protection_enabled    = true
    ebs_malware_protection   = true
    finding_frequency        = "FIFTEEN_MINUTES"
    securityhub_enabled      = true
    cis_benchmark_enabled    = true
    aws_foundational_enabled = true
    alerts_email             = var.security_alert_email != "" ? var.security_alert_email : "not configured"
    alert_severity_threshold = "High (>=7) for GuardDuty, CRITICAL/HIGH for Security Hub"
    } : {
    guardduty_enabled = false
    message           = "GuardDuty and Security Hub are disabled. Set enable_guardduty = true to enable."
  }
}
