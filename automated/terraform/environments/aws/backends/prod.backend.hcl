# Production Backend Configuration
# Usage: terraform init -backend-config=backends/prod.backend.hcl

bucket         = "middleware-platform-terraform-state"
key            = "environments/prod/terraform.tfstate"
region         = "us-east-1"
encrypt        = true
dynamodb_table = "middleware-platform-terraform-locks"

# Optional: Use workspace prefix for additional isolation
# workspace_key_prefix = "workspaces"
