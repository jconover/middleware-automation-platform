# ECS Fargate vs EC2 Deployment Comparison

This platform supports two compute models, controlled via `terraform.tfvars`.

```mermaid
flowchart TB
    subgraph CONFIG["Configuration Options"]
        OPT1["Option 1: ECS Only<br/>ecs_enabled = true<br/>liberty_instance_count = 0"]
        OPT2["Option 2: EC2 Only<br/>ecs_enabled = false<br/>liberty_instance_count = 2"]
        OPT3["Option 3: Both<br/>ecs_enabled = true<br/>liberty_instance_count = 2"]
    end

    ALB["Application Load Balancer"]

    subgraph ECS_PATH["ECS Fargate Path"]
        direction TB
        ECS_TG["Target Group<br/>(Default Route)"]
        ECS_SERVICE["ECS Service"]
        ECS_TASK1["Task 1"]
        ECS_TASK2["Task 2"]
        ECS_TASK3["Task N..."]

        ECS_TG --> ECS_SERVICE
        ECS_SERVICE --> ECS_TASK1
        ECS_SERVICE --> ECS_TASK2
        ECS_SERVICE --> ECS_TASK3

        ECS_SCALING["Auto-Scaling<br/>2-6 Tasks<br/>CPU/Memory/Requests"]
    end

    subgraph EC2_PATH["EC2 Instance Path"]
        direction TB
        EC2_TG["Target Group<br/>(X-Target: ec2 header)"]
        EC2_1["Liberty EC2 #1<br/>t3.small"]
        EC2_2["Liberty EC2 #2<br/>t3.small"]

        EC2_TG --> EC2_1
        EC2_TG --> EC2_2

        ANSIBLE["Ansible<br/>Configuration"]
        ANSIBLE -.->|Configure| EC2_1
        ANSIBLE -.->|Configure| EC2_2
    end

    ALB -->|"Default"| ECS_TG
    ALB -->|"X-Target: ec2"| EC2_TG

    style ECS_PATH fill:#fff3e0
    style EC2_PATH fill:#e8f5e9
    style ECS_SCALING fill:#ffcc80
```

## Feature Comparison

| Feature | ECS Fargate | EC2 Instances |
|---------|-------------|---------------|
| **Scaling** | Auto (2-6 tasks) | Manual / ASG |
| **Management** | Serverless | Full OS access |
| **Deployment** | Image pull (~2 min) | Ansible playbook (~10 min) |
| **Cost Model** | Per vCPU/memory/hour | Per instance/hour |
| **Customization** | Container only | Full system control |
| **Best For** | Production workloads | Legacy apps, debugging |

## Routing Configuration

```mermaid
flowchart LR
    CLIENT["Client Request"]

    subgraph ALB_RULES["ALB Listener Rules"]
        RULE1["Rule 1: Default<br/>Forward to ECS"]
        RULE2["Rule 2: Header Match<br/>X-Target: ec2<br/>Forward to EC2"]
    end

    ECS_TG2["ECS Target Group"]
    EC2_TG2["EC2 Target Group"]

    CLIENT --> ALB_RULES
    RULE1 --> ECS_TG2
    RULE2 --> EC2_TG2
```

## When to Use Each

**Choose ECS Fargate when:**
- You want minimal operational overhead
- Workloads are containerized and stateless
- You need rapid scaling
- Cost predictability is important

**Choose EC2 when:**
- You need full OS-level access
- Running legacy or non-containerized apps
- Debugging complex issues
- Cost optimization for steady-state workloads
