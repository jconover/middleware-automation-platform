# Staging Backend Configuration
# Usage: terraform init -backend-config=backends/stage.backend.hcl

bucket         = "middleware-platform-terraform-state"
key            = "environments/stage/terraform.tfstate"
region         = "us-east-1"
encrypt        = true
dynamodb_table = "middleware-platform-terraform-locks"
