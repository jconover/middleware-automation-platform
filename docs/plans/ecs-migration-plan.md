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

### 6.1 File-Based ECS Service Discovery (Implemented)

The monitoring server uses file-based service discovery with a custom script that queries the ECS API.

**Why file_sd instead of ecs_sd:**
- Official Prometheus binaries don't include `ecs_sd_configs` (requires building from source)
- File-based discovery is reliable and well-supported
- Discovery script runs via cron every minute

**Components:**
1. **Discovery Script** (`/usr/local/bin/ecs-discovery.sh`): Queries ECS API for running tasks
2. **Targets File** (`/etc/prometheus/targets/ecs-liberty.json`): Updated by script
3. **Cron Job** (`/etc/cron.d/ecs-discovery`): Runs script every minute

**Dependencies (installed via user-data):**
- AWS CLI v2 (for ECS API calls)
- jq (for JSON processing)

**IAM Permissions Required:**
```hcl
# Added to monitoring.tf
- ecs:ListTasks
- ecs:DescribeTasks
- ec2:DescribeNetworkInterfaces
```

**Prometheus Configuration:**
```yaml
- job_name: 'ecs-liberty'
  metrics_path: '/metrics'
  file_sd_configs:
    - files:
        - /etc/prometheus/targets/ecs-liberty.json
      refresh_interval: 30s
```

**Discovery Script Output (ecs-liberty.json):**
```json
[
  {
    "targets": ["10.10.10.140:9080"],
    "labels": {
      "job": "ecs-liberty",
      "ecs_cluster": "mw-prod-cluster",
      "ecs_task_id": "abc123...",
      "container_name": "liberty",
      "environment": "production",
      "deployment_type": "ecs"
    }
  }
]
```

**Security Group Requirements:**
- Monitoring server security group must have access to ECS task security group on port 9080

### 6.2 ECS Alert Rules

New alerts in `/etc/prometheus/rules/ecs-alerts.yml`:
- **ECSLibertyTaskDown**: Task not responding (critical)
- **ECSLibertyNoTasks**: No tasks running (critical)
- **ECSLibertyHighHeapUsage**: Heap > 85% (warning)
- **ECSLibertyHighErrorRate**: 5xx > 5% (warning)

### 6.3 Grafana Dashboard

**Manual Import Required** (dashboard JSON exceeds EC2 user-data 16KB limit):

1. Access Grafana at `http://<monitoring-ip>:3000` (admin/admin)
2. Go to **Dashboards → New → Import**
3. Copy contents from `monitoring/grafana/dashboards/ecs-liberty.json`
4. Paste into the "Import via dashboard JSON model" text area
5. Click **Load**, then **Import**

**Alternative - using curl:**
```bash
# From a machine with access to the monitoring server
GRAFANA_URL="http://<monitoring-ip>:3000"
DASHBOARD_FILE="monitoring/grafana/dashboards/ecs-liberty.json"

curl -X POST "$GRAFANA_URL/api/dashboards/db" \
  -H "Content-Type: application/json" \
  -u admin:admin \
  -d "{\"dashboard\": $(cat $DASHBOARD_FILE), \"overwrite\": true}"
```

**Dashboard includes:**
- Healthy/unhealthy task counts
- Task up/down status timeline
- Request rate and error rates
- JVM heap usage per task
- ECS vs EC2 comparison panels (during migration)

### 6.4 CloudWatch Container Insights
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
- [x] Test traffic through ALB
- [x] Set up auto-scaling
- [x] Update CI/CD pipeline
- [x] Update monitoring (file_sd + discovery script + Grafana dashboard)
- [x] Decommission EC2 instances

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

## Phase 7: Decommission EC2 Liberty Instances

### Prerequisites
Before decommissioning, verify ECS is fully operational:

