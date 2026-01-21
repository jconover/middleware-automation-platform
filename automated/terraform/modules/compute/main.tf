# =============================================================================
# Compute Module - EC2 Instances
# =============================================================================
# Generic EC2 compute module for deploying instances across availability zones.
# Supports any workload (Liberty, web servers, application servers, etc.)
# =============================================================================

# -----------------------------------------------------------------------------
# Data Source: Latest Ubuntu AMI (fallback when ami_id not provided)
# -----------------------------------------------------------------------------
data "aws_ami" "ubuntu" {
  count       = var.ami_id == null ? 1 : 0
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  ami_id = var.ami_id != null ? var.ami_id : data.aws_ami.ubuntu[0].id
}

# -----------------------------------------------------------------------------
# SSH Key Pair
# -----------------------------------------------------------------------------
resource "aws_key_pair" "this" {
  count = var.create_key_pair ? 1 : 0

  key_name   = "${var.name_prefix}-deployer"
  public_key = var.ssh_public_key

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-deployer-key"
  })
}

locals {
  key_name = var.create_key_pair ? aws_key_pair.this[0].key_name : var.existing_key_name
}

# -----------------------------------------------------------------------------
# IAM Role for EC2 Instances
# -----------------------------------------------------------------------------
resource "aws_iam_role" "this" {
  count = var.create_iam_role ? 1 : 0

  name = "${var.name_prefix}-role"

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

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-role"
  })
}

# Attach AWS managed policies
resource "aws_iam_role_policy_attachment" "managed_policies" {
  count = var.create_iam_role ? length(var.iam_managed_policy_arns) : 0

  role       = aws_iam_role.this[0].name
  policy_arn = var.iam_managed_policy_arns[count.index]
}

# Attach SSM managed policy by default for instance management
resource "aws_iam_role_policy_attachment" "ssm" {
  count = var.create_iam_role && var.enable_ssm ? 1 : 0

  role       = aws_iam_role.this[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Custom inline policy for CloudWatch logs and other permissions
resource "aws_iam_role_policy" "custom" {
  count = var.create_iam_role && length(var.iam_inline_policy_statements) > 0 ? 1 : 0

  name = "${var.name_prefix}-custom-policy"
  role = aws_iam_role.this[0].id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = var.iam_inline_policy_statements
  })
}

# CloudWatch logs policy (always added if log group is created)
resource "aws_iam_role_policy" "cloudwatch_logs" {
  count = var.create_iam_role && var.create_cloudwatch_log_group ? 1 : 0

  name = "${var.name_prefix}-cloudwatch-logs"
  role = aws_iam_role.this[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          aws_cloudwatch_log_group.this[0].arn,
          "${aws_cloudwatch_log_group.this[0].arn}:*"
        ]
      }
    ]
  })
}

# Instance Profile
resource "aws_iam_instance_profile" "this" {
  count = var.create_iam_role ? 1 : 0

  name = "${var.name_prefix}-profile"
  role = aws_iam_role.this[0].name

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-profile"
  })
}

locals {
  instance_profile_name = var.create_iam_role ? aws_iam_instance_profile.this[0].name : var.existing_instance_profile_name
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "this" {
  count = var.create_cloudwatch_log_group ? 1 : 0

  name              = "/aws/ec2/${var.name_prefix}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_group_kms_key_id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-logs"
  })
}

# -----------------------------------------------------------------------------
# EC2 Instances
# -----------------------------------------------------------------------------
resource "aws_instance" "this" {
  count = var.instance_count

  ami                    = local.ami_id
  instance_type          = var.instance_type
  key_name               = local.key_name
  subnet_id              = var.subnet_ids[count.index % length(var.subnet_ids)]
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = local.instance_profile_name

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = var.root_volume_type
    encrypted             = var.root_volume_encrypted
    kms_key_id            = var.root_volume_kms_key_id
    delete_on_termination = var.root_volume_delete_on_termination
    # Note: tags are applied via volume_tags to avoid conflict
  }

  # Additional EBS volumes
  dynamic "ebs_block_device" {
    for_each = var.additional_ebs_volumes
    content {
      device_name           = ebs_block_device.value.device_name
      volume_size           = ebs_block_device.value.volume_size
      volume_type           = lookup(ebs_block_device.value, "volume_type", "gp3")
      encrypted             = lookup(ebs_block_device.value, "encrypted", true)
      kms_key_id            = lookup(ebs_block_device.value, "kms_key_id", null)
      delete_on_termination = lookup(ebs_block_device.value, "delete_on_termination", true)
      # Note: tags are applied via volume_tags to avoid conflict
    }
  }

  # IMDSv2 required for security
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = var.require_imdsv2 ? "required" : "optional"
    http_put_response_hop_limit = var.imds_hop_limit
  }

  # User data with optional templating
  user_data = var.user_data_base64 != null ? var.user_data_base64 : (
    var.user_data_template != null ? base64encode(templatefile(var.user_data_template, merge(
      var.user_data_template_vars,
      {
        aws_region  = var.aws_region
        name_prefix = var.name_prefix
        instance_id = count.index + 1
      }
    ))) : null
  )

  # Monitoring
  monitoring = var.detailed_monitoring

  # Placement
  availability_zone = var.availability_zone != null ? var.availability_zone : null

  # Tenancy
  tenancy = var.tenancy

  tags = merge(var.tags, var.instance_tags, {
    Name = "${var.name_prefix}-${count.index + 1}"
  })

  volume_tags = merge(var.tags, {
    Name = "${var.name_prefix}-${count.index + 1}"
  })

  # Note: ignore_changes for AMI is hardcoded to prevent recreation on AMI updates.
  # This is the common pattern for long-running instances where AMI updates are
  # handled through a separate update/replacement strategy.
  lifecycle {
    ignore_changes = [ami, user_data]
  }
}
