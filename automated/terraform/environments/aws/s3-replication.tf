# =============================================================================
# S3 Cross-Region Replication for Disaster Recovery
# =============================================================================
# Implements cross-region replication from primary region to DR region
# for critical log data: ALB access logs and CloudTrail audit logs.
#
# Benefits:
# - Geographic redundancy for compliance and audit data
# - Enables DR region access to historical logs
# - Meets regulatory requirements for data residency
# - Supports business continuity planning
#
# Enable with: enable_s3_replication = true
# =============================================================================

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
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowS3ReplicationEncrypt"
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

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dr-replication-key"
  })
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

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-s3-replication-role"
  })
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
            module.loadbalancer.alb_logs_bucket_arn,
            var.enable_cloudtrail ? module.security_compliance.cloudtrail_s3_bucket_arn : ""
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
            "${module.loadbalancer.alb_logs_bucket_arn}/*",
            var.enable_cloudtrail ? "${module.security_compliance.cloudtrail_s3_bucket_arn}/*" : ""
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
            module.security_compliance.cloudtrail_kms_key_arn
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

  bucket        = "${local.name_prefix}-alb-logs-dr-${local.account_id}"
  force_destroy = true # Allow terraform destroy to delete bucket with contents

  tags = merge(local.common_tags, {
    Name         = "${local.name_prefix}-alb-logs-dr"
    SourceBucket = module.loadbalancer.alb_logs_bucket_id
    Region       = var.dr_region
  })
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

  # Must have bucket versioning enabled first (handled by loadbalancer module)
  role   = aws_iam_role.s3_replication[0].arn
  bucket = module.loadbalancer.alb_logs_bucket_id

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
# CloudTrail Logs - DR Destination Bucket
# =============================================================================

resource "aws_s3_bucket" "cloudtrail_dr" {
  count    = var.enable_s3_replication && var.enable_cloudtrail ? 1 : 0
  provider = aws.dr

  bucket        = "${local.name_prefix}-cloudtrail-logs-dr-${local.account_id}"
  force_destroy = true # Allow terraform destroy to delete bucket with contents

  tags = merge(local.common_tags, {
    Name         = "${local.name_prefix}-cloudtrail-logs-dr"
    SourceBucket = module.security_compliance.cloudtrail_s3_bucket
    Region       = var.dr_region
  })
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

  # Must have bucket versioning enabled first (handled by security_compliance module)
  role   = aws_iam_role.s3_replication[0].arn
  bucket = module.security_compliance.cloudtrail_s3_bucket

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
    SourceBucket      = module.loadbalancer.alb_logs_bucket_id
    DestinationBucket = aws_s3_bucket.alb_logs_dr[0].id
    RuleId            = "alb-logs-dr-replication"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-logs-replication-latency-alarm"
  })
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
    SourceBucket      = module.security_compliance.cloudtrail_s3_bucket
    DestinationBucket = aws_s3_bucket.cloudtrail_dr[0].id
    RuleId            = "cloudtrail-logs-dr-replication"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cloudtrail-replication-latency-alarm"
  })
}
