# ECS Fargate Migration Plan

## Overview

Migrate Liberty application servers from EC2 instances to ECS Fargate for improved scalability, easier deployments, and reduced operational overhead.

## Current State
- 2x EC2 t3.small instances running Liberty
- Manual WAR deployment to dropins
- ALB routing traffic to EC2 instances
- Ansible-based configuration management

## Target State
- ECS Fargate service running Liberty containers
- ECR for container image storage
- Auto-scaling based on CPU/memory
- Blue/green deployments
- Infrastructure as Code (Terraform)

---

## Phase 1: Container Registry Setup

### 1.1 Create ECR Repository
```hcl
# New file: ecr.tf
resource "aws_ecr_repository" "liberty" {
  name                 = "${local.name_prefix}-liberty"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
```

### 1.2 Build and Push Liberty Image
```bash
# Build from existing Containerfile
cd containers/liberty
podman build -t liberty-app:1.0.0 .

# Tag and push to ECR
aws ecr get-login-password | podman login --username AWS --password-stdin <account>.dkr.ecr.us-east-1.amazonaws.com
podman tag liberty-app:1.0.0 <account>.dkr.ecr.us-east-1.amazonaws.com/mw-prod-liberty:1.0.0
podman push <account>.dkr.ecr.us-east-1.amazonaws.com/mw-prod-liberty:1.0.0
```

---

## Phase 2: ECS Cluster and Task Definition

### 2.1 Create ECS Cluster
```hcl
# New file: ecs.tf
resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}
```

### 2.2 Create Task Definition
```hcl
resource "aws_ecs_task_definition" "liberty" {
  family                   = "${local.name_prefix}-liberty"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512   # 0.5 vCPU
  memory                   = 1024  # 1 GB
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name  = "liberty"
      image = "${aws_ecr_repository.liberty.repository_url}:latest"

      portMappings = [
        { containerPort = 9080, protocol = "tcp" },
        { containerPort = 9443, protocol = "tcp" }
      ]

      environment = [
        { name = "DB_HOST", value = aws_db_instance.postgres.address },
        { name = "REDIS_HOST", value = aws_elasticache_cluster.redis.cache_nodes[0].address }
      ]

      secrets = [
        { name = "DB_PASSWORD", valueFrom = aws_secretsmanager_secret.db_password.arn }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:9080/health/ready || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${local.name_prefix}-liberty"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "liberty"
        }
      }
    }
  ])
}
```

### 2.3 Create ECS Service
```hcl
resource "aws_ecs_service" "liberty" {
  name            = "${local.name_prefix}-liberty"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.liberty.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.liberty.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.liberty_ecs.arn
    container_name   = "liberty"
    container_port   = 9080
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_controller {
    type = "ECS"  # or "CODE_DEPLOY" for blue/green
  }
}
```

---

## Phase 3: Update Load Balancer

### 3.1 Create New Target Group for ECS
```hcl
resource "aws_lb_target_group" "liberty_ecs" {
  name        = "${local.name_prefix}-liberty-ecs-tg"
  port        = 9080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"  # Required for Fargate

  health_check {
    enabled             = true
    path                = "/health/ready"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }
}
```

### 3.2 Update ALB Listener
- Point ALB listener to new ECS target group
- Keep EC2 target group during migration for rollback

---

## Phase 4: Auto Scaling

### 4.1 Application Auto Scaling
```hcl
resource "aws_appautoscaling_target" "liberty" {
  max_capacity       = 6
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.liberty.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "liberty_cpu" {
  name               = "${local.name_prefix}-liberty-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.liberty.resource_id
  scalable_dimension = aws_appautoscaling_target.liberty.scalable_dimension
  service_namespace  = aws_appautoscaling_target.liberty.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
```

---

## Phase 5: CI/CD Pipeline Updates

### 5.1 Update Jenkins Pipeline
```groovy
// Add to Jenkinsfile
stage('Build Container') {
  steps {
    sh 'podman build -t liberty-app:${BUILD_NUMBER} containers/liberty/'
  }
}

stage('Push to ECR') {
  steps {
    sh '''
      aws ecr get-login-password | podman login --username AWS --password-stdin ${ECR_REPO}
      podman tag liberty-app:${BUILD_NUMBER} ${ECR_REPO}:${BUILD_NUMBER}
      podman tag liberty-app:${BUILD_NUMBER} ${ECR_REPO}:latest
      podman push ${ECR_REPO}:${BUILD_NUMBER}
      podman push ${ECR_REPO}:latest
    '''
  }
}

stage('Deploy to ECS') {
  steps {
    sh '''
      aws ecs update-service \
        --cluster ${ECS_CLUSTER} \
        --service ${ECS_SERVICE} \
        --force-new-deployment
    '''
  }
}
```

---

## Phase 6: Monitoring Updates

### 6.1 Update Prometheus Targets
- ECS tasks have dynamic IPs
- Use ECS service discovery or CloudMap
- Or scrape via CloudWatch Container Insights

### 6.2 CloudWatch Container Insights
- Already enabled via cluster setting
- Provides CPU, memory, network metrics
- Log aggregation in CloudWatch Logs

---

## Migration Checklist

- [x] Create ECR repository
- [x] Update Containerfile with sample-app
- [x] Build and push initial image
- [x] Create ECS cluster
- [x] Create IAM roles (execution + task)
- [x] Create CloudWatch log group
- [x] Create task definition
- [x] Create ECS target group
- [x] Create ECS service
- [ ] Test traffic through ALB
- [ ] Set up auto-scaling
- [ ] Update CI/CD pipeline
- [ ] Update monitoring
- [ ] Decommission EC2 instances

---

## Cost Comparison

| Resource | EC2 (Current) | ECS Fargate |
|----------|---------------|-------------|
| Compute (2 instances) | ~$30/mo | ~$40-50/mo |
| Scaling | Manual | Auto |
| Patching | Required | AWS managed |
| Deployment speed | Minutes | Seconds |

Fargate costs slightly more but reduces operational overhead significantly.

---

## Rollback Plan

If issues occur:
1. Keep EC2 instances running during migration
2. ALB can switch back to EC2 target group
3. Terraform state preserved for both

---

## Files to Create

```
automated/terraform/environments/prod-aws/
├── ecr.tf           # ECR repository
├── ecs.tf           # ECS cluster, service, task definition
├── ecs-iam.tf       # IAM roles for ECS
└── ecs-scaling.tf   # Auto-scaling policies

containers/liberty/
└── Containerfile    # Update with sample-app baked in

ci-cd/
└── Jenkinsfile      # Add container build/deploy stages
```
