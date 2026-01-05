# =============================================================================
# S3 Cross-Region Replication for Disaster Recovery
# =============================================================================
# Implements cross-region replication from us-east-1 (primary) to us-west-2 (DR)
# for critical log data: ALB access logs and CloudTrail audit logs.
#
# Benefits:
# - Geographic redundancy for compliance and audit data
# - Enables DR region access to historical logs
# - Meets regulatory requirements for data residency
# - Supports business continuity planning
# =============================================================================

# -----------------------------------------------------------------------------
# Secondary Region Provider (DR Region)
# -----------------------------------------------------------------------------
provider "aws" {
  alias  = "dr"
  region = var.dr_region

  default_tags {
    tags = merge(
      {
        Project     = var.project_name
        Environment = var.environment
        ManagedBy   = "terraform"
        Purpose     = "disaster-recovery"
      },
      var.additional_tags
    )
  }
}

# -----------------------------------------------------------------------------
# KMS Key for Destination Bucket Encryption (DR Region)
# -----------------------------------------------------------------------------
resource "aws_kms_key" "dr_replication" {
  count    = var.enable_s3_replication ? 1 : 0
  provider = aws.dr

  description             = "KMS key for S3 replication destination buckets in DR region"
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
        Sid    = "AllowS3ReplicationDecrypt"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.s3_replication[0].arn
        }
        Action = [
          "kms:Encrypt",
          "kms:GenerateDataKey*"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "s3.${var.dr_region}.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-dr-replication-key"
  }
}

resource "aws_kms_alias" "dr_replication" {
  count    = var.enable_s3_replication ? 1 : 0
  provider = aws.dr

  name          = "alias/${local.name_prefix}-dr-replication"
  target_key_id = aws_kms_key.dr_replication[0].key_id
}

# -----------------------------------------------------------------------------
# IAM Role for S3 Replication
# -----------------------------------------------------------------------------
resource "aws_iam_role" "s3_replication" {
  count = var.enable_s3_replication ? 1 : 0

  name = "${local.name_prefix}-s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-s3-replication-role"
  }
}

resource "aws_iam_role_policy" "s3_replication" {
  count = var.enable_s3_replication ? 1 : 0

  name = "${local.name_prefix}-s3-replication-policy"
  role = aws_iam_role.s3_replication[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid    = "SourceBucketPermissions"
          Effect = "Allow"
          Action = [
            "s3:GetReplicationConfiguration",
            "s3:ListBucket"
          ]
          Resource = compact([
            aws_s3_bucket.alb_logs.arn,
            var.enable_cloudtrail ? aws_s3_bucket.cloudtrail[0].arn : ""
          ])
        },
        {
          Sid    = "SourceObjectPermissions"
          Effect = "Allow"
          Action = [
            "s3:GetObjectVersionForReplication",
            "s3:GetObjectVersionAcl",
            "s3:GetObjectVersionTagging"
          ]
          Resource = compact([
            "${aws_s3_bucket.alb_logs.arn}/*",
            var.enable_cloudtrail ? "${aws_s3_bucket.cloudtrail[0].arn}/*" : ""
          ])
        },
        {
          Sid    = "DestinationBucketPermissions"
          Effect = "Allow"
          Action = [
            "s3:ReplicateObject",
            "s3:ReplicateDelete",
            "s3:ReplicateTags",
            "s3:ObjectOwnerOverrideToBucketOwner"
          ]
          Resource = compact([
            "${aws_s3_bucket.alb_logs_dr[0].arn}/*",
            var.enable_cloudtrail ? "${aws_s3_bucket.cloudtrail_dr[0].arn}/*" : ""
          ])
        },
        {
          Sid    = "DestinationKMSEncrypt"
          Effect = "Allow"
          Action = [
            "kms:Encrypt",
            "kms:GenerateDataKey*"
          ]
          Resource = [
            aws_kms_key.dr_replication[0].arn
          ]
        }
      ],
      # Only include CloudTrail KMS decrypt permissions when CloudTrail is enabled
      var.enable_cloudtrail ? [
        {
          Sid    = "SourceKMSDecryptCloudTrail"
          Effect = "Allow"
          Action = [
            "kms:Decrypt"
          ]
          Resource = [
            aws_kms_key.cloudtrail[0].arn
          ]
          Condition = {
            StringLike = {
              "kms:ViaService" = "s3.${var.aws_region}.amazonaws.com"
            }
          }
        }
      ] : []
    )
  })
}

# =============================================================================
# ALB Logs - DR Destination Bucket
# =============================================================================

resource "aws_s3_bucket" "alb_logs_dr" {
  count    = var.enable_s3_replication ? 1 : 0
  provider = aws.dr

  bucket = "${local.name_prefix}-alb-logs-dr-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name         = "${local.name_prefix}-alb-logs-dr"
    SourceBucket = aws_s3_bucket.alb_logs.id
    Region       = var.dr_region
  }
}

