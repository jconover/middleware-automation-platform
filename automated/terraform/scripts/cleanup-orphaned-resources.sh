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