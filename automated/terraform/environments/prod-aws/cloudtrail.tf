# =============================================================================
# CloudTrail - Audit Logging and Compliance
# =============================================================================
# Comprehensive AWS CloudTrail implementation for security auditing.
# Includes S3 bucket with lifecycle policies, KMS encryption, CloudWatch
# integration, and security-focused metric filters and alarms.
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
            "aws:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${local.name_prefix}-trail"
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
          Service = "logs.${data.aws_region.current.name}.amazonaws.com"
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
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:*"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-cloudtrail-key"
  }
}

resource "aws_kms_alias" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0

  name          = "alias/${local.name_prefix}-cloudtrail"
  target_key_id = aws_kms_key.cloudtrail[0].key_id
}

# -----------------------------------------------------------------------------
# S3 Bucket for CloudTrail Logs
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = "${local.name_prefix}-cloudtrail-logs-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${local.name_prefix}-cloudtrail-logs"
  }
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
            "aws:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${local.name_prefix}-trail"
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
            "aws:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${local.name_prefix}-trail"
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
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
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

  name              = "/aws/cloudtrail/${local.name_prefix}"
  retention_in_days = var.cloudtrail_log_retention_days
  kms_key_id        = aws_kms_key.cloudtrail[0].arn

  tags = {
    Name = "${local.name_prefix}-cloudtrail-logs"
  }
}

# -----------------------------------------------------------------------------
# IAM Role for CloudTrail to CloudWatch Logs
# -----------------------------------------------------------------------------
resource "aws_iam_role" "cloudtrail_cloudwatch" {
  count = var.enable_cloudtrail ? 1 : 0

  name = "${local.name_prefix}-cloudtrail-cloudwatch-role"

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

  tags = {
    Name = "${local.name_prefix}-cloudtrail-cloudwatch-role"
  }
}

resource "aws_iam_role_policy" "cloudtrail_cloudwatch" {
  count = var.enable_cloudtrail ? 1 : 0

  name = "${local.name_prefix}-cloudtrail-cloudwatch-policy"
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

  name                          = "${local.name_prefix}-trail"
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

  tags = {
    Name = "${local.name_prefix}-trail"
  }

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

  name              = "${local.name_prefix}-cloudtrail-alarms"
  kms_master_key_id = aws_kms_key.cloudtrail[0].id

  tags = {
    Name = "${local.name_prefix}-cloudtrail-alarms"
  }
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
            "aws:SourceArn" = "arn:aws:cloudwatch:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:alarm:*"
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Metric Filter: Unauthorized API Calls
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_metric_filter" "unauthorized_api_calls" {
  count = var.enable_cloudtrail ? 1 : 0

  name           = "${local.name_prefix}-unauthorized-api-calls"
  pattern        = "{ ($.errorCode = \"*UnauthorizedAccess*\") || ($.errorCode = \"AccessDenied*\") || ($.errorCode = \"AuthorizationError\") }"
  log_group_name = aws_cloudwatch_log_group.cloudtrail[0].name

  metric_transformation {
    name          = "UnauthorizedAPICalls"
    namespace     = "${local.name_prefix}/CloudTrail"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "unauthorized_api_calls" {
  count = var.enable_cloudtrail ? 1 : 0

  alarm_name          = "${local.name_prefix}-unauthorized-api-calls"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnauthorizedAPICalls"
  namespace           = "${local.name_prefix}/CloudTrail"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "This alarm monitors for unauthorized API calls. More than 5 in 5 minutes triggers the alarm."
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.cloudtrail_alarms[0].arn]
  ok_actions    = [aws_sns_topic.cloudtrail_alarms[0].arn]

  tags = {
    Name = "${local.name_prefix}-unauthorized-api-calls-alarm"
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Metric Filter: Root Account Usage
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_metric_filter" "root_account_usage" {
  count = var.enable_cloudtrail ? 1 : 0

  name           = "${local.name_prefix}-root-account-usage"
  pattern        = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"
  log_group_name = aws_cloudwatch_log_group.cloudtrail[0].name

  metric_transformation {
    name          = "RootAccountUsage"
    namespace     = "${local.name_prefix}/CloudTrail"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "root_account_usage" {
  count = var.enable_cloudtrail ? 1 : 0

  alarm_name          = "${local.name_prefix}-root-account-usage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "RootAccountUsage"
  namespace           = "${local.name_prefix}/CloudTrail"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "This alarm monitors for any use of the AWS root account. Any usage triggers the alarm."
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.cloudtrail_alarms[0].arn]
  ok_actions    = [aws_sns_topic.cloudtrail_alarms[0].arn]

  tags = {
    Name = "${local.name_prefix}-root-account-usage-alarm"
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Metric Filter: Console Login Without MFA
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_metric_filter" "console_login_without_mfa" {
  count = var.enable_cloudtrail ? 1 : 0

  name           = "${local.name_prefix}-console-login-without-mfa"
  pattern        = "{ ($.eventName = \"ConsoleLogin\") && ($.additionalEventData.MFAUsed != \"Yes\") && ($.userIdentity.type = \"IAMUser\") && ($.responseElements.ConsoleLogin = \"Success\") }"
  log_group_name = aws_cloudwatch_log_group.cloudtrail[0].name

  metric_transformation {
    name          = "ConsoleLoginWithoutMFA"
    namespace     = "${local.name_prefix}/CloudTrail"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "console_login_without_mfa" {
  count = var.enable_cloudtrail ? 1 : 0

  alarm_name          = "${local.name_prefix}-console-login-without-mfa"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ConsoleLoginWithoutMFA"
  namespace           = "${local.name_prefix}/CloudTrail"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "This alarm monitors for console logins without MFA. Any login without MFA triggers the alarm."
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.cloudtrail_alarms[0].arn]
  ok_actions    = [aws_sns_topic.cloudtrail_alarms[0].arn]

  tags = {
    Name = "${local.name_prefix}-console-login-without-mfa-alarm"
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "cloudtrail_trail_arn" {
  description = "ARN of the CloudTrail trail"
  value       = var.enable_cloudtrail ? aws_cloudtrail.main[0].arn : null
}

output "cloudtrail_s3_bucket" {
  description = "Name of the S3 bucket for CloudTrail logs"
  value       = var.enable_cloudtrail ? aws_s3_bucket.cloudtrail[0].id : null
}

output "cloudtrail_log_group" {
  description = "Name of the CloudWatch Log Group for CloudTrail"
  value       = var.enable_cloudtrail ? aws_cloudwatch_log_group.cloudtrail[0].name : null
}

output "cloudtrail_kms_key_arn" {
  description = "ARN of the KMS key used for CloudTrail encryption"
  value       = var.enable_cloudtrail ? aws_kms_key.cloudtrail[0].arn : null
}

output "cloudtrail_sns_topic_arn" {
  description = "ARN of the SNS topic for CloudTrail alarms"
  value       = var.enable_cloudtrail ? aws_sns_topic.cloudtrail_alarms[0].arn : null
}

output "cloudtrail_alarm_subscription_command" {
  description = "AWS CLI command to subscribe an email to CloudTrail alarms"
  value       = var.enable_cloudtrail ? "aws sns subscribe --topic-arn ${aws_sns_topic.cloudtrail_alarms[0].arn} --protocol email --notification-endpoint YOUR_EMAIL@example.com" : null
}
