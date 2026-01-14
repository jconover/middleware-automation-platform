# =============================================================================
# Security Compliance Module - Main Configuration
# =============================================================================
# This module provides security and compliance resources including:
# - CloudTrail for audit logging
# - GuardDuty and Security Hub for threat detection
# - WAF for web application protection
# =============================================================================

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# =============================================================================
# CLOUDTRAIL SECTION
# =============================================================================

# -----------------------------------------------------------------------------
# KMS Key for CloudTrail Encryption
# -----------------------------------------------------------------------------
resource "aws_kms_key" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0

  description             = "KMS key for CloudTrail log encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccountPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowCloudTrailToEncryptLogs"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:SourceArn" = "arn:aws:cloudtrail:${var.aws_region}:${data.aws_caller_identity.current.account_id}:trail/${var.name_prefix}-trail"
          }
          StringLike = {
            "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:aws:cloudtrail:*:${data.aws_caller_identity.current.account_id}:trail/*"
          }
        }
      },
      {
        Sid    = "AllowCloudTrailToDecryptLogs"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "kms:Decrypt"
        Resource = "*"
        Condition = {
          Null = {
            "kms:EncryptionContext:aws:cloudtrail:arn" = "false"
          }
        }
      },
      {
        Sid    = "AllowCloudWatchLogsToEncrypt"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:*"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-cloudtrail-key"
  })
}

resource "aws_kms_alias" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0

  name          = "alias/${var.name_prefix}-cloudtrail"
  target_key_id = aws_kms_key.cloudtrail[0].key_id
}

# -----------------------------------------------------------------------------
# S3 Bucket for CloudTrail Logs
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = "${var.name_prefix}-cloudtrail-logs-${data.aws_caller_identity.current.account_id}"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-cloudtrail-logs"
  })
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.cloudtrail[0].arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id

  rule {
    id     = "cloudtrail-log-lifecycle"
    status = "Enabled"

    filter {} # Apply to all objects in the bucket

    transition {
      days          = var.cloudtrail_log_retention_days
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail[0].arn
        Condition = {
          StringEquals = {
            "aws:SourceArn" = "arn:aws:cloudtrail:${var.aws_region}:${data.aws_caller_identity.current.account_id}:trail/${var.name_prefix}-trail"
          }
        }
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = "arn:aws:cloudtrail:${var.aws_region}:${data.aws_caller_identity.current.account_id}:trail/${var.name_prefix}-trail"
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.cloudtrail[0].arn,
          "${aws_s3_bucket.cloudtrail[0].arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid       = "DenyUnencryptedUploads"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail[0].arn}/*"
        Condition = {
          # Deny uploads not using KMS encryption, but allow CloudTrail service
          # which uses bucket default encryption
          StringNotEqualsIfExists = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
          # Only apply this deny to non-CloudTrail principals
          StringNotEquals = {
            "aws:PrincipalServiceName" = "cloudtrail.amazonaws.com"
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.cloudtrail]
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group for CloudTrail
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0

  name              = "/aws/cloudtrail/${var.name_prefix}"
  retention_in_days = var.cloudtrail_log_retention_days
  kms_key_id        = aws_kms_key.cloudtrail[0].arn

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-cloudtrail-logs"
  })
}

# -----------------------------------------------------------------------------
# IAM Role for CloudTrail to CloudWatch Logs
# -----------------------------------------------------------------------------
resource "aws_iam_role" "cloudtrail_cloudwatch" {
  count = var.enable_cloudtrail ? 1 : 0

  name = "${var.name_prefix}-cloudtrail-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-cloudtrail-cloudwatch-role"
  })
}

