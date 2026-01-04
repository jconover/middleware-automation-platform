# =============================================================================
# Load Balancer Module - Application Load Balancer with HTTPS Support
# =============================================================================

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------
data "aws_elb_service_account" "main" {}

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# Application Load Balancer
# -----------------------------------------------------------------------------
resource "aws_lb" "main" {
  name               = "${var.name_prefix}-alb"
  internal           = var.internal
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  idle_timeout               = var.idle_timeout
  enable_deletion_protection = var.enable_deletion_protection

  dynamic "access_logs" {
    for_each = var.enable_access_logs ? [1] : []
    content {
      bucket  = aws_s3_bucket.alb_logs[0].id
      prefix  = "alb"
      enabled = true
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-alb"
  })
}

# -----------------------------------------------------------------------------
# ALB Access Logs Bucket
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "alb_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket = "${var.name_prefix}-alb-logs-${data.aws_caller_identity.current.account_id}"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-alb-logs"
  })
}

# -----------------------------------------------------------------------------
# ALB Access Logs Bucket - Versioning (for forensic analysis)
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "alb_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket = aws_s3_bucket.alb_logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

# -----------------------------------------------------------------------------
# ALB Access Logs Bucket - Server-Side Encryption
# Uses AES256 (SSE-S3) as ALB access logs do not support SSE-KMS
# See: https://docs.aws.amazon.com/elasticloadbalancing/latest/application/enable-access-logging.html
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket = aws_s3_bucket.alb_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# -----------------------------------------------------------------------------
# ALB Access Logs Bucket - Block Public Access
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "alb_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket = aws_s3_bucket.alb_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# ALB Access Logs Bucket - Lifecycle Configuration
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket = aws_s3_bucket.alb_logs[0].id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = var.access_logs_retention_days
    }
  }
}

