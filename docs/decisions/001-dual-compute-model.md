# ADR 001: Dual Compute Model (ECS Fargate and EC2)

## Status

Accepted

## Context

The Middleware Automation Platform needed to deploy Open Liberty application servers to AWS production. Two primary compute options were available:

1. **ECS Fargate** - Serverless container orchestration with no infrastructure management
2. **EC2 Instances** - Traditional virtual machines with full control over the operating system

Different organizations and use cases have varying requirements:

- Some teams prefer serverless approaches to minimize operational overhead
- Some teams require full OS-level control for compliance, debugging, or legacy integration
- Migration scenarios often require running both models simultaneously for comparison or gradual cutover
- Cost optimization may favor one model over another depending on workload characteristics

Additionally, the platform needed to support A/B testing and blue-green deployment patterns during infrastructure changes.

## Decision

We decided to implement a **configurable dual compute model** that supports ECS Fargate, EC2 instances, or both simultaneously via Terraform variables:

```hcl
# Option 1: ECS Fargate only (default)
ecs_enabled = true
liberty_instance_count = 0

# Option 2: EC2 instances only
ecs_enabled = false
liberty_instance_count = 2

# Option 3: Both (migration/comparison)
ecs_enabled = true
liberty_instance_count = 2
```

When both compute models are enabled:
- Default traffic routes to ECS Fargate
- EC2 instances are accessible via the `X-Target: ec2` HTTP header
- Both target groups share the same Application Load Balancer

### Implementation Details

- `ecs.tf` defines the ECS cluster, service, task definition, and ECS-specific target group
- `compute.tf` defines EC2 instances for Liberty servers
- `loadbalancer.tf` implements header-based routing rules
- Both compute paths share the same RDS database and ElastiCache cluster
- Auto-scaling is configured for ECS (2-6 tasks based on CPU/memory/requests)
- EC2 instances are managed via Ansible for configuration consistency

## Consequences

### Positive

1. **Flexibility**: Organizations can choose the compute model that best fits their requirements
2. **Migration Support**: Running both models simultaneously enables gradual migration with fallback capability
3. **A/B Testing**: Header-based routing allows testing ECS vs EC2 performance with real traffic
4. **Cost Comparison**: Easy to compare actual costs between compute models in the same environment
5. **No Lock-in**: Teams are not forced into either serverless or traditional infrastructure
6. **Consistent Networking**: Both models share the same VPC, subnets, and security groups

### Negative

1. **Configuration Complexity**: Two compute paths mean more Terraform code and conditional logic
2. **Testing Overhead**: Both paths must be tested and maintained
3. **Potential Cost**: Running both models simultaneously (option 3) doubles compute costs
4. **Documentation Burden**: Users must understand both deployment models
5. **Monitoring Differences**: Different service discovery mechanisms required (file-based for ECS, static for EC2)

## Alternatives Considered

### Alternative 1: ECS Fargate Only

Deploy exclusively to ECS Fargate, removing EC2 support entirely.

**Rejected because**:
- Would prevent migration scenarios and comparison testing
- Some organizations have compliance requirements that mandate VM-level control
- Existing teams with Ansible expertise would lose their familiar tooling

### Alternative 2: EC2 Only with Auto Scaling Groups

Use traditional EC2 instances with Auto Scaling Groups for elasticity.

**Rejected because**:
- Higher operational overhead compared to Fargate
- Slower scaling response times
- More complex AMI management and patching workflows
- Would not demonstrate modern container orchestration patterns

### Alternative 3: Amazon EKS (Kubernetes)

Deploy to Amazon Elastic Kubernetes Service instead of ECS.

**Rejected because**:
- Higher complexity and cost for a demonstration platform
- Local Kubernetes already demonstrates container orchestration patterns
- ECS Fargate provides simpler serverless container deployment
- EKS requires cluster management overhead (control plane costs, upgrades)

## References

- Terraform configuration: `automated/terraform/environments/prod-aws/ecs.tf`
- Terraform configuration: `automated/terraform/environments/prod-aws/compute.tf`
- Load balancer routing: `automated/terraform/environments/prod-aws/loadbalancer.tf`
- ECS scaling policies: `automated/terraform/environments/prod-aws/ecs-scaling.tf`
