# =============================================================================
# Main Configuration - Module Orchestration
# =============================================================================
# This file wires together all infrastructure modules for the unified AWS
# environment. Modules are called in dependency order with outputs passed
# between them to ensure proper resource relationships.
#
# Usage:
#   terraform init
#   terraform plan -var-file=envs/prod.tfvars
#   terraform apply -var-file=envs/prod.tfvars
# =============================================================================

# -----------------------------------------------------------------------------
# Networking Module
# -----------------------------------------------------------------------------
# Creates VPC, subnets, NAT gateway, internet gateway, and route tables.
# This is the foundation that all other resources depend on.
# -----------------------------------------------------------------------------

module "networking" {
  source = "../../modules/networking"

  name_prefix                 = local.name_prefix
  vpc_cidr                    = var.vpc_cidr
  availability_zones          = var.availability_zones
  high_availability_nat       = var.high_availability_nat
  enable_dns_hostnames        = true
  enable_dns_support          = true
  enable_nat_gateway          = true
  enable_flow_logs            = true
  enable_flow_logs_encryption = true
  flow_logs_traffic_type      = "ALL"
  flow_logs_retention_days    = 30
  aws_region                  = var.aws_region
  tags                        = local.common_tags
}

# -----------------------------------------------------------------------------
# Security Groups Module
# -----------------------------------------------------------------------------
# Creates security groups for ALB, ECS, Liberty EC2, database, cache,
# monitoring, and management servers.
# -----------------------------------------------------------------------------

module "security_groups" {
  source = "../../modules/security-groups"

  name_prefix = local.name_prefix
  vpc_id      = module.networking.vpc_id
  vpc_cidr    = module.networking.vpc_cidr
  tags        = local.common_tags

  # Security group creation flags based on deployment options
  create_liberty_sg    = var.liberty_instance_count > 0
  create_ecs_sg        = var.ecs_enabled
  create_monitoring_sg = var.create_monitoring_server
  create_management_sg = false # AWX/Jenkins management server
  create_bastion_sg    = false # No bastion in this deployment
  create_rds_proxy_sg  = var.enable_rds_proxy

  # Restrict egress for security compliance
  restrict_egress = true

  # Allowed CIDRs for management access
  monitoring_allowed_cidrs = var.management_allowed_cidrs
  management_allowed_cidrs = var.management_allowed_cidrs
  bastion_allowed_cidrs    = var.allowed_ssh_cidr_blocks
}

# -----------------------------------------------------------------------------
# Database Module
# -----------------------------------------------------------------------------
# Creates RDS PostgreSQL, ElastiCache Redis, and optionally RDS Proxy.
# Credentials are auto-generated and stored in Secrets Manager.
# -----------------------------------------------------------------------------

module "database" {
  source = "../../modules/database"

  name_prefix             = local.name_prefix
  aws_region              = var.aws_region
  vpc_id                  = module.networking.vpc_id
  private_subnet_ids      = module.networking.private_subnet_ids
  db_security_group_id    = module.security_groups.db_security_group_id
  cache_security_group_id = module.security_groups.cache_security_group_id
  tags                    = local.common_tags

  # RDS Configuration
  db_instance_class               = var.db_instance_class
  db_allocated_storage            = var.db_allocated_storage
  db_name                         = var.db_name
  db_username                     = var.db_username
  db_multi_az                     = var.db_multi_az
  db_backup_retention             = var.db_backup_retention_period
  db_deletion_protection          = var.environment == "prod" || var.environment == "production"
  db_performance_insights_enabled = true
  db_monitoring_interval          = 60

  # ElastiCache Configuration
  cache_node_type = var.cache_node_type
  cache_multi_az  = var.cache_multi_az

  # RDS Proxy Configuration (optional)
  enable_rds_proxy                  = var.enable_rds_proxy
  rds_proxy_security_group_id       = var.enable_rds_proxy ? module.security_groups.rds_proxy_security_group_id : ""
  rds_proxy_idle_timeout            = var.rds_proxy_idle_timeout
  rds_proxy_max_connections_percent = var.rds_proxy_max_connections_percent
  rds_proxy_require_iam             = false
  enable_rds_proxy_read_endpoint    = false
}

