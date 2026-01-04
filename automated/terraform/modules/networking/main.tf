# =============================================================================
# Networking Module - VPC, Subnets, NAT Gateway, Route Tables
# =============================================================================

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-vpc"
  })
}

# -----------------------------------------------------------------------------
# Internet Gateway
# -----------------------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-igw"
  })
}

# -----------------------------------------------------------------------------
# Public Subnets
# -----------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count = var.availability_zones

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + var.public_subnet_offset)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-public-${count.index + 1}"
    Tier = "public"
  })
}

# -----------------------------------------------------------------------------
# Private Subnets
# -----------------------------------------------------------------------------
resource "aws_subnet" "private" {
  count = var.availability_zones

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + var.private_subnet_offset)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-${count.index + 1}"
    Tier = "private"
  })
}

# -----------------------------------------------------------------------------
# NAT Gateway
# Single NAT Gateway (default) or Multi-AZ NAT Gateways for high availability
# Multi-AZ adds ~$32/month per additional NAT Gateway
# -----------------------------------------------------------------------------

# Elastic IPs for NAT Gateways
# - Single NAT: 1 EIP
# - Multi-AZ: 1 EIP per AZ
resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? (var.high_availability_nat ? var.availability_zones : 1) : 0
  domain = "vpc"

  tags = merge(var.tags, {
    Name = var.high_availability_nat ? "${var.name_prefix}-nat-eip-${count.index + 1}" : "${var.name_prefix}-nat-eip"
  })

  depends_on = [aws_internet_gateway.main]
}

# NAT Gateways
# - Single NAT: 1 NAT Gateway in first public subnet
# - Multi-AZ: 1 NAT Gateway per AZ in corresponding public subnet
resource "aws_nat_gateway" "main" {
  count         = var.enable_nat_gateway ? (var.high_availability_nat ? var.availability_zones : 1) : 0
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.tags, {
    Name = var.high_availability_nat ? "${var.name_prefix}-nat-${count.index + 1}" : "${var.name_prefix}-nat"
  })

  depends_on = [aws_internet_gateway.main]
}

# -----------------------------------------------------------------------------
# Route Tables
# -----------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-public-rt"
  })
}

# Private Route Table - Single NAT Gateway configuration
# Used when high_availability_nat = false
resource "aws_route_table" "private" {
  count  = var.enable_nat_gateway && !var.high_availability_nat ? 1 : 0
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[0].id
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-rt"
  })
}

# Private Route Tables - Multi-AZ NAT Gateway configuration
# Used when high_availability_nat = true
# Creates one route table per AZ, each routing through its local NAT Gateway
resource "aws_route_table" "private_per_az" {
  count  = var.enable_nat_gateway && var.high_availability_nat ? var.availability_zones : 0
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-rt-${count.index + 1}"
  })
}

# Private Route Table - No NAT Gateway (isolated private subnets)
resource "aws_route_table" "private_no_nat" {
  count  = var.enable_nat_gateway ? 0 : 1
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-rt"
  })
}

# -----------------------------------------------------------------------------
# Route Table Associations
# -----------------------------------------------------------------------------
resource "aws_route_table_association" "public" {
  count = var.availability_zones

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private subnet route table associations - Single NAT Gateway
resource "aws_route_table_association" "private" {
  count = var.enable_nat_gateway && !var.high_availability_nat ? var.availability_zones : 0

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[0].id
}

# Private subnet route table associations - Multi-AZ NAT Gateways
# Each private subnet routes through its local AZ's NAT Gateway
resource "aws_route_table_association" "private_per_az" {
  count = var.enable_nat_gateway && var.high_availability_nat ? var.availability_zones : 0

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private_per_az[count.index].id
}

# Private subnet route table associations - No NAT Gateway
resource "aws_route_table_association" "private_no_nat" {
  count = var.enable_nat_gateway ? 0 : var.availability_zones

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private_no_nat[0].id
}

# -----------------------------------------------------------------------------
# VPC Flow Logs (Security Best Practice)
# -----------------------------------------------------------------------------
resource "aws_flow_log" "main" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id          = aws_vpc.main.id
  traffic_type    = var.flow_logs_traffic_type
  iam_role_arn    = aws_iam_role.flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.flow_logs[0].arn

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-flow-logs"
  })
}

# -----------------------------------------------------------------------------
# KMS Key for CloudWatch Logs Encryption (when enabled)
# -----------------------------------------------------------------------------
resource "aws_kms_key" "logs" {
  count = var.enable_flow_logs && var.enable_flow_logs_encryption ? 1 : 0

  description             = "KMS key for CloudWatch logs encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-logs-key"
  })
}

resource "aws_kms_key_policy" "logs" {
  count = var.enable_flow_logs && var.enable_flow_logs_encryption ? 1 : 0

  key_id = aws_kms_key.logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM policies"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc/${var.name_prefix}-flow-logs"
  retention_in_days = var.flow_logs_retention_days
  kms_key_id        = var.enable_flow_logs_encryption ? aws_kms_key.logs[0].arn : null

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-flow-logs"
  })

  depends_on = [aws_kms_key_policy.logs]
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${var.name_prefix}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
    }]
  })

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-flow-logs-role"
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${var.name_prefix}-flow-logs-policy"
  role = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ]
      Effect = "Allow"
      Resource = [
        aws_cloudwatch_log_group.flow_logs[0].arn,
        "${aws_cloudwatch_log_group.flow_logs[0].arn}:*"
      ]
    }]
  })
}
