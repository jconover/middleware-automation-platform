# =============================================================================
# Security Compliance Module - Variables
# =============================================================================
# This module provides security and compliance resources including:
# - CloudTrail for audit logging
# - GuardDuty and Security Hub for threat detection
# - WAF for web application protection
# =============================================================================

# -----------------------------------------------------------------------------
# General Configuration
# -----------------------------------------------------------------------------
variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string

  validation {
    condition     = length(var.name_prefix) >= 2 && length(var.name_prefix) <= 30
    error_message = "Name prefix must be between 2 and 30 characters."
  }

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name_prefix))
    error_message = "Name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be a valid format (e.g., us-east-1, eu-west-2)."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# CloudTrail Configuration
# -----------------------------------------------------------------------------
variable "enable_cloudtrail" {
  description = <<-EOT
    Enable AWS CloudTrail for audit logging and compliance.
    When enabled, creates:
    - CloudTrail trail with multi-region and global service events
    - S3 bucket with encryption and lifecycle policies
    - CloudWatch Log Group for real-time analysis
    - Metric filters and alarms for security events
  EOT
  type        = bool
  default     = true
}

variable "cloudtrail_log_retention_days" {
  description = <<-EOT
    Number of days to retain CloudTrail logs in CloudWatch before transitioning to Glacier.
    S3 logs are transitioned to Glacier after this period and expire after 365 days.
  EOT
  type        = number
  default     = 90

  validation {
    condition     = var.cloudtrail_log_retention_days >= 30 && var.cloudtrail_log_retention_days <= 365
    error_message = "CloudTrail log retention must be between 30 and 365 days."
  }
}

# -----------------------------------------------------------------------------
# GuardDuty and Security Hub Configuration
# -----------------------------------------------------------------------------
variable "enable_guardduty" {
  description = <<-EOT
    Enable AWS GuardDuty and Security Hub for threat detection and security posture management.
    When enabled, creates:
    - GuardDuty Detector with S3 logs and EBS malware protection
    - Security Hub with CIS AWS Foundations and AWS Foundational Security benchmarks
    - EventBridge rules for alerting on high-severity findings
    - IAM roles for malware protection
  EOT
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# WAF Configuration
# -----------------------------------------------------------------------------
variable "enable_waf" {
  description = <<-EOT
    Enable AWS WAFv2 Web Application Firewall.
    When enabled, creates a Web ACL with:
    - AWS Managed Rules Common Rule Set (OWASP Top 10 protection)
    - AWS Managed Rules SQL Injection Rule Set
    - AWS Managed Rules Known Bad Inputs Rule Set
    - Rate limiting to prevent DDoS and brute force attacks
  EOT
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = <<-EOT
    Maximum requests per 5-minute period per IP address before rate limiting kicks in.
    Requests exceeding this limit are blocked.

    Guidelines:
    - Low traffic sites: 1000-2000
    - Medium traffic: 2000-5000
    - High traffic/API: 5000-10000
  EOT
  type        = number
  default     = 2000

  validation {
    condition     = var.waf_rate_limit >= 100 && var.waf_rate_limit <= 20000000
    error_message = "WAF rate limit must be between 100 and 20,000,000 requests per 5-minute period."
  }
}

variable "waf_enable_logging" {
  description = <<-EOT
    Enable WAF logging to CloudWatch Logs.
    When enabled, creates a log group with 30-day retention for:
    - Blocked requests
    - Matched rules
    - Request details (with authorization and cookie headers redacted)

    Note: WAF logging incurs additional CloudWatch Logs costs.
  EOT
  type        = bool
  default     = false
}

variable "alb_arn" {
  description = <<-EOT
    ARN of the Application Load Balancer to associate with WAF.
    Required when enable_waf = true and attach_waf_to_alb = true.
  EOT
  type        = string
  default     = ""
}

variable "attach_waf_to_alb" {
  description = "Whether to attach WAF Web ACL to the ALB (set to true when ALB exists)"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Alert Configuration
# -----------------------------------------------------------------------------
variable "security_alert_email" {
  description = <<-EOT
    Email address for security alerts from GuardDuty, Security Hub, and CloudTrail.
    Leave empty to disable email notifications.

    When configured, receives notifications for:
    - GuardDuty findings with severity >= 7 (High/Critical)
    - Security Hub findings with CRITICAL or HIGH severity
    - CloudTrail security alarms (unauthorized API calls, root usage, login without MFA)

    IMPORTANT: The subscriber must confirm the email subscription after deployment.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.security_alert_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.security_alert_email))
    error_message = "security_alert_email must be empty or a valid email address format."
  }
}