# -----------------------------------------------------------------------------
# Load Balancer Module
# -----------------------------------------------------------------------------
# Creates Application Load Balancer with target groups for ECS and/or EC2.
# Supports HTTPS with provided or self-signed certificates.
# -----------------------------------------------------------------------------

module "loadbalancer" {
  source = "../../modules/loadbalancer"

  name_prefix           = local.name_prefix
  aws_region            = var.aws_region
  vpc_id                = module.networking.vpc_id
  public_subnet_ids     = module.networking.public_subnet_ids
  alb_security_group_id = module.security_groups.alb_security_group_id
  tags                  = local.common_tags

  # ALB Configuration
  internal                   = false
  idle_timeout               = 60
  enable_deletion_protection = var.environment == "prod" || var.environment == "production"

  # HTTPS Configuration
  enable_https    = var.enable_https
  certificate_arn = var.certificate_arn

  # Access Logs
  enable_access_logs         = true
  access_logs_retention_days = 90

  # Target Groups - create based on deployment type
  create_ecs_target_group = var.ecs_enabled
  create_ec2_target_group = var.liberty_instance_count > 0
  target_port             = 9080

  # Health Check Configuration
  health_check_path                = "/health/ready"
  health_check_healthy_threshold   = 2
  health_check_unhealthy_threshold = 3
  health_check_timeout             = 5
  health_check_interval            = 30
  health_check_matcher             = "200"

  # Session Stickiness
  stickiness_enabled  = true
  stickiness_duration = 86400

  # Security - block public access to metrics endpoint
  block_metrics_endpoint = true
}

# -----------------------------------------------------------------------------
# ECS Module (Conditional)
# -----------------------------------------------------------------------------
# Creates ECS Fargate cluster, service, task definition, and ECR repository.
# Includes auto-scaling policies and optional blue-green deployment support.
# -----------------------------------------------------------------------------

module "ecs" {
  count  = var.ecs_enabled ? 1 : 0
  source = "../../modules/ecs"

  name_prefix        = local.name_prefix
  aws_region         = var.aws_region
  private_subnet_ids = module.networking.private_subnet_ids
  security_group_ids = [module.security_groups.ecs_security_group_id]
  tags               = local.common_tags

  # Container Configuration
  container_name        = "liberty"
  container_image       = local.container_image != null ? local.container_image : "${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${local.name_prefix}-liberty:${var.container_image_tag}"
  task_cpu              = var.ecs_task_cpu
  task_memory           = var.ecs_task_memory
  desired_count         = var.ecs_desired_count
  create_ecr_repository = true

  # Environment Variables for Container
  environment_variables = [
    {
      name  = "ENVIRONMENT"
      value = var.environment
    },
    {
      name  = "DB_HOST"
      value = var.enable_rds_proxy ? module.database.rds_proxy_endpoint : module.database.db_endpoint
    },
    {
      name  = "DB_PORT"
      value = tostring(module.database.db_port)
    },
    {
      name  = "DB_NAME"
      value = module.database.db_name
    },
    {
      name  = "CACHE_HOST"
      value = module.database.cache_endpoint
    },
    {
      name  = "CACHE_PORT"
      value = tostring(module.database.cache_port)
    }
  ]

  # Secrets from Secrets Manager
  secrets = [
    {
      name      = "DB_PASSWORD"
      valueFrom = "${module.database.db_secret_arn}:password::"
    },
    {
      name      = "CACHE_AUTH_TOKEN"
      valueFrom = "${module.database.cache_auth_token_secret_arn}:auth_token::"
    }
  ]
  secrets_arns = [
    module.database.db_secret_arn,
    module.database.cache_auth_token_secret_arn
  ]

  # Load Balancer Integration
  target_group_arn = module.loadbalancer.ecs_target_group_arn
  alb_arn_suffix   = module.loadbalancer.alb_arn_suffix

