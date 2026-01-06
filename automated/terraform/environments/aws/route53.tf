# =============================================================================
# Route53 Health Checks and Failover Routing
# =============================================================================
# Implements DNS-based health checks and automatic failover for high availability.
#
# Architecture:
#   - Primary: ALB endpoint (weighted routing in normal operation)
#   - Secondary: S3 static maintenance page (failover when primary is unhealthy)
#   - Health Check: HTTPS probe to ALB /health/ready endpoint
#   - CloudWatch Alarm: Alerts when health check fails
#
# Requirements:
#   - Route53 hosted zone must exist for the domain
#   - domain_name variable must be set
#   - enable_route53_failover must be true
# =============================================================================

# -----------------------------------------------------------------------------
# Data Source: Existing Route53 Hosted Zone
# -----------------------------------------------------------------------------
data "aws_route53_zone" "main" {
  count = local.route53_enabled ? 1 : 0

  name         = var.route53_zone_name != "" ? var.route53_zone_name : var.domain_name
  private_zone = false
}

# =============================================================================
# Route53 Health Check
# =============================================================================
# Monitors the ALB endpoint using HTTPS health checks from multiple AWS regions.
# Health check results are used for DNS failover decisions.

resource "aws_route53_health_check" "alb_primary" {
  count = local.route53_enabled ? 1 : 0

  fqdn              = module.loadbalancer.alb_dns_name
  port              = local.has_certificate ? 443 : 80
  type              = local.has_certificate ? "HTTPS" : "HTTP"
  resource_path     = "/health/ready"
  failure_threshold = var.route53_health_check_failure_threshold
  request_interval  = var.route53_health_check_interval

  # Enable latency measurement for performance monitoring
  measure_latency = true

  # Check from multiple regions for reliability
  regions = var.route53_health_check_regions

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-alb-health-check"
    Purpose = "DNS Failover"
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Alarm for Route53 Health Check
# -----------------------------------------------------------------------------
# Triggers when the health check fails, enabling alerting and automation.

resource "aws_cloudwatch_metric_alarm" "route53_health_check" {
  count = local.route53_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-route53-health-check-failed"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  alarm_description   = <<-EOT
    CRITICAL: Route53 health check for ALB has FAILED.
    DNS failover has been triggered to the maintenance page.

    Health Check ID: ${aws_route53_health_check.alb_primary[0].id}
    ALB DNS: ${module.loadbalancer.alb_dns_name}

    Immediate actions required:
    1. Check ALB target group health
    2. Verify ECS service status
    3. Check application logs

    Runbook: docs/runbooks/dns-failover.md
  EOT
  treat_missing_data  = "breaching"
  actions_enabled     = true

  # Use Route53 alerts SNS topic
  alarm_actions = [aws_sns_topic.route53_alerts[0].arn]
  ok_actions    = [aws_sns_topic.route53_alerts[0].arn]

  dimensions = {
    HealthCheckId = aws_route53_health_check.alb_primary[0].id
  }

  tags = merge(local.common_tags, {
    Name     = "${local.name_prefix}-route53-health-alarm"
    Severity = "critical"
  })
}

# SNS Topic for Route53 alerts
resource "aws_sns_topic" "route53_alerts" {
  count = local.route53_enabled ? 1 : 0

  name = "${local.name_prefix}-route53-alerts"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-route53-alerts"
  })
}

# =============================================================================
# S3 Bucket for Static Maintenance Page (Failover Target)
# =============================================================================
# When the primary ALB is unhealthy, traffic is routed to this static S3 website.

resource "aws_s3_bucket" "maintenance" {
  count = local.route53_enabled && var.enable_maintenance_page ? 1 : 0

  bucket = "${local.name_prefix}-maintenance-${local.account_id}"

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-maintenance"
    Purpose = "DNS Failover Maintenance Page"
  })
}

