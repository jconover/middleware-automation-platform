# =============================================================================
# Security Compliance Module - Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# CloudTrail Outputs
# -----------------------------------------------------------------------------
output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail"
  value       = var.enable_cloudtrail ? aws_cloudtrail.main[0].arn : null
}

output "cloudtrail_s3_bucket" {
  description = "Name of the S3 bucket for CloudTrail logs"
  value       = var.enable_cloudtrail ? aws_s3_bucket.cloudtrail[0].id : null
}

output "cloudtrail_s3_bucket_arn" {
  description = "ARN of the S3 bucket for CloudTrail logs"
  value       = var.enable_cloudtrail ? aws_s3_bucket.cloudtrail[0].arn : null
}

output "cloudtrail_log_group_name" {
  description = "Name of the CloudWatch Log Group for CloudTrail"
  value       = var.enable_cloudtrail ? aws_cloudwatch_log_group.cloudtrail[0].name : null
}

output "cloudtrail_log_group_arn" {
  description = "ARN of the CloudWatch Log Group for CloudTrail"
  value       = var.enable_cloudtrail ? aws_cloudwatch_log_group.cloudtrail[0].arn : null
}

output "cloudtrail_kms_key_arn" {
  description = "ARN of the KMS key used for CloudTrail encryption"
  value       = var.enable_cloudtrail ? aws_kms_key.cloudtrail[0].arn : null
}

output "cloudtrail_kms_key_id" {
  description = "ID of the KMS key used for CloudTrail encryption"
  value       = var.enable_cloudtrail ? aws_kms_key.cloudtrail[0].key_id : null
}

output "cloudtrail_sns_topic_arn" {
  description = "ARN of the SNS topic for CloudTrail alarms"
  value       = var.enable_cloudtrail ? aws_sns_topic.cloudtrail_alarms[0].arn : null
}

# -----------------------------------------------------------------------------
# GuardDuty and Security Hub Outputs
# -----------------------------------------------------------------------------
output "guardduty_detector_id" {
  description = "ID of the GuardDuty detector"
  value       = var.enable_guardduty ? aws_guardduty_detector.main[0].id : null
}

output "guardduty_detector_arn" {
  description = "ARN of the GuardDuty detector"
  value       = var.enable_guardduty ? aws_guardduty_detector.main[0].arn : null
}

output "security_hub_arn" {
  description = "ARN of the Security Hub account"
  value       = var.enable_guardduty ? aws_securityhub_account.main[0].arn : null
}

output "security_hub_id" {
  description = "ID of the Security Hub account"
  value       = var.enable_guardduty ? aws_securityhub_account.main[0].id : null
}

output "security_alerts_sns_topic_arn" {
  description = "ARN of the SNS topic for GuardDuty/Security Hub alerts"
  value       = var.enable_guardduty && var.security_alert_email != "" ? aws_sns_topic.security_alerts[0].arn : null
}

output "security_alerts_kms_key_arn" {
  description = "ARN of the KMS key used for security alerts SNS topic"
  value       = var.enable_guardduty && var.security_alert_email != "" ? aws_kms_key.security_alerts[0].arn : null
}

# -----------------------------------------------------------------------------
# WAF Outputs
# -----------------------------------------------------------------------------
output "waf_web_acl_arn" {
  description = "ARN of the WAF Web ACL"
  value       = var.enable_waf ? aws_wafv2_web_acl.main[0].arn : null
}

output "waf_web_acl_id" {
  description = "ID of the WAF Web ACL"
  value       = var.enable_waf ? aws_wafv2_web_acl.main[0].id : null
}

output "waf_web_acl_capacity" {
  description = "Web ACL capacity units (WCUs) used"
  value       = var.enable_waf ? aws_wafv2_web_acl.main[0].capacity : null
}

output "waf_log_group_arn" {
  description = "ARN of the CloudWatch Log Group for WAF logs"
  value       = var.enable_waf && var.waf_enable_logging ? aws_cloudwatch_log_group.waf[0].arn : null
}

output "waf_log_group_name" {
  description = "Name of the CloudWatch Log Group for WAF logs"
  value       = var.enable_waf && var.waf_enable_logging ? aws_cloudwatch_log_group.waf[0].name : null
}

# -----------------------------------------------------------------------------
# Consolidated SNS Topic Output
# -----------------------------------------------------------------------------
output "sns_topic_arn" {
  description = <<-EOT
    Primary SNS topic ARN for security alerts.
    Returns the GuardDuty/Security Hub alerts topic if configured,
    otherwise returns the CloudTrail alarms topic, or null if neither enabled.
  EOT
  value = (
    var.enable_guardduty && var.security_alert_email != "" ? aws_sns_topic.security_alerts[0].arn :
    var.enable_cloudtrail ? aws_sns_topic.cloudtrail_alarms[0].arn :
    null
  )
}

# -----------------------------------------------------------------------------
# Helper Outputs
# -----------------------------------------------------------------------------
output "email_subscription_confirmation_required" {
  description = "Whether email subscription confirmation is required (true if email was configured)"
  value       = var.security_alert_email != ""
}

output "enabled_features" {
  description = "Map of which security features are enabled"
  value = {
    cloudtrail   = var.enable_cloudtrail
    guardduty    = var.enable_guardduty
    security_hub = var.enable_guardduty # Security Hub is tied to GuardDuty
    waf          = var.enable_waf
    waf_logging  = var.enable_waf && var.waf_enable_logging
  }
}