resource "aws_iam_role_policy" "cloudtrail_cloudwatch" {
  count = var.enable_cloudtrail ? 1 : 0

  name = "${var.name_prefix}-cloudtrail-cloudwatch-policy"
  role = aws_iam_role.cloudtrail_cloudwatch[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchLogsWrite"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.cloudtrail[0].arn}:*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# CloudTrail Trail
# -----------------------------------------------------------------------------
resource "aws_cloudtrail" "main" {
  count = var.enable_cloudtrail ? 1 : 0

  name                          = "${var.name_prefix}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail[0].id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.cloudtrail[0].arn

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail[0].arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch[0].arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3"]
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-trail"
  })

  depends_on = [
    aws_s3_bucket_policy.cloudtrail,
    aws_iam_role_policy.cloudtrail_cloudwatch
  ]
}

# -----------------------------------------------------------------------------
# SNS Topic for CloudTrail Alarms
# -----------------------------------------------------------------------------
resource "aws_sns_topic" "cloudtrail_alarms" {
  count = var.enable_cloudtrail ? 1 : 0

  name              = "${var.name_prefix}-cloudtrail-alarms"
  kms_master_key_id = aws_kms_key.cloudtrail[0].id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-cloudtrail-alarms"
  })
}

resource "aws_sns_topic_policy" "cloudtrail_alarms" {
  count = var.enable_cloudtrail ? 1 : 0

  arn = aws_sns_topic.cloudtrail_alarms[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchAlarms"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.cloudtrail_alarms[0].arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = "arn:aws:cloudwatch:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alarm:*"
          }
        }
      }
    ]
  })
}

# Email subscription for CloudTrail alarms
resource "aws_sns_topic_subscription" "cloudtrail_alarms_email" {
  count = var.enable_cloudtrail && var.security_alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.cloudtrail_alarms[0].arn
  protocol  = "email"
  endpoint  = var.security_alert_email
}

# -----------------------------------------------------------------------------
# CloudWatch Metric Filter: Unauthorized API Calls
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_metric_filter" "unauthorized_api_calls" {
  count = var.enable_cloudtrail ? 1 : 0

  name           = "${var.name_prefix}-unauthorized-api-calls"
  pattern        = "{ ($.errorCode = \"*UnauthorizedAccess*\") || ($.errorCode = \"AccessDenied*\") || ($.errorCode = \"AuthorizationError\") }"
  log_group_name = aws_cloudwatch_log_group.cloudtrail[0].name

  metric_transformation {
    name          = "UnauthorizedAPICalls"
    namespace     = "${var.name_prefix}/CloudTrail"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "unauthorized_api_calls" {
  count = var.enable_cloudtrail ? 1 : 0

  alarm_name          = "${var.name_prefix}-unauthorized-api-calls"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnauthorizedAPICalls"
  namespace           = "${var.name_prefix}/CloudTrail"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "This alarm monitors for unauthorized API calls. More than 5 in 5 minutes triggers the alarm."
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.cloudtrail_alarms[0].arn]
  ok_actions    = [aws_sns_topic.cloudtrail_alarms[0].arn]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-unauthorized-api-calls-alarm"
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Metric Filter: Root Account Usage
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_metric_filter" "root_account_usage" {
  count = var.enable_cloudtrail ? 1 : 0

  name           = "${var.name_prefix}-root-account-usage"
  pattern        = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"
  log_group_name = aws_cloudwatch_log_group.cloudtrail[0].name

  metric_transformation {
    name          = "RootAccountUsage"
    namespace     = "${var.name_prefix}/CloudTrail"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "root_account_usage" {
  count = var.enable_cloudtrail ? 1 : 0

  alarm_name          = "${var.name_prefix}-root-account-usage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "RootAccountUsage"
  namespace           = "${var.name_prefix}/CloudTrail"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "This alarm monitors for any use of the AWS root account. Any usage triggers the alarm."
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.cloudtrail_alarms[0].arn]
  ok_actions    = [aws_sns_topic.cloudtrail_alarms[0].arn]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-root-account-usage-alarm"
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Metric Filter: Console Login Without MFA
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_metric_filter" "console_login_without_mfa" {
  count = var.enable_cloudtrail ? 1 : 0

  name           = "${var.name_prefix}-console-login-without-mfa"
  pattern        = "{ ($.eventName = \"ConsoleLogin\") && ($.additionalEventData.MFAUsed != \"Yes\") && ($.userIdentity.type = \"IAMUser\") && ($.responseElements.ConsoleLogin = \"Success\") }"
  log_group_name = aws_cloudwatch_log_group.cloudtrail[0].name

  metric_transformation {
    name          = "ConsoleLoginWithoutMFA"
    namespace     = "${var.name_prefix}/CloudTrail"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "console_login_without_mfa" {
  count = var.enable_cloudtrail ? 1 : 0

  alarm_name          = "${var.name_prefix}-console-login-without-mfa"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ConsoleLoginWithoutMFA"
  namespace           = "${var.name_prefix}/CloudTrail"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "This alarm monitors for console logins without MFA. Any login without MFA triggers the alarm."
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.cloudtrail_alarms[0].arn]
  ok_actions    = [aws_sns_topic.cloudtrail_alarms[0].arn]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-console-login-without-mfa-alarm"
  })
}

