# =============================================================================
# Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# VPC Outputs
# -----------------------------------------------------------------------------
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
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
}

# -----------------------------------------------------------------------------
# Cache Outputs
# -----------------------------------------------------------------------------
output "redis_endpoint" {
  description = "ElastiCache Redis endpoint"
  value       = aws_elasticache_cluster.main.cache_nodes[0].address
}

output "redis_port" {
  description = "ElastiCache Redis port"
  value       = aws_elasticache_cluster.main.cache_nodes[0].port
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
    redis_host=${aws_elasticache_cluster.main.cache_nodes[0].address}
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