resource "aws_s3_bucket_versioning" "alb_logs_dr" {
  count    = var.enable_s3_replication ? 1 : 0
  provider = aws.dr

  bucket = aws_s3_bucket.alb_logs_dr[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs_dr" {
  count    = var.enable_s3_replication ? 1 : 0
  provider = aws.dr

  bucket = aws_s3_bucket.alb_logs_dr[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.dr_replication[0].arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "alb_logs_dr" {
  count    = var.enable_s3_replication ? 1 : 0
  provider = aws.dr

  bucket = aws_s3_bucket.alb_logs_dr[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs_dr" {
  count    = var.enable_s3_replication ? 1 : 0
  provider = aws.dr

  bucket = aws_s3_bucket.alb_logs_dr[0].id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {
      prefix = ""
    }

    # Keep DR copies longer for compliance
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs_dr" {
  count    = var.enable_s3_replication ? 1 : 0
  provider = aws.dr

  bucket = aws_s3_bucket.alb_logs_dr[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.alb_logs_dr[0].arn,
          "${aws_s3_bucket.alb_logs_dr[0].arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid    = "AllowReplicationFromSource"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.s3_replication[0].arn
        }
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags",
          "s3:ObjectOwnerOverrideToBucketOwner"
        ]
        Resource = "${aws_s3_bucket.alb_logs_dr[0].arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.alb_logs_dr]
}

# -----------------------------------------------------------------------------
# ALB Logs - Source Bucket Replication Configuration
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_replication_configuration" "alb_logs" {
  count = var.enable_s3_replication ? 1 : 0

  # Must have bucket versioning enabled first
  depends_on = [aws_s3_bucket_versioning.alb_logs]

  role   = aws_iam_role.s3_replication[0].arn
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "alb-logs-dr-replication"
    status = "Enabled"

    filter {
      prefix = ""
    }

    destination {
      bucket        = aws_s3_bucket.alb_logs_dr[0].arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.dr_replication[0].arn
      }

      metrics {
        status = "Enabled"
        event_threshold {
          minutes = 15
        }
      }

      replication_time {
        status = "Enabled"
        time {
          minutes = 15
        }
      }
    }

    # Replicate delete markers for complete audit trail
    delete_marker_replication {
      status = "Enabled"
    }
  }
}

# =============================================================================
# CloudTrail Logs - DR Destination Bucket
# =============================================================================

resource "aws_s3_bucket" "cloudtrail_dr" {
  count    = var.enable_s3_replication && var.enable_cloudtrail ? 1 : 0
  provider = aws.dr

  bucket = "${local.name_prefix}-cloudtrail-logs-dr-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name         = "${local.name_prefix}-cloudtrail-logs-dr"
    SourceBucket = aws_s3_bucket.cloudtrail[0].id
    Region       = var.dr_region
  }
}

resource "aws_s3_bucket_versioning" "cloudtrail_dr" {
  count    = var.enable_s3_replication && var.enable_cloudtrail ? 1 : 0
  provider = aws.dr

  bucket = aws_s3_bucket.cloudtrail_dr[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_dr" {
  count    = var.enable_s3_replication && var.enable_cloudtrail ? 1 : 0
  provider = aws.dr

  bucket = aws_s3_bucket.cloudtrail_dr[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.dr_replication[0].arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_dr" {
  count    = var.enable_s3_replication && var.enable_cloudtrail ? 1 : 0
  provider = aws.dr

  bucket = aws_s3_bucket.cloudtrail_dr[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail_dr" {
  count    = var.enable_s3_replication && var.enable_cloudtrail ? 1 : 0
  provider = aws.dr

  bucket = aws_s3_bucket.cloudtrail_dr[0].id

  rule {
    id     = "cloudtrail-logs-lifecycle"
    status = "Enabled"

    filter {
      prefix = ""
    }

    # Keep CloudTrail logs longer for compliance (7 years is common)
    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 180
      storage_class = "GLACIER"
    }

    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"
    }

    # 7-year retention for compliance
    expiration {
      days = 2555
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

resource "aws_s3_bucket_policy" "cloudtrail_dr" {
  count    = var.enable_s3_replication && var.enable_cloudtrail ? 1 : 0
  provider = aws.dr

  bucket = aws_s3_bucket.cloudtrail_dr[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.cloudtrail_dr[0].arn,
          "${aws_s3_bucket.cloudtrail_dr[0].arn}/*"
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
        Resource  = "${aws_s3_bucket.cloudtrail_dr[0].arn}/*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
        }
      },
      {
        Sid    = "AllowReplicationFromSource"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.s3_replication[0].arn
        }
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags",
          "s3:ObjectOwnerOverrideToBucketOwner"
        ]
        Resource = "${aws_s3_bucket.cloudtrail_dr[0].arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.cloudtrail_dr]
}

# -----------------------------------------------------------------------------
# CloudTrail Logs - Source Bucket Replication Configuration
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_replication_configuration" "cloudtrail" {
  count = var.enable_s3_replication && var.enable_cloudtrail ? 1 : 0

  # Must have bucket versioning enabled first
  depends_on = [aws_s3_bucket_versioning.cloudtrail]

  role   = aws_iam_role.s3_replication[0].arn
  bucket = aws_s3_bucket.cloudtrail[0].id

  rule {
    id     = "cloudtrail-logs-dr-replication"
    status = "Enabled"

    filter {
      prefix = ""
    }

    destination {
      bucket        = aws_s3_bucket.cloudtrail_dr[0].arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.dr_replication[0].arn
      }

      metrics {
        status = "Enabled"
        event_threshold {
          minutes = 15
        }
      }

      replication_time {
        status = "Enabled"
        time {
          minutes = 15
        }
      }
    }

    # Enable Server Side Encryption KMS for source objects
    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }

    # Replicate delete markers for complete audit trail
    delete_marker_replication {
      status = "Enabled"
    }
  }
}

