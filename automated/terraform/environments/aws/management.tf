# =============================================================================
# Management Server - AWX/Jenkins for CI/CD and Automation
# =============================================================================
# This instance runs in a public subnet and can manage all other instances
# via SSM (no VPC peering required for multi-region).
# Controlled by var.create_management_server variable.
# =============================================================================

# -----------------------------------------------------------------------------
# Security Group
# -----------------------------------------------------------------------------
resource "aws_security_group" "management" {
  count = var.create_management_server ? 1 : 0

  name        = "${local.name_prefix}-mgmt-sg"
  description = "Security group for AWX/Jenkins management server"
  vpc_id      = module.networking.vpc_id

  # SSH
  ingress {
    description = "SSH from allowed CIDRs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.management_allowed_cidrs
  }

  # AWX Web UI (NodePort)
  ingress {
    description = "AWX NodePort"
    from_port   = 30080
    to_port     = 30080
    protocol    = "tcp"
    cidr_blocks = var.management_allowed_cidrs
  }

  # Jenkins
  ingress {
    description = "Jenkins"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.management_allowed_cidrs
  }

  # Prometheus (for monitoring)
  ingress {
    description = "Prometheus"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = var.management_allowed_cidrs
  }

  # Grafana
  ingress {
    description = "Grafana"
    from_port   = 3000
    to_port     = 3000
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

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mgmt-sg"
  })
}

# -----------------------------------------------------------------------------
# IAM Role - Least-Privilege Custom Policies
# -----------------------------------------------------------------------------
# SECURITY: Uses scoped custom policies instead of AWS managed FullAccess policies.
# Each policy grants only the minimum permissions needed for AWX/Ansible operations.
# -----------------------------------------------------------------------------
resource "aws_iam_role" "management" {
  count = var.create_management_server ? 1 : 0

  name = "${local.name_prefix}-mgmt-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mgmt-role"
  })
}

