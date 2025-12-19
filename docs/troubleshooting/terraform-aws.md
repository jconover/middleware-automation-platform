# Terraform AWS Troubleshooting

Common issues and solutions when working with Terraform and AWS infrastructure.

---

## Orphaned Resources After `terraform destroy`

Sometimes `terraform destroy` doesn't fully clean up all AWS resources, causing errors on subsequent `terraform apply`.

### Secrets Manager: Secret Scheduled for Deletion

**Error:**
```
Error: creating Secrets Manager Secret (mw-prod/database/credentials): InvalidRequestException:
You can't create this secret because a secret with this name is already scheduled for deletion.
```

**Cause:** Secrets Manager has a recovery window (default 7-30 days) before permanently deleting secrets.

**Solution:** Force delete the secret immediately:
```bash
aws secretsmanager delete-secret \
  --secret-id "mw-prod/database/credentials" \
  --force-delete-without-recovery
```

**Alternative:** Import the existing secret into Terraform state:
```bash
terraform import aws_secretsmanager_secret.db_credentials "mw-prod/database/credentials"
```

---

### CloudWatch Log Group Already Exists

**Error:**
```
Error: creating CloudWatch Logs Log Group (/aws/vpc/mw-prod-flow-logs):
ResourceAlreadyExistsException: The specified log group already exists
```

**Cause:** Log group wasn't deleted during `terraform destroy`.

**Solution:** Delete the log group manually:
```bash
aws logs delete-log-group --log-group-name "/aws/vpc/mw-prod-flow-logs"
```

**Alternative:** Import the existing log group into Terraform state:
```bash
terraform import aws_cloudwatch_log_group.flow_logs "/aws/vpc/mw-prod-flow-logs"
```

---

## Prevention Tips

### 1. Set Shorter Recovery Window for Secrets

In `database.tf`, set a shorter recovery window for non-production environments:

```hcl
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.environment_prefix}/database/credentials"
  recovery_window_in_days = 0  # Immediate deletion (use 7+ for production)
}
```

### 2. Use `force_destroy` for Log Groups

```hcl
resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/${var.environment_prefix}-flow-logs"
  retention_in_days = 30
  # No force_destroy needed - log groups delete cleanly
}
```

### 3. Check for Orphaned Resources Before Apply

```bash
# List secrets scheduled for deletion
aws secretsmanager list-secrets --include-planned-deletion --query 'SecretList[?DeletedDate!=`null`].Name'

# List log groups matching your prefix
aws logs describe-log-groups --log-group-name-prefix "/aws/vpc/mw-prod" --query 'logGroups[].logGroupName'
```

---

## Full Cleanup Script

Run this before `terraform apply` if you've previously destroyed the environment:

```bash
#!/bin/bash
# cleanup-orphaned-resources.sh

ENV_PREFIX="${1:-mw-prod}"

echo "Cleaning up orphaned AWS resources for: $ENV_PREFIX"

# Force delete secrets scheduled for deletion
echo "Checking Secrets Manager..."
aws secretsmanager delete-secret \
  --secret-id "${ENV_PREFIX}/database/credentials" \
  --force-delete-without-recovery 2>/dev/null && echo "  Deleted: ${ENV_PREFIX}/database/credentials" || echo "  Not found or already deleted"

# Delete orphaned log groups
echo "Checking CloudWatch Log Groups..."
aws logs delete-log-group \
  --log-group-name "/aws/vpc/${ENV_PREFIX}-flow-logs" 2>/dev/null && echo "  Deleted: /aws/vpc/${ENV_PREFIX}-flow-logs" || echo "  Not found or already deleted"

echo "Cleanup complete. You can now run 'terraform apply'"
```

Usage:
```bash
chmod +x cleanup-orphaned-resources.sh
./cleanup-orphaned-resources.sh mw-prod
```
