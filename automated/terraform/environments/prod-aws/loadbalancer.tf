# =============================================================================
# Application Load Balancer with HTTPS Support
# =============================================================================

# -----------------------------------------------------------------------------
# ACM Certificate (Optional - DNS validation)
# -----------------------------------------------------------------------------
resource "aws_acm_certificate" "main" {
  count = var.create_certificate && var.domain_name != "" ? 1 : 0

  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.name_prefix}-cert"
  }
}

# -----------------------------------------------------------------------------
# Application Load Balancer
# -----------------------------------------------------------------------------
resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false # Set to true for production

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    prefix  = "alb"
    enabled = true
  }

  tags = {
    Name = "${local.name_prefix}-alb"
  }
}

# -----------------------------------------------------------------------------
# ALB Access Logs Bucket
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "alb_logs" {
  bucket = "${local.name_prefix}-alb-logs-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${local.name_prefix}-alb-logs"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 90
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::127311923021:root" # ELB account for us-east-1
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs.arn}/alb/*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Target Group
# -----------------------------------------------------------------------------
resource "aws_lb_target_group" "liberty" {
  name     = "${local.name_prefix}-liberty-tg"
  port     = 9080
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/health/ready"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = true
  }

  tags = {
    Name = "${local.name_prefix}-liberty-tg"
  }
}

resource "aws_lb_target_group_attachment" "liberty" {
  count = var.liberty_instance_count

  target_group_arn = aws_lb_target_group.liberty.arn
  target_id        = aws_instance.liberty[count.index].id
  port             = 9080
}

# -----------------------------------------------------------------------------
# HTTP Listener (Redirect to HTTPS if cert exists, otherwise forward)
# -----------------------------------------------------------------------------
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = local.has_certificate ? "redirect" : "forward"

    # Redirect to HTTPS if certificate is available
    dynamic "redirect" {
      for_each = local.has_certificate ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    # Forward to target group if no certificate
    target_group_arn = local.has_certificate ? null : aws_lb_target_group.liberty.arn
  }
}

# -----------------------------------------------------------------------------
# HTTPS Listener (Only if certificate is available)
# -----------------------------------------------------------------------------
resource "aws_lb_listener" "https" {
  count = local.has_certificate ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = local.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.liberty.arn
  }
}

# -----------------------------------------------------------------------------
# Locals for Certificate Logic
# -----------------------------------------------------------------------------
locals {
  # Use provided certificate ARN, or created certificate, or none
  certificate_arn = var.certificate_arn != "" ? var.certificate_arn : (
    var.create_certificate && length(aws_acm_certificate.main) > 0 ? aws_acm_certificate.main[0].arn : ""
  )

  has_certificate = local.certificate_arn != ""
}