# -----------------------------------------------------------------------------
# ALB Access Logs Bucket - Policy
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_policy" "alb_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket = aws_s3_bucket.alb_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = data.aws_elb_service_account.main.arn
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs[0].arn}/alb/*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Self-signed Certificate for fallback (when no external certificate provided)
# -----------------------------------------------------------------------------
resource "tls_private_key" "self_signed" {
  count       = var.enable_https && var.certificate_arn == "" ? 1 : 0
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

resource "tls_self_signed_cert" "main" {
  count           = var.enable_https && var.certificate_arn == "" ? 1 : 0
  private_key_pem = tls_private_key.self_signed[0].private_key_pem

  subject {
    common_name  = var.self_signed_cert_common_name
    organization = var.self_signed_cert_organization
  }

  validity_period_hours = var.self_signed_cert_validity_hours

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "self_signed" {
  count            = var.enable_https && var.certificate_arn == "" ? 1 : 0
  private_key      = tls_private_key.self_signed[0].private_key_pem
  certificate_body = tls_self_signed_cert.main[0].cert_pem

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-self-signed-cert"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Local values for certificate ARN resolution
# -----------------------------------------------------------------------------
locals {
  # Determine if we have HTTPS capability
  # Either user provided a certificate, or HTTPS is enabled (which creates self-signed)
  has_certificate = var.certificate_arn != "" || var.enable_https

  # Use provided certificate ARN, or fall back to self-signed if HTTPS is enabled
  effective_certificate_arn = var.certificate_arn != "" ? var.certificate_arn : (
    var.enable_https ? aws_acm_certificate.self_signed[0].arn : ""
  )
}

# -----------------------------------------------------------------------------
# ECS Target Group (IP-based for Fargate)
# -----------------------------------------------------------------------------
resource "aws_lb_target_group" "ecs" {
  count = var.create_ecs_target_group ? 1 : 0

  name        = "${var.name_prefix}-ecs-tg"
  port        = var.target_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # Required for Fargate

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = var.health_check_port
    protocol            = "HTTP"
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    timeout             = var.health_check_timeout
    interval            = var.health_check_interval
    matcher             = var.health_check_matcher
  }

  stickiness {
    type            = "lb_cookie"
    cookie_duration = var.stickiness_duration
    enabled         = var.stickiness_enabled
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-ecs-tg"
  })
}

# -----------------------------------------------------------------------------
# EC2 Target Group (Instance-based)
# -----------------------------------------------------------------------------
resource "aws_lb_target_group" "ec2" {
  count = var.create_ec2_target_group ? 1 : 0

  name        = "${var.name_prefix}-ec2-tg"
  port        = var.target_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = var.health_check_port
    protocol            = "HTTP"
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    timeout             = var.health_check_timeout
    interval            = var.health_check_interval
    matcher             = var.health_check_matcher
  }

  stickiness {
    type            = "lb_cookie"
    cookie_duration = var.stickiness_duration
    enabled         = var.stickiness_enabled
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-ec2-tg"
  })
}

# -----------------------------------------------------------------------------
# HTTP Listener (Port 80)
# Redirects to HTTPS if certificate is available, otherwise forwards to target
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

    # Forward to primary target group if no certificate
    target_group_arn = local.has_certificate ? null : local.default_target_group_arn
  }
}

# -----------------------------------------------------------------------------
# HTTPS Listener (Port 443)
# Only created when a certificate is available
# -----------------------------------------------------------------------------
resource "aws_lb_listener" "https" {
  count = local.has_certificate ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = local.effective_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = local.default_target_group_arn
  }
}

# -----------------------------------------------------------------------------
# Additional Certificate (for listener with multiple domains)
# -----------------------------------------------------------------------------
resource "aws_lb_listener_certificate" "additional" {
  count = local.has_certificate && var.additional_certificate_arn != "" ? 1 : 0

  listener_arn    = aws_lb_listener.https[0].arn
  certificate_arn = var.additional_certificate_arn
}

# -----------------------------------------------------------------------------
# Local value for default target group
# -----------------------------------------------------------------------------
locals {
  # Primary target group - ECS if available, otherwise EC2
  default_target_group_arn = var.create_ecs_target_group ? aws_lb_target_group.ecs[0].arn : (
    var.create_ec2_target_group ? aws_lb_target_group.ec2[0].arn : null
  )
}

# -----------------------------------------------------------------------------
# SECURITY: Block /metrics endpoint from public access
# Metrics endpoint exposes internal application metrics (Prometheus format).
# Only the monitoring server should access this endpoint directly via VPC.
# Public requests to /metrics receive a 403 Forbidden response.
# -----------------------------------------------------------------------------
resource "aws_lb_listener_rule" "block_metrics_http" {
  count = var.block_metrics_endpoint ? 1 : 0

  listener_arn = aws_lb_listener.http.arn
  priority     = 1 # Highest priority - evaluated before all other rules

  action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }

  condition {
    path_pattern {
      values = ["/metrics", "/metrics/*"]
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-block-metrics-http"
  })
}

resource "aws_lb_listener_rule" "block_metrics_https" {
  count = var.block_metrics_endpoint && local.has_certificate ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 1 # Highest priority - evaluated before all other rules

  action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }

  condition {
    path_pattern {
      values = ["/metrics", "/metrics/*"]
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-block-metrics-https"
  })
}

# -----------------------------------------------------------------------------
# EC2 Rollback Listener Rule
# Routes traffic to EC2 target group when X-Target: ec2 header is present
# Used for rollback scenarios or A/B testing between ECS and EC2
# -----------------------------------------------------------------------------
resource "aws_lb_listener_rule" "ec2_rollback_http" {
  count = var.create_ecs_target_group && var.create_ec2_target_group ? 1 : 0

  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ec2[0].arn
  }

  condition {
    http_header {
      http_header_name = "X-Target"
      values           = ["ec2"]
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-ec2-rollback-http"
  })
}

resource "aws_lb_listener_rule" "ec2_rollback_https" {
  count = var.create_ecs_target_group && var.create_ec2_target_group && local.has_certificate ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ec2[0].arn
  }

  condition {
    http_header {
      http_header_name = "X-Target"
      values           = ["ec2"]
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-ec2-rollback-https"
  })
}