# =============================================================================
# CloudWatch Alarms for Replication Monitoring
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "alb_logs_replication_latency" {
  count = var.enable_s3_replication ? 1 : 0

  alarm_name          = "${local.name_prefix}-alb-logs-replication-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ReplicationLatency"
  namespace           = "AWS/S3"
  period              = 300
  statistic           = "Average"
  threshold           = 900 # 15 minutes in seconds
  alarm_description   = "ALB logs replication to DR region is delayed beyond 15 minutes"
  treat_missing_data  = "notBreaching"

  dimensions = {
    SourceBucket      = aws_s3_bucket.alb_logs.id
    DestinationBucket = aws_s3_bucket.alb_logs_dr[0].id
    RuleId            = "alb-logs-dr-replication"
  }

  tags = {
    Name = "${local.name_prefix}-alb-logs-replication-latency-alarm"
  }
}

resource "aws_cloudwatch_metric_alarm" "cloudtrail_replication_latency" {
  count = var.enable_s3_replication && var.enable_cloudtrail ? 1 : 0

  alarm_name          = "${local.name_prefix}-cloudtrail-replication-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ReplicationLatency"
  namespace           = "AWS/S3"
  period              = 300
  statistic           = "Average"
  threshold           = 900 # 15 minutes in seconds
  alarm_description   = "CloudTrail logs replication to DR region is delayed beyond 15 minutes"
  treat_missing_data  = "notBreaching"

  dimensions = {
    SourceBucket      = aws_s3_bucket.cloudtrail[0].id
    DestinationBucket = aws_s3_bucket.cloudtrail_dr[0].id
    RuleId            = "cloudtrail-logs-dr-replication"
  }

  tags = {
    Name = "${local.name_prefix}-cloudtrail-replication-latency-alarm"
  }
}

# =============================================================================
# Outputs
# =============================================================================

output "s3_replication_enabled" {
  description = "Whether S3 cross-region replication is enabled"
  value       = var.enable_s3_replication
}

output "dr_region" {
  description = "DR region for S3 replication"
  value       = var.enable_s3_replication ? var.dr_region : null
}

output "alb_logs_dr_bucket" {
  description = "ALB logs DR destination bucket name"
  value       = var.enable_s3_replication ? aws_s3_bucket.alb_logs_dr[0].id : null
}

output "alb_logs_dr_bucket_arn" {
  description = "ALB logs DR destination bucket ARN"
  value       = var.enable_s3_replication ? aws_s3_bucket.alb_logs_dr[0].arn : null
}

output "cloudtrail_logs_dr_bucket" {
  description = "CloudTrail logs DR destination bucket name"
  value       = var.enable_s3_replication && var.enable_cloudtrail ? aws_s3_bucket.cloudtrail_dr[0].id : null
}

output "cloudtrail_logs_dr_bucket_arn" {
  description = "CloudTrail logs DR destination bucket ARN"
  value       = var.enable_s3_replication && var.enable_cloudtrail ? aws_s3_bucket.cloudtrail_dr[0].arn : null
}

output "s3_replication_role_arn" {
  description = "IAM role ARN used for S3 replication"
  value       = var.enable_s3_replication ? aws_iam_role.s3_replication[0].arn : null
}

output "dr_kms_key_arn" {
  description = "KMS key ARN in DR region for replication encryption"
  value       = var.enable_s3_replication ? aws_kms_key.dr_replication[0].arn : null
}

output "s3_replication_configuration" {
  description = "Summary of S3 cross-region replication configuration"
  value = var.enable_s3_replication ? {
    enabled                   = true
    source_region             = var.aws_region
    destination_region        = var.dr_region
    alb_logs_source           = aws_s3_bucket.alb_logs.id
    alb_logs_destination      = aws_s3_bucket.alb_logs_dr[0].id
    cloudtrail_source         = var.enable_cloudtrail ? aws_s3_bucket.cloudtrail[0].id : null
    cloudtrail_destination    = var.enable_cloudtrail ? aws_s3_bucket.cloudtrail_dr[0].id : null
    replication_time_control  = "15 minutes"
    delete_marker_replication = true
    encryption                = "KMS"
    } : {
    enabled = false
    message = "S3 cross-region replication is disabled. Set enable_s3_replication = true to enable DR."
  }
}