resource "aws_s3_bucket_website_configuration" "maintenance" {
  count = local.route53_enabled && var.enable_maintenance_page ? 1 : 0

  bucket = aws_s3_bucket.maintenance[0].id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

resource "aws_s3_bucket_public_access_block" "maintenance" {
  count = local.route53_enabled && var.enable_maintenance_page ? 1 : 0

  bucket = aws_s3_bucket.maintenance[0].id

  # Allow public access for static website hosting
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "maintenance" {
  count = local.route53_enabled && var.enable_maintenance_page ? 1 : 0

  bucket = aws_s3_bucket.maintenance[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.maintenance[0].arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.maintenance]
}

# Upload default maintenance page
resource "aws_s3_object" "maintenance_index" {
  count = local.route53_enabled && var.enable_maintenance_page ? 1 : 0

  bucket       = aws_s3_bucket.maintenance[0].id
  key          = "index.html"
  content_type = "text/html"
  content      = <<-HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Scheduled Maintenance - ${var.project}</title>
        <style>
            * {
                margin: 0;
                padding: 0;
                box-sizing: border-box;
            }
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                min-height: 100vh;
                display: flex;
                align-items: center;
                justify-content: center;
                padding: 20px;
            }
            .container {
                background: white;
                border-radius: 16px;
                padding: 48px;
                max-width: 600px;
                text-align: center;
                box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.25);
            }
            .icon {
                font-size: 64px;
                margin-bottom: 24px;
            }
            h1 {
                color: #1a202c;
                font-size: 28px;
                margin-bottom: 16px;
            }
            p {
                color: #4a5568;
                font-size: 16px;
                line-height: 1.6;
                margin-bottom: 24px;
            }
            .status {
                background: #f7fafc;
                border-radius: 8px;
                padding: 16px;
                margin-top: 24px;
            }
            .status-item {
                display: flex;
                align-items: center;
                justify-content: center;
                gap: 8px;
                color: #718096;
                font-size: 14px;
            }
            .pulse {
                width: 8px;
                height: 8px;
                background: #f6ad55;
                border-radius: 50%;
                animation: pulse 2s infinite;
            }
            @keyframes pulse {
                0%, 100% { opacity: 1; }
                50% { opacity: 0.5; }
            }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="icon">&#128736;</div>
            <h1>We'll Be Right Back</h1>
            <p>
                Our platform is currently undergoing scheduled maintenance to improve
                your experience. We apologize for any inconvenience and appreciate your patience.
            </p>
            <p>
                Expected duration: <strong>Less than 30 minutes</strong>
            </p>
            <div class="status">
                <div class="status-item">
                    <span class="pulse"></span>
                    <span>Maintenance in progress</span>
                </div>
            </div>
        </div>
    </body>
    </html>
  HTML

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-maintenance-index"
  })
}

resource "aws_s3_object" "maintenance_error" {
  count = local.route53_enabled && var.enable_maintenance_page ? 1 : 0

  bucket       = aws_s3_bucket.maintenance[0].id
  key          = "error.html"
  content_type = "text/html"
  content      = <<-HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Service Unavailable - ${var.project}</title>
        <style>
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                background: #f7fafc;
                min-height: 100vh;
                display: flex;
                align-items: center;
                justify-content: center;
                padding: 20px;
            }
            .container {
                text-align: center;
                max-width: 500px;
            }
            h1 { color: #2d3748; margin-bottom: 16px; }
            p { color: #718096; line-height: 1.6; }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>Service Temporarily Unavailable</h1>
            <p>We're experiencing technical difficulties. Please try again in a few minutes.</p>
        </div>
    </body>
    </html>
  HTML

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-maintenance-error"
  })
}

# =============================================================================
# Route53 Failover Records
# =============================================================================
# Primary: ALB (active when healthy)
# Secondary: S3 maintenance page (active when primary is unhealthy)

# -----------------------------------------------------------------------------
# Primary Record - Points to ALB with health check
# -----------------------------------------------------------------------------
resource "aws_route53_record" "primary" {
  count = local.route53_enabled ? 1 : 0

  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = var.domain_name
  type    = "A"

  failover_routing_policy {
    type = "PRIMARY"
  }

  set_identifier  = "primary"
  health_check_id = aws_route53_health_check.alb_primary[0].id

  alias {
    name                   = module.loadbalancer.alb_dns_name
    zone_id                = module.loadbalancer.alb_zone_id
    evaluate_target_health = true
  }
}

