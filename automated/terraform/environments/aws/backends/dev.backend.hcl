# Development Backend Configuration
# Usage: terraform init -backend-config=backends/dev.backend.hcl

bucket         = "middleware-platform-terraform-state"
key            = "environments/dev/terraform.tfstate"
region         = "us-east-1"
encrypt        = true
dynamodb_table = "middleware-platform-terraform-locks"
