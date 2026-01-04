# =============================================================================
# AWS WAF Web Application Firewall
# =============================================================================
# Provides protection against common web exploits (OWASP Top 10), SQL injection,
# known bad inputs, and DDoS through rate limiting.
# =============================================================================

# -----------------------------------------------------------------------------
# WAFv2 Web ACL
# -----------------------------------------------------------------------------
resource "aws_wafv2_web_acl" "main" {
  count = var.enable_waf ? 1 : 0

  name        = "${local.name_prefix}-waf"
  description = "WAF Web ACL for ${local.name_prefix} ALB"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # ---------------------------------------------------------------------------
  # Rule 1: AWS Managed Rules - Common Rule Set (OWASP Core)
  # ---------------------------------------------------------------------------
  # Protects against common web exploits including those in OWASP Top 10
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  # ---------------------------------------------------------------------------
  # Rule 2: AWS Managed Rules - SQL Injection Rule Set
  # ---------------------------------------------------------------------------
  # Protects against SQL injection attacks
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-sqli-rules"
      sampled_requests_enabled   = true
    }
  }

  # ---------------------------------------------------------------------------
  # Rule 3: AWS Managed Rules - Known Bad Inputs Rule Set
  # ---------------------------------------------------------------------------
  # Blocks requests with patterns known to be malicious
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 30

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-bad-inputs-rules"
      sampled_requests_enabled   = true
    }
  }

  # ---------------------------------------------------------------------------
  # Rule 4: Rate Limiting
  # ---------------------------------------------------------------------------
  # Limits requests per IP to prevent DDoS and brute force attacks
  rule {
    name     = "RateLimitRule"
    priority = 40

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "${local.name_prefix}-waf"
  }
}

# -----------------------------------------------------------------------------
# WAF Web ACL Association with ALB
# -----------------------------------------------------------------------------
resource "aws_wafv2_web_acl_association" "alb" {
  count = var.enable_waf ? 1 : 0

  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.main[0].arn
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group for WAF Logs (Optional)
# -----------------------------------------------------------------------------
# WAF log group names must start with "aws-waf-logs-" prefix
resource "aws_cloudwatch_log_group" "waf" {
  count = var.enable_waf && var.waf_enable_logging ? 1 : 0

  name              = "aws-waf-logs-${local.name_prefix}"
  retention_in_days = 30

  tags = {
    Name = "${local.name_prefix}-waf-logs"
  }
}

# -----------------------------------------------------------------------------
# WAF Logging Configuration
# -----------------------------------------------------------------------------
resource "aws_wafv2_web_acl_logging_configuration" "main" {
  count = var.enable_waf && var.waf_enable_logging ? 1 : 0

  log_destination_configs = [aws_cloudwatch_log_group.waf[0].arn]
  resource_arn            = aws_wafv2_web_acl.main[0].arn

  # Optionally redact sensitive fields from logs
  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  redacted_fields {
    single_header {
      name = "cookie"
    }
  }
}

# -----------------------------------------------------------------------------
# IAM Policy for WAF to write to CloudWatch Logs
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_resource_policy" "waf" {
  count = var.enable_waf && var.waf_enable_logging ? 1 : 0

  policy_name = "${local.name_prefix}-waf-logging"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.waf[0].arn}:*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      }
    ]
  })
}
