# =============================================================================
# Compute - EC2 Instances for Liberty
# =============================================================================

# -----------------------------------------------------------------------------
# SSH Key Pair
# -----------------------------------------------------------------------------
resource "aws_key_pair" "deployer" {
  key_name   = "${local.name_prefix}-deployer"
  public_key = file(pathexpand(var.ssh_public_key_path))

  tags = {
    Name = "${local.name_prefix}-deployer-key"
  }
}

# -----------------------------------------------------------------------------
# IAM Role for EC2 Instances
# -----------------------------------------------------------------------------
resource "aws_iam_role" "liberty" {
  name = "${local.name_prefix}-liberty-role"

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

  tags = {
    Name = "${local.name_prefix}-liberty-role"
  }
}

resource "aws_iam_role_policy_attachment" "liberty_ssm" {
  role       = aws_iam_role.liberty.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "liberty_secrets" {
  name = "${local.name_prefix}-liberty-secrets"
  role = aws_iam_role.liberty.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.db_credentials.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          aws_cloudwatch_log_group.liberty.arn,
          "${aws_cloudwatch_log_group.liberty.arn}:*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "liberty" {
  name = "${local.name_prefix}-liberty-profile"
  role = aws_iam_role.liberty.name
}

# -----------------------------------------------------------------------------
# EC2 Instances
# -----------------------------------------------------------------------------
resource "aws_instance" "liberty" {
  count = var.liberty_instance_count

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.liberty_instance_type
  key_name               = aws_key_pair.deployer.key_name
  subnet_id              = module.networking.private_subnet_ids[count.index % var.availability_zones]
  vpc_security_group_ids = [aws_security_group.liberty.id]
  iam_instance_profile   = aws_iam_instance_profile.liberty.name

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "${local.name_prefix}-liberty-${count.index + 1}-root"
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(templatefile("${path.module}/templates/liberty-user-data.sh", {
    aws_region = var.aws_region
  }))

  tags = {
    Name              = "${local.name_prefix}-liberty-${count.index + 1}"
    Role              = "liberty-server"
    LibertyServerName = "appServer0${count.index + 1}"
    AnsibleGroup      = "liberty_servers"
  }

  lifecycle {
    ignore_changes = [ami, user_data] # Prevent recreation on AMI/user_data updates
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group for Liberty
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "liberty" {
  name              = "/aws/ec2/${local.name_prefix}/liberty"
  retention_in_days = 30

  tags = {
    Name = "${local.name_prefix}-liberty-logs"
  }
}