# -----------------------------------------------------------------------------
# Custom IAM Policy: EC2 Management (Scoped)
# -----------------------------------------------------------------------------
# Purpose: Ansible dynamic inventory and instance start/stop for cost management
# Replaces: AmazonEC2FullAccess
resource "aws_iam_role_policy" "management_ec2" {
  count = var.create_management_server ? 1 : 0

  name = "${local.name_prefix}-mgmt-ec2"
  role = aws_iam_role.management[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2DescribeForInventory"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeTags",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:DescribeRegions",
          "ec2:DescribeAvailabilityZones"
        ]
        Resource = "*" # Describe operations require wildcard per AWS docs
      },
      {
        Sid    = "EC2InstanceManagement"
        Effect = "Allow"
        Action = [
          "ec2:StartInstances",
          "ec2:StopInstances",
          "ec2:RebootInstances"
        ]
        Resource = "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project" = var.project
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Custom IAM Policy: ECS Deployment (Scoped)
# -----------------------------------------------------------------------------
# Purpose: Deploy Liberty containers to ECS via update-service
# Used by: Jenkinsfile, aws ecs update-service --force-new-deployment
resource "aws_iam_role_policy" "management_ecs" {
  count = var.create_management_server && var.ecs_enabled ? 1 : 0

  name = "${local.name_prefix}-mgmt-ecs"
  role = aws_iam_role.management[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECSReadOperations"
        Effect = "Allow"
        Action = [
          "ecs:DescribeClusters",
          "ecs:DescribeServices",
          "ecs:DescribeTasks",
          "ecs:DescribeTaskDefinition",
          "ecs:ListClusters",
          "ecs:ListServices",
          "ecs:ListTasks"
        ]
        Resource = "*" # Describe/List operations require wildcard
      },
      {
        Sid    = "ECSServiceUpdate"
        Effect = "Allow"
        Action = [
          "ecs:UpdateService"
        ]
        Resource = "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:service/${local.name_prefix}-cluster/${local.name_prefix}-liberty"
      },
      {
        Sid    = "ECSPassRole"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.name_prefix}-ecs-task-role",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.name_prefix}-ecs-execution-role"
        ]
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Custom IAM Policy: ECR Image Management (Scoped)
# -----------------------------------------------------------------------------
# Purpose: Push Liberty container images to ECR from CI/CD pipeline
# Used by: Jenkinsfile container build stage
resource "aws_iam_role_policy" "management_ecr" {
  count = var.create_management_server ? 1 : 0

  name = "${local.name_prefix}-mgmt-ecr"
  role = aws_iam_role.management[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuthentication"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*" # GetAuthorizationToken requires wildcard
      },
      {
        Sid    = "ECRImageOperations"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:ListImages",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]
        Resource = "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/${local.name_prefix}-*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Custom IAM Policy: Secrets Manager Read-Only (Scoped)
# -----------------------------------------------------------------------------
# Purpose: Ansible fetches database credentials for Liberty configuration
# Used by: automated/ansible/roles/liberty/tasks/main.yml line 72-77
# Replaces: SecretsManagerReadWrite (downgraded to read-only)
resource "aws_iam_role_policy" "management_secrets" {
  count = var.create_management_server ? 1 : 0

  name = "${local.name_prefix}-mgmt-secrets"
  role = aws_iam_role.management[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManagerReadOnly"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${local.name_prefix}/*"
      },
      {
        Sid      = "SecretsManagerList"
        Effect   = "Allow"
        Action   = "secretsmanager:ListSecrets"
        Resource = "*" # ListSecrets requires wildcard
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Custom IAM Policy: CloudWatch Logs (Scoped)
# -----------------------------------------------------------------------------
# Purpose: Write deployment logs from AWX/Jenkins
# Replaces: CloudWatchFullAccess (scoped to write-only, specific log groups)
resource "aws_iam_role_policy" "management_cloudwatch" {
  count = var.create_management_server ? 1 : 0

  name = "${local.name_prefix}-mgmt-cloudwatch"
  role = aws_iam_role.management[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogsWrite"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/${local.name_prefix}/*",
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/${local.name_prefix}/*:log-stream:*"
        ]
      },
      {
        Sid    = "CloudWatchMetricsRead"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*" # Metrics read operations require wildcard
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Custom IAM Policy: S3 Access (Scoped)
# -----------------------------------------------------------------------------
# Purpose: Access Terraform state bucket and deployment artifacts
# Replaces: AmazonS3FullAccess (scoped to specific bucket patterns)
resource "aws_iam_role_policy" "management_s3" {
  count = var.create_management_server ? 1 : 0

  name = "${local.name_prefix}-mgmt-s3"
  role = aws_iam_role.management[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ListBuckets"
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets",
          "s3:GetBucketLocation"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3ProjectBuckets"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::${local.name_prefix}-*",
          "arn:aws:s3:::${local.name_prefix}-*/*",
          "arn:aws:s3:::${var.project}-terraform-*",
          "arn:aws:s3:::${var.project}-terraform-*/*"
        ]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Custom IAM Policy: SSM Session Manager (Scoped)
# -----------------------------------------------------------------------------
# Purpose: Secure shell access to managed instances without SSH keys
# Replaces: AmazonSSMFullAccess (scoped to project-tagged instances)
resource "aws_iam_role_policy" "management_ssm" {
  count = var.create_management_server ? 1 : 0

  name = "${local.name_prefix}-mgmt-ssm"
  role = aws_iam_role.management[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMDescribe"
        Effect = "Allow"
        Action = [
          "ssm:DescribeInstanceInformation",
          "ssm:GetConnectionStatus",
          "ssm:DescribeSessions",
          "ssm:ListCommands",
          "ssm:ListCommandInvocations"
        ]
        Resource = "*" # SSM describe operations require wildcard
      },
      {
        Sid    = "SSMSessionManagement"
        Effect = "Allow"
        Action = [
          "ssm:StartSession",
          "ssm:TerminateSession",
          "ssm:ResumeSession"
        ]
        Resource = [
          "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*",
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:session/*"
        ]
        Condition = {
          StringEquals = {
            "ssm:resourceTag/Project" = var.project
          }
        }
      },
      {
        Sid    = "SSMSendCommand"
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation"
        ]
        Resource = [
          "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*",
          "arn:aws:ssm:${data.aws_region.current.name}::document/AWS-RunShellScript"
        ]
        Condition = {
          StringEquals = {
            "ssm:resourceTag/Project" = var.project
          }
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "management" {
  count = var.create_management_server ? 1 : 0

  name = "${local.name_prefix}-mgmt-profile"
  role = aws_iam_role.management[0].name
}

# -----------------------------------------------------------------------------
# SSH Key Pair (if not already created by compute module)
# -----------------------------------------------------------------------------
resource "aws_key_pair" "management" {
  count = var.create_management_server && var.liberty_instance_count == 0 ? 1 : 0

  key_name   = "${local.name_prefix}-management"
  public_key = local.ssh_public_key

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-management"
  })
}

# -----------------------------------------------------------------------------
# Elastic IP (stable public IP)
# -----------------------------------------------------------------------------
resource "aws_eip" "management" {
  count = var.create_management_server ? 1 : 0

  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mgmt-eip"
  })
}

resource "aws_eip_association" "management" {
  count = var.create_management_server ? 1 : 0

  instance_id   = aws_instance.management[0].id
  allocation_id = aws_eip.management[0].id
}

# -----------------------------------------------------------------------------
# EC2 Instance
# -----------------------------------------------------------------------------
resource "aws_instance" "management" {
  count = var.create_management_server ? 1 : 0

  ami           = data.aws_ami.ubuntu.id
  instance_type = var.management_instance_type
  key_name = (
    var.liberty_instance_count > 0
    ? module.compute[0].ssh_key_name
    : aws_key_pair.management[0].key_name
  )
  subnet_id              = module.networking.public_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.management[0].id]
  iam_instance_profile   = aws_iam_instance_profile.management[0].name

  root_block_device {
    volume_size           = 50 # More storage for containers/artifacts
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true

    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-mgmt-root"
    })
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(file("${path.module}/templates/management-user-data.sh"))

  tags = merge(local.common_tags, {
    Name         = "${local.name_prefix}-management"
    Role         = "management"
    AnsibleGroup = "management_servers"
  })

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

# -----------------------------------------------------------------------------
# Allow management server to SSH to Liberty instances
# -----------------------------------------------------------------------------
resource "aws_security_group_rule" "liberty_ssh_from_management" {
  count = var.create_management_server && var.liberty_instance_count > 0 ? 1 : 0

  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  security_group_id        = module.security_groups.liberty_security_group_id
  source_security_group_id = aws_security_group.management[0].id
  description              = "SSH from management server"
}