  # Cluster Settings
  enable_container_insights = true
  enable_execute_command    = true
  log_retention_days        = 30

  # Auto-Scaling Configuration
  enable_autoscaling     = true
  enable_request_scaling = true
  min_capacity           = var.ecs_min_capacity
  max_capacity           = var.ecs_max_capacity
  cpu_target             = var.ecs_cpu_target
  memory_target          = var.ecs_memory_target
  request_count_target   = var.ecs_requests_per_target
  scale_in_cooldown      = 300
  scale_out_cooldown     = 60

  # Fargate Spot for cost savings
  fargate_spot_weight = var.fargate_spot_weight

  # Blue-Green Deployment (optional)
  enable_blue_green                   = var.enable_blue_green
  vpc_id                              = module.networking.vpc_id
  listener_arn                        = module.loadbalancer.http_listener_arn
  codedeploy_deployment_config        = "CodeDeployDefault.ECSLinear10PercentEvery1Minutes"
  blue_green_termination_wait_minutes = 5

  # Observability
  enable_xray          = var.enable_xray
  enable_slo_alarms    = var.environment == "prod" || var.environment == "production"
  slo_cpu_threshold    = 85
  slo_memory_threshold = 85
}

# -----------------------------------------------------------------------------
# Compute Module (Conditional - EC2 Liberty Instances)
# -----------------------------------------------------------------------------
# Creates EC2 instances for Liberty application servers when not using ECS.
# Instances are distributed across private subnets for high availability.
# -----------------------------------------------------------------------------

module "compute" {
  count  = var.liberty_instance_count > 0 ? 1 : 0
  source = "../../modules/compute"

  name_prefix        = "${local.name_prefix}-liberty"
  aws_region         = var.aws_region
  instance_count     = var.liberty_instance_count
  instance_type      = var.liberty_instance_type
  subnet_ids         = module.networking.private_subnet_ids
  security_group_ids = [module.security_groups.liberty_security_group_id]
  tags               = local.common_tags

  # AMI Configuration
  ami_id = null # Uses latest Ubuntu 22.04 LTS

  # SSH Key Configuration
  create_key_pair = true
  ssh_public_key  = local.ssh_public_key

  # IAM Configuration
  create_iam_role = true
  enable_ssm      = true
  iam_inline_policy_statements = [
    {
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = [
        module.database.db_secret_arn,
        module.database.cache_auth_token_secret_arn
      ]
    },
    {
      Effect   = "Allow"
      Action   = ["ecr:GetAuthorizationToken", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
      Resource = ["*"]
    }
  ]

  # Storage Configuration
  root_volume_size      = 30
  root_volume_type      = "gp3"
  root_volume_encrypted = true

  # Instance Metadata Service (IMDSv2 required for security)
  require_imdsv2 = true
  imds_hop_limit = 1

  # Monitoring
  detailed_monitoring         = false
  create_cloudwatch_log_group = true
  log_retention_days          = 30

  # Instance tags for Ansible targeting
  instance_tags = {
    Role = "liberty"
    Tier = "application"
  }
}

# -----------------------------------------------------------------------------
# Monitoring SSH Key (Conditional)
# -----------------------------------------------------------------------------
# Creates an SSH key pair for the monitoring server when the compute module
# is not being created (i.e., when liberty_instance_count = 0).
# -----------------------------------------------------------------------------

resource "tls_private_key" "monitoring" {
  count     = var.create_monitoring_server && var.liberty_instance_count == 0 ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "monitoring" {
  count      = var.create_monitoring_server && var.liberty_instance_count == 0 ? 1 : 0
  key_name   = "${local.name_prefix}-monitoring"
  public_key = tls_private_key.monitoring[0].public_key_openssh

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-monitoring-key"
  })
}

resource "local_file" "monitoring_private_key" {
  count           = var.create_monitoring_server && var.liberty_instance_count == 0 ? 1 : 0
  content         = tls_private_key.monitoring[0].private_key_pem
  filename        = pathexpand("~/.ssh/${local.name_prefix}-monitoring.pem")
  file_permission = "0400"
}

