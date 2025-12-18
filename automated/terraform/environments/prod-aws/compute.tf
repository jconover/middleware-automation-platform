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
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
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
  subnet_id              = aws_subnet.private[count.index % var.availability_zones].id
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

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e

    # Update system
    apt-get update
    apt-get upgrade -y

    # Install prerequisites for Ansible
    apt-get install -y python3 python3-pip

    # Install AWS CLI
    apt-get install -y awscli

    # Create ansible user
    useradd -m -s /bin/bash ansible
    mkdir -p /home/ansible/.ssh
    cat /home/ubuntu/.ssh/authorized_keys >> /home/ansible/.ssh/authorized_keys
    chown -R ansible:ansible /home/ansible/.ssh
    chmod 700 /home/ansible/.ssh
    chmod 600 /home/ansible/.ssh/authorized_keys

    # Add ansible to sudoers
    echo "ansible ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible

    # Tag instance as ready
    INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    aws ec2 create-tags --resources $INSTANCE_ID --tags Key=Status,Value=Ready --region ${var.aws_region}
  EOF
  )

  tags = {
    Name                = "${local.name_prefix}-liberty-${count.index + 1}"
    Role                = "liberty-server"
    LibertyServerName   = "appServer0${count.index + 1}"
    AnsibleGroup        = "liberty_servers"
  }

  lifecycle {
    ignore_changes = [ami] # Prevent recreation on AMI updates
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
