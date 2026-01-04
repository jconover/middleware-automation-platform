# =============================================================================
# AWS GuardDuty and Security Hub Configuration
# =============================================================================
# This file implements:
# - GuardDuty Detector with S3 and EBS protection
# - Security Hub with CIS and AWS Foundational benchmarks
# - SNS Topic for security alerts with KMS encryption
# - EventBridge rules for high-severity finding notifications
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

  tags = {
    Name = "${local.name_prefix}-guardduty"
  }
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

  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}::standards/cis-aws-foundations-benchmark/v/1.4.0"

  depends_on = [aws_securityhub_account.main]
}

# AWS Foundational Security Best Practices
resource "aws_securityhub_standards_subscription" "aws_foundational" {
  count = var.enable_guardduty ? 1 : 0

  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}::standards/aws-foundational-security-best-practices/v/1.0.0"

  depends_on = [aws_securityhub_account.main]
}

# Enable GuardDuty integration with Security Hub
resource "aws_securityhub_product_subscription" "guardduty" {
  count = var.enable_guardduty ? 1 : 0

  product_arn = "arn:aws:securityhub:${data.aws_region.current.name}::product/aws/guardduty"

  depends_on = [
    aws_securityhub_account.main,
    aws_guardduty_detector.main
  ]
}

# -----------------------------------------------------------------------------
# KMS Key for SNS Encryption
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

  tags = {
    Name = "${local.name_prefix}-security-alerts-key"
  }
}

resource "aws_kms_alias" "security_alerts" {
  count = var.enable_guardduty && var.security_alert_email != "" ? 1 : 0

  name          = "alias/${local.name_prefix}-security-alerts"
  target_key_id = aws_kms_key.security_alerts[0].key_id
}

# -----------------------------------------------------------------------------
# SNS Topic for Security Alerts
# -----------------------------------------------------------------------------
resource "aws_sns_topic" "security_alerts" {
  count = var.enable_guardduty && var.security_alert_email != "" ? 1 : 0

  name              = "${local.name_prefix}-security-alerts"
  kms_master_key_id = aws_kms_key.security_alerts[0].id

  tags = {
    Name = "${local.name_prefix}-security-alerts"
  }
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
            "aws:SourceArn" = "arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:rule/${local.name_prefix}-*"
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

# Email Subscription
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

  name        = "${local.name_prefix}-guardduty-high-findings"
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

  tags = {
    Name = "${local.name_prefix}-guardduty-high-findings"
  }
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

  name        = "${local.name_prefix}-securityhub-critical-findings"
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

  tags = {
    Name = "${local.name_prefix}-securityhub-critical-findings"
  }
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
# IAM Role for GuardDuty (if needed for additional features)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "guardduty_malware_protection" {
  count = var.enable_guardduty ? 1 : 0

  name = "${local.name_prefix}-guardduty-malware-role"

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

  tags = {
    Name = "${local.name_prefix}-guardduty-malware-role"
  }
}

resource "aws_iam_role_policy" "guardduty_malware_protection" {
  count = var.enable_guardduty ? 1 : 0

  name = "${local.name_prefix}-guardduty-malware-policy"
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
            "ec2:Region" = data.aws_region.current.name
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
        Resource = "arn:aws:kms:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:key/*"
        Condition = {
          StringLike = {
            "kms:ViaService" = "ec2.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      }
    ]
  })
}