```bash
# 1. Check ECS service health
aws ecs describe-services --cluster mw-prod-cluster --services mw-prod-liberty \
  --query 'services[0].{status:status,running:runningCount,desired:desiredCount}'

# 2. Verify ECS target group has healthy targets
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups --names mw-prod-liberty-ecs-tg \
    --query 'TargetGroups[0].TargetGroupArn' --output text) \
  --query 'TargetHealthDescriptions[*].{Target:Target.Id,Health:TargetHealth.State}'

# 3. Test ECS endpoints via ALB (default route, no header needed after migration)
curl -s http://<alb-dns>/health/ready
curl -s http://<alb-dns>/api/info

# 4. Verify Prometheus is scraping ECS tasks
curl -s http://<monitoring-ip>:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="ecs-liberty")'
```

### 7.1 Switch ALB Default Route to ECS

Update `loadbalancer.tf` to make ECS the default target (remove header requirement):

```hcl
# Change the default action to forward to ECS target group
resource "aws_lb_listener" "http" {
  # ... existing config ...
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.liberty_ecs[0].arn  # Changed from liberty
  }
}
```

Or keep both and use weighted routing during transition:
```hcl
default_action {
  type = "forward"
  forward {
    target_group {
      arn    = aws_lb_target_group.liberty_ecs[0].arn
      weight = 100  # All traffic to ECS
    }
    target_group {
      arn    = aws_lb_target_group.liberty.arn
      weight = 0    # No traffic to EC2
    }
  }
}
```

### 7.2 Remove EC2 Liberty Instances

**Option A: Set instance count to 0 (reversible)**
```hcl
# In terraform.tfvars
liberty_instance_count = 0
```

**Option B: Remove EC2 resources entirely**
1. Remove from `compute.tf`:
   - `aws_instance.liberty`
   - `aws_lb_target_group_attachment.liberty`
   - `aws_lb_target_group_attachment.liberty_admin`

2. Remove from `loadbalancer.tf`:
   - `aws_lb_target_group.liberty` (EC2 target group)
   - Any listener rules routing to EC2

3. Update `security.tf`:
   - Remove `aws_security_group.liberty` if no longer needed
   - Remove EC2-specific security group rules

4. Clean up `monitoring.tf`:
   - Remove EC2 Liberty targets from Prometheus config
   - Keep only ECS discovery
   - **Important:** Update user_data template variables to handle empty EC2 list:
     ```hcl
     user_data = base64encode(templatefile("...", {
       liberty1_ip = length(aws_instance.liberty) > 0 ? aws_instance.liberty[0].private_ip : ""
       liberty2_ip = length(aws_instance.liberty) > 1 ? aws_instance.liberty[1].private_ip : (length(aws_instance.liberty) > 0 ? aws_instance.liberty[0].private_ip : "")
       # ... other vars
     }))
     ```

### 7.3 Update Prometheus Configuration

After EC2 removal, update monitoring to remove EC2 targets:

```yaml
# Remove this job from prometheus.yml
# - job_name: 'ec2-liberty'
#   static_configs:
#     - targets: ['${liberty1_ip}:9080', '${liberty2_ip}:9080']
```

### 7.4 Apply Changes

```bash
cd automated/terraform/environments/prod-aws

# Preview changes
terraform plan

# Apply (this will terminate EC2 instances)
terraform apply

# Verify ECS is still healthy after changes
aws ecs describe-services --cluster mw-prod-cluster --services mw-prod-liberty
```

### 7.5 Post-Decommission Verification

```bash
# Confirm no EC2 Liberty instances running
aws ec2 describe-instances --filters "Name=tag:Name,Values=*liberty*" \
  --query 'Reservations[*].Instances[*].{ID:InstanceId,State:State.Name}'

# Confirm ALB routes to ECS
curl -s http://<alb-dns>/health/ready

# Confirm monitoring only shows ECS targets
curl -s http://<monitoring-ip>:9090/api/v1/targets | \
  jq '[.data.activeTargets[] | select(.labels.job | contains("liberty"))]'
```

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
