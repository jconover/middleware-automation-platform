# ECS Module

## Status: UNUSED - For Reference Only

**This module is NOT currently used by the production environment.** See [../README.md](../README.md) for details.

## Purpose

Provides a complete AWS ECS Fargate deployment for Open Liberty:
- ECS cluster with Container Insights
- Task definition with configurable CPU/memory
- ECS service with deployment circuit breaker
- IAM roles (execution and task)
- ECR repository with lifecycle policies (optional)
- CloudWatch log group

## Resources Created

| Resource | Count | Description |
|----------|-------|-------------|
| `aws_ecs_cluster` | 1 | ECS cluster |
| `aws_ecs_task_definition` | 1 | Liberty container task |
| `aws_ecs_service` | 1 | ECS service |
| `aws_iam_role` | 2 | Execution and task roles |
| `aws_ecr_repository` | 0-1 | Container registry (if enabled) |
| `aws_cloudwatch_log_group` | 1 | Container logs |

## Usage Example

```hcl
module "ecs" {
  source = "../../modules/ecs"

  name_prefix        = "mw-prod"
  aws_region         = "us-east-1"
  private_subnet_ids = module.networking.private_subnet_ids
  security_group_ids = [module.security_groups.ecs_security_group_id]

  container_image = "${aws_ecr_repository.liberty.repository_url}:latest"
  task_cpu        = 512   # 0.5 vCPU
  task_memory     = 1024  # 1 GB
  desired_count   = 2

  environment_variables = [
    { name = "DB_HOST", value = aws_db_instance.main.address }
  ]

  secrets = [
    {
      name      = "DB_PASSWORD"
      valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:password::"
    }
  ]

  secrets_arns     = [aws_secretsmanager_secret.db_credentials.arn]
  target_group_arn = aws_lb_target_group.liberty_ecs.arn
}
```

## Task CPU/Memory Combinations

| CPU | Valid Memory Values |
|-----|---------------------|
| 256 | 512 MB, 1 GB, 2 GB |
| 512 | 1 GB - 4 GB |
| 1024 | 2 GB - 8 GB |
| 2048 | 4 GB - 16 GB |
| 4096 | 8 GB - 30 GB |

## Key Features

### Deployment Circuit Breaker
Enabled with automatic rollback:
```hcl
deployment_circuit_breaker {
  enable   = true
  rollback = true
}
```

### Health Check
Uses Liberty MicroProfile Health:
```hcl
healthCheck = {
  command = ["CMD-SHELL", "curl -f http://localhost:9080/health/ready || exit 1"]
}
```

### ECS Exec (Debugging)
```bash
aws ecs execute-command \
  --cluster mw-prod-cluster \
  --task <task-id> \
  --container liberty \
  --interactive \
  --command "/bin/bash"
```

## Key Outputs

| Output | Description |
|--------|-------------|
| `cluster_id` | ECS cluster ID |
| `cluster_name` | ECS cluster name |
| `service_name` | ECS service name |
| `task_definition_arn` | Task definition ARN |
| `ecr_repository_url` | ECR repository URL |

## Cost Estimate

| Resource | Monthly Cost (2 tasks, 512 CPU, 1024 MB) |
|----------|------------------------------------------|
| ECS Fargate tasks | ~$30 |
| CloudWatch Logs | ~$2.50 |
| ECR storage | ~$0.50 |
| **Total** | ~$33/month |

## Related Files

- [Module implementation](./main.tf)
- [Production inline implementation](../../environments/prod-aws/ecs.tf)

---

**Status:** Complete but unused
**Last Updated:** 2025-12-30
