# =============================================================================
# Terraform Backend Configuration
# =============================================================================
# Prerequisites: Run the bootstrap/ terraform first to create the S3 bucket
# and DynamoDB table.
# =============================================================================

terraform {
  backend "s3" {
    bucket         = "middleware-platform-terraform-state"
    key            = "prod-aws/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "middleware-platform-terraform-locks"
    encrypt        = true
  }
}