# -----------------------------------------------------------------------------
# Secondary Record - Points to S3 maintenance page (or DR region ALB)
# -----------------------------------------------------------------------------
resource "aws_route53_record" "secondary" {
  count = local.route53_enabled ? 1 : 0

  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = var.domain_name
  type    = "A"

  failover_routing_policy {
    type = "SECONDARY"
  }

  set_identifier = "secondary"

  # When maintenance page is enabled, use S3; otherwise use DR ALB if provided
  dynamic "alias" {
    for_each = var.enable_maintenance_page ? [1] : []
    content {
      # S3 website endpoints use regional website hosting zone IDs
      name                   = aws_s3_bucket_website_configuration.maintenance[0].website_endpoint
      zone_id                = local.s3_website_zone_id
      evaluate_target_health = false
    }
  }

  # If DR region ALB is specified (and maintenance page is disabled), use that instead
  dynamic "alias" {
    for_each = !var.enable_maintenance_page && var.dr_alb_dns_name != "" ? [1] : []
    content {
      name                   = var.dr_alb_dns_name
      zone_id                = var.dr_alb_zone_id
      evaluate_target_health = true
    }
  }
}

# -----------------------------------------------------------------------------
# WWW Subdomain CNAME (optional)
# -----------------------------------------------------------------------------
resource "aws_route53_record" "www" {
  count = local.route53_enabled && var.create_www_record ? 1 : 0

  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = "www.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = [var.domain_name]
}

# =============================================================================
# CloudWatch Latency Alarm
# =============================================================================
# Monitors Route53 health check latency for performance degradation

resource "aws_cloudwatch_metric_alarm" "route53_latency_high" {
  count = local.route53_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-route53-latency-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TimeToFirstByte"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Average"
  threshold           = var.route53_latency_threshold_ms
  alarm_description   = <<-EOT
    WARNING: Route53 health check latency is elevated.
    Average TTFB exceeds ${var.route53_latency_threshold_ms}ms over the last 3 minutes.

    This may indicate:
    - Network connectivity issues
    - Application performance degradation
    - Resource constraints

    Runbook: docs/runbooks/high-latency.md
  EOT
  treat_missing_data  = "notBreaching"
  actions_enabled     = true

  alarm_actions = [aws_sns_topic.route53_alerts[0].arn]

  dimensions = {
    HealthCheckId = aws_route53_health_check.alb_primary[0].id
  }

  tags = merge(local.common_tags, {
    Name     = "${local.name_prefix}-route53-latency-alarm"
    Severity = "warning"
  })
}

# =============================================================================
# Locals for Route53
# =============================================================================
locals {
  # S3 website endpoint hosted zone IDs by region
  # Reference: https://docs.aws.amazon.com/general/latest/gr/s3.html#s3_website_region_endpoints
  s3_website_zone_ids = {
    "us-east-1"      = "Z3AQBSTGFYJSTF"
    "us-east-2"      = "Z2O1EMRO9K5GLX"
    "us-west-1"      = "Z2F56UZL2M1ACD"
    "us-west-2"      = "Z3BJ6K6RIION7M"
    "eu-west-1"      = "Z1BKCTXD74EZPE"
    "eu-west-2"      = "Z3GKZC51ZF0DB4"
    "eu-west-3"      = "Z3R1K369G5AVDG"
    "eu-central-1"   = "Z21DNDUVLTQW6Q"
    "eu-north-1"     = "Z3BAZG2TWCNX0D"
    "ap-southeast-1" = "Z3O0J2DXBE1FTB"
    "ap-southeast-2" = "Z1WCIBER93W1HD"
    "ap-northeast-1" = "Z2M4EHUR26P7ZW"
    "ap-northeast-2" = "Z3W03O7B5YMIYP"
    "ap-south-1"     = "Z11RGJOFQNVJUP"
    "sa-east-1"      = "Z7KQH4QJS55SO"
    "ca-central-1"   = "Z1QDHH18159H29"
  }

  s3_website_zone_id = lookup(local.s3_website_zone_ids, var.aws_region, "Z3AQBSTGFYJSTF")
}
