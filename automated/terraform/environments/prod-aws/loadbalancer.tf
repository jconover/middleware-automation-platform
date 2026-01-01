# =============================================================================
# Application Load Balancer with HTTPS Support
# =============================================================================

# -----------------------------------------------------------------------------
# ELB Service Account (for ALB access logs - region-aware)
# -----------------------------------------------------------------------------
data "aws_elb_service_account" "main" {}

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

# -----------------------------------------------------------------------------
# ALB Access Logs Bucket - Server-Side Encryption
# Uses AES256 (SSE-S3) as ALB access logs do not support SSE-KMS
# See: https://docs.aws.amazon.com/elasticloadbalancing/latest/application/enable-access-logging.html
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

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
  bucket = aws_s3_bucket.alb_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
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
          AWS = data.aws_elb_service_account.main.arn
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
# Target Group - Liberty Admin Console (HTTPS 9443)
# -----------------------------------------------------------------------------
resource "aws_lb_target_group" "liberty_admin" {
  name     = "${local.name_prefix}-liberty-admin-tg"
  port     = 9443
  protocol = "HTTPS"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/adminCenter/"
    port                = "traffic-port"
    protocol            = "HTTPS"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200-399"
  }

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = true
  }

  tags = {
    Name = "${local.name_prefix}-liberty-admin-tg"
  }
}

resource "aws_lb_target_group_attachment" "liberty_admin" {
  count = var.liberty_instance_count

  target_group_arn = aws_lb_target_group.liberty_admin.arn
  target_id        = aws_instance.liberty[count.index].id
  port             = 9443
}

# -----------------------------------------------------------------------------
# SECURITY: Block /metrics endpoint from public access
# -----------------------------------------------------------------------------
# Metrics endpoint exposes internal application metrics (Prometheus format).
# Only the monitoring server should access this endpoint directly via VPC.
# Public requests to /metrics receive a 403 Forbidden response.
# -----------------------------------------------------------------------------
resource "aws_lb_listener_rule" "block_metrics" {
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

  tags = {
    Name = "${local.name_prefix}-block-metrics-rule"
  }
}

# Block /metrics on HTTPS listener as well (if certificate exists)
resource "aws_lb_listener_rule" "block_metrics_https" {
  count = local.has_certificate ? 1 : 0

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

  tags = {
    Name = "${local.name_prefix}-block-metrics-https-rule"
  }
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

    # Forward to ECS target group (primary) if no certificate
    # EC2 target group kept for rollback but not used as default
    target_group_arn = local.has_certificate ? null : (
      var.ecs_enabled ? aws_lb_target_group.liberty_ecs[0].arn : aws_lb_target_group.liberty.arn
    )
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
# Liberty Admin Console Listener (Port 9443 - Restricted to allowed CIDRs)
# -----------------------------------------------------------------------------
resource "aws_lb_listener" "admin_console" {
  load_balancer_arn = aws_lb.main.arn
  port              = 9443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = local.admin_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.liberty_admin.arn
  }
}

# -----------------------------------------------------------------------------
# Self-signed Certificate for Admin Console (if no other cert available)
# -----------------------------------------------------------------------------
resource "tls_private_key" "admin" {
  count     = local.certificate_arn == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "admin" {
  count           = local.certificate_arn == "" ? 1 : 0
  private_key_pem = tls_private_key.admin[0].private_key_pem

  subject {
    common_name  = "liberty-admin.local"
    organization = "Middleware Platform"
  }

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "admin_self_signed" {
  count            = local.certificate_arn == "" ? 1 : 0
  private_key      = tls_private_key.admin[0].private_key_pem
  certificate_body = tls_self_signed_cert.admin[0].cert_pem

  tags = {
    Name = "${local.name_prefix}-admin-cert"
  }

  lifecycle {
    create_before_destroy = true
  }
}