# =============================================================================
# GUARDDUTY AND SECURITY HUB SECTION
# =============================================================================

# -----------------------------------------------------------------------------
# GuardDuty Detector
# -----------------------------------------------------------------------------
resource "aws_guardduty_detector" "main" {
  count = var.enable_guardduty ? 1 : 0

  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  datasources {
    s3_logs {
      enable = true
    }

    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-guardduty"
  })
}

# -----------------------------------------------------------------------------
# Security Hub
# -----------------------------------------------------------------------------
resource "aws_securityhub_account" "main" {
  count = var.enable_guardduty ? 1 : 0

  enable_default_standards = false
  auto_enable_controls     = true

  depends_on = [aws_guardduty_detector.main]
}

# CIS AWS Foundations Benchmark v1.4.0
resource "aws_securityhub_standards_subscription" "cis" {
  count = var.enable_guardduty ? 1 : 0

  standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/cis-aws-foundations-benchmark/v/1.4.0"

  depends_on = [aws_securityhub_account.main]
}

# AWS Foundational Security Best Practices
resource "aws_securityhub_standards_subscription" "aws_foundational" {
  count = var.enable_guardduty ? 1 : 0

  standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/aws-foundational-security-best-practices/v/1.0.0"

  depends_on = [aws_securityhub_account.main]
}

# Enable GuardDuty integration with Security Hub
resource "aws_securityhub_product_subscription" "guardduty" {
  count = var.enable_guardduty ? 1 : 0

  product_arn = "arn:aws:securityhub:${var.aws_region}::product/aws/guardduty"

  depends_on = [
    aws_securityhub_account.main,
    aws_guardduty_detector.main
  ]
}

# -----------------------------------------------------------------------------
# KMS Key for Security Alerts SNS Encryption
# -----------------------------------------------------------------------------
resource "aws_kms_key" "security_alerts" {
  count = var.enable_guardduty && var.security_alert_email != "" ? 1 : 0

  description             = "KMS key for security alerts SNS topic encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow EventBridge to use the key"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow SNS to use the key"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch to use the key"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-security-alerts-key"
  })
}

resource "aws_kms_alias" "security_alerts" {
  count = var.enable_guardduty && var.security_alert_email != "" ? 1 : 0

  name          = "alias/${var.name_prefix}-security-alerts"
  target_key_id = aws_kms_key.security_alerts[0].key_id
}

# -----------------------------------------------------------------------------
# SNS Topic for Security Alerts
# -----------------------------------------------------------------------------
resource "aws_sns_topic" "security_alerts" {
  count = var.enable_guardduty && var.security_alert_email != "" ? 1 : 0

  name              = "${var.name_prefix}-security-alerts"
  kms_master_key_id = aws_kms_key.security_alerts[0].id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-security-alerts"
  })
}