# -----------------------------------------------------------------------------
# Monitoring Module (Conditional)
# -----------------------------------------------------------------------------
# Creates dedicated EC2 instance with Prometheus, Grafana, and AlertManager.
# Supports ECS service discovery and static EC2 targets.
# -----------------------------------------------------------------------------

module "monitoring" {
  count  = var.create_monitoring_server ? 1 : 0
  source = "../../modules/monitoring"

  name_prefix  = local.name_prefix
  aws_region   = var.aws_region
  vpc_id       = module.networking.vpc_id
  vpc_cidr     = module.networking.vpc_cidr
  subnet_id    = module.networking.public_subnet_ids[0]
  ami_id       = data.aws_ami.ubuntu.id
  ssh_key_name = var.liberty_instance_count > 0 ? module.compute[0].ssh_key_name : aws_key_pair.monitoring[0].key_name
  tags         = local.common_tags

  # Security Group
  create_security_group = false
  security_group_id     = module.security_groups.monitoring_security_group_id
  allowed_cidrs         = var.management_allowed_cidrs

  # Instance Configuration
  instance_type     = var.monitoring_instance_type
  root_volume_size  = 30
  create_elastic_ip = true

  # ECS Service Discovery (when ECS is enabled)
  ecs_cluster_name = var.ecs_enabled ? module.ecs[0].cluster_name : ""

  # Static Targets for EC2 Liberty instances
  liberty_targets = var.liberty_instance_count > 0 ? [
    for ip in module.compute[0].instance_private_ips : "${ip}:9080"
  ] : []

  # Add target SG for scraping Liberty instances
  enable_target_monitoring_rules = var.liberty_instance_count > 0
  target_security_group_id       = var.liberty_instance_count > 0 ? module.security_groups.liberty_security_group_id : ""

  # Prometheus Configuration
  prometheus_retention_days = 15

  # AlertManager Configuration
  alertmanager_slack_secret_arn = var.alertmanager_slack_secret_arn
  alertmanager_config = {
    slack_channel    = "#middleware-${var.environment}"
    critical_channel = "#middleware-critical"
    email_to         = var.security_alert_email
    email_from       = ""
    smtp_host        = ""
  }

  # Logging
  log_retention_days = 30
}

# -----------------------------------------------------------------------------
# Security Compliance Module
# -----------------------------------------------------------------------------
# Creates CloudTrail, GuardDuty, Security Hub, and WAF resources.
# Provides audit logging, threat detection, and web application protection.
# -----------------------------------------------------------------------------

module "security_compliance" {
  source = "../../modules/security-compliance"

  name_prefix = local.name_prefix
  aws_region  = var.aws_region
  tags        = local.common_tags

  # CloudTrail Configuration
  enable_cloudtrail             = var.enable_cloudtrail
  cloudtrail_log_retention_days = var.cloudtrail_log_retention_days

  # GuardDuty and Security Hub
  enable_guardduty = var.enable_guardduty

  # WAF Configuration
  enable_waf         = var.enable_waf
  waf_rate_limit     = var.waf_rate_limit
  waf_enable_logging = var.waf_enable_logging
  alb_arn            = module.loadbalancer.alb_arn
  attach_waf_to_alb  = true

  # Security Alerts
  security_alert_email = var.security_alert_email
}

# -----------------------------------------------------------------------------
# ALB Target Group Attachments (EC2 Instances)
# -----------------------------------------------------------------------------
# When EC2 Liberty instances are created, attach them to the ALB target group.
# -----------------------------------------------------------------------------

resource "aws_lb_target_group_attachment" "liberty_ec2" {
  count            = var.liberty_instance_count > 0 ? var.liberty_instance_count : 0
  target_group_arn = module.loadbalancer.ec2_target_group_arn
  target_id        = module.compute[0].instance_ids[count.index]
  port             = 9080
}