# SNS Topic Policy - Allow EventBridge to publish
resource "aws_sns_topic_policy" "security_alerts" {
  count = var.enable_guardduty && var.security_alert_email != "" ? 1 : 0

  arn = aws_sns_topic.security_alerts[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgePublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.security_alerts[0].arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = "arn:aws:events:${var.aws_region}:${data.aws_caller_identity.current.account_id}:rule/${var.name_prefix}-*"
          }
        }
      },
      {
        Sid    = "AllowAccountManagement"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "sns:GetTopicAttributes",
          "sns:SetTopicAttributes",
          "sns:AddPermission",
          "sns:RemovePermission",
          "sns:DeleteTopic",
          "sns:Subscribe",
          "sns:ListSubscriptionsByTopic",
          "sns:Publish"
        ]
        Resource = aws_sns_topic.security_alerts[0].arn
      }
    ]
  })
}

# Email Subscription for Security Alerts
resource "aws_sns_topic_subscription" "security_alerts_email" {
  count = var.enable_guardduty && var.security_alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.security_alerts[0].arn
  protocol  = "email"
  endpoint  = var.security_alert_email
}

# -----------------------------------------------------------------------------
# EventBridge Rule - GuardDuty High/Critical Findings
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  count = var.enable_guardduty && var.security_alert_email != "" ? 1 : 0

  name        = "${var.name_prefix}-guardduty-high-findings"
  description = "Capture GuardDuty High and Critical severity findings"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [
        { numeric = [">=", 7] }
      ]
    }
  })

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-guardduty-high-findings"
  })
}

resource "aws_cloudwatch_event_target" "guardduty_to_sns" {
  count = var.enable_guardduty && var.security_alert_email != "" ? 1 : 0

  rule      = aws_cloudwatch_event_rule.guardduty_findings[0].name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.security_alerts[0].arn

  input_transformer {
    input_paths = {
      severity    = "$.detail.severity"
      title       = "$.detail.title"
      description = "$.detail.description"
      type        = "$.detail.type"
      region      = "$.region"
      account     = "$.account"
      time        = "$.time"
      findingId   = "$.detail.id"
    }
    input_template = <<-EOF
      {
        "subject": "GuardDuty Alert: <title>",
        "message": "GUARDDUTY SECURITY ALERT\n\nSeverity: <severity>\nType: <type>\nTime: <time>\nRegion: <region>\nAccount: <account>\n\nTitle: <title>\n\nDescription: <description>\n\nFinding ID: <findingId>\n\nPlease investigate this finding in the AWS GuardDuty console immediately."
      }
    EOF
  }
}

# -----------------------------------------------------------------------------
# EventBridge Rule - Security Hub Critical Findings
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "securityhub_findings" {
  count = var.enable_guardduty && var.security_alert_email != "" ? 1 : 0

  name        = "${var.name_prefix}-securityhub-critical-findings"
  description = "Capture Security Hub Critical and High severity findings"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = ["CRITICAL", "HIGH"]
        }
        Workflow = {
          Status = ["NEW"]
        }
        RecordState = ["ACTIVE"]
      }
    }
  })

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-securityhub-critical-findings"
  })
}

resource "aws_cloudwatch_event_target" "securityhub_to_sns" {
  count = var.enable_guardduty && var.security_alert_email != "" ? 1 : 0

  rule      = aws_cloudwatch_event_rule.securityhub_findings[0].name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.security_alerts[0].arn

  input_transformer {
    input_paths = {
      severity     = "$.detail.findings[0].Severity.Label"
      title        = "$.detail.findings[0].Title"
      description  = "$.detail.findings[0].Description"
      productName  = "$.detail.findings[0].ProductName"
      region       = "$.region"
      account      = "$.account"
      time         = "$.time"
      findingId    = "$.detail.findings[0].Id"
      resourceType = "$.detail.findings[0].Resources[0].Type"
      resourceId   = "$.detail.findings[0].Resources[0].Id"
    }
    input_template = <<-EOF
      {
        "subject": "Security Hub Alert: <title>",
        "message": "SECURITY HUB ALERT\n\nSeverity: <severity>\nProduct: <productName>\nTime: <time>\nRegion: <region>\nAccount: <account>\n\nTitle: <title>\n\nDescription: <description>\n\nResource Type: <resourceType>\nResource ID: <resourceId>\n\nFinding ID: <findingId>\n\nPlease review this finding in the AWS Security Hub console."
      }
    EOF
  }
}

# -----------------------------------------------------------------------------
# IAM Role for GuardDuty Malware Protection
# -----------------------------------------------------------------------------
resource "aws_iam_role" "guardduty_malware_protection" {
  count = var.enable_guardduty ? 1 : 0

  name = "${var.name_prefix}-guardduty-malware-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "malware-protection.guardduty.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-guardduty-malware-role"
  })
}

resource "aws_iam_role_policy" "guardduty_malware_protection" {
  count = var.enable_guardduty ? 1 : 0

  name = "${var.name_prefix}-guardduty-malware-policy"
  role = aws_iam_role.guardduty_malware_protection[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowMalwareProtectionSnapshots"
        Effect = "Allow"
        Action = [
          "ec2:CreateSnapshot",
          "ec2:DeleteSnapshot",
          "ec2:DescribeSnapshots",
          "ec2:CreateTags"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:Region" = var.aws_region
          }
        }
      },
      {
        Sid    = "AllowKMSAccess"
        Effect = "Allow"
        Action = [
          "kms:CreateGrant",
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*"
        ]
        Resource = "arn:aws:kms:${var.aws_region}:${data.aws_caller_identity.current.account_id}:key/*"
        Condition = {
          StringLike = {
            "kms:ViaService" = "ec2.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })
}

# =============================================================================
# WAF SECTION
# =============================================================================

# -----------------------------------------------------------------------------
# KMS Key for WAF Log Encryption
# -----------------------------------------------------------------------------
resource "aws_kms_key" "waf_logs" {
  count = var.enable_waf && var.waf_enable_logging ? 1 : 0

  description             = "KMS key for WAF log encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccountPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowCloudWatchLogsToEncrypt"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:aws-waf-logs-*"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-waf-logs-key"
  })
}

resource "aws_kms_alias" "waf_logs" {
  count = var.enable_waf && var.waf_enable_logging ? 1 : 0

  name          = "alias/${var.name_prefix}-waf-logs"
  target_key_id = aws_kms_key.waf_logs[0].key_id
}

# -----------------------------------------------------------------------------
# WAFv2 Web ACL
# -----------------------------------------------------------------------------
resource "aws_wafv2_web_acl" "main" {
  count = var.enable_waf ? 1 : 0

  name        = "${var.name_prefix}-waf"
  description = "WAF Web ACL for ${var.name_prefix} ALB"
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
      metric_name                = "${var.name_prefix}-common-rules"
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
      metric_name                = "${var.name_prefix}-sqli-rules"
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
      metric_name                = "${var.name_prefix}-bad-inputs-rules"
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
      metric_name                = "${var.name_prefix}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-waf"
    sampled_requests_enabled   = true
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-waf"
  })
}

# -----------------------------------------------------------------------------
# WAF Web ACL Association with ALB
# -----------------------------------------------------------------------------
resource "aws_wafv2_web_acl_association" "alb" {
  count = var.enable_waf && var.attach_waf_to_alb ? 1 : 0

  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.main[0].arn
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group for WAF Logs (Optional)
# -----------------------------------------------------------------------------
# WAF log group names must start with "aws-waf-logs-" prefix
resource "aws_cloudwatch_log_group" "waf" {
  count = var.enable_waf && var.waf_enable_logging ? 1 : 0

  name              = "aws-waf-logs-${var.name_prefix}"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.waf_logs[0].arn

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-waf-logs"
  })
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

  policy_name = "${var.name_prefix}-waf-logging"

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
            "aws:SourceArn" = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      }
    ]
  })
}
