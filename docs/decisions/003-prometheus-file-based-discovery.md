# ADR 003: Prometheus File-Based Discovery for ECS

## Status

Accepted

## Context

The Middleware Automation Platform uses Prometheus for metrics collection from Open Liberty application servers. When deploying to AWS ECS Fargate, Prometheus needs to discover running task IPs to scrape metrics from the `/metrics` endpoint.

Prometheus supports several service discovery mechanisms:

1. **Native `ecs_sd_configs`**: Built-in ECS service discovery configuration
2. **File-based discovery (`file_sd_configs`)**: Read targets from JSON/YAML files
3. **HTTP service discovery**: Query an HTTP endpoint for targets
4. **Static configuration**: Hardcoded target IPs

The challenge: **Official Prometheus binary releases do not include the `ecs_sd_configs` module**. This feature requires building Prometheus from source with custom build tags, or using community-maintained builds.

From the monitoring user-data script:
```
# Note: Using 2.54.1 - official binaries don't include ecs_sd_configs,
# so we use file_sd_configs with a discovery script instead
```

## Decision

We decided to use **file-based service discovery** (`file_sd_configs`) with a custom shell script that queries the AWS ECS API and generates target files.

### Implementation

1. **Discovery Script** (`/usr/local/bin/ecs-discovery.sh`):
   - Queries `ecs:ListTasks` for running tasks in the Liberty service
   - Queries `ecs:DescribeTasks` to get private IPs
   - Generates `/etc/prometheus/targets/ecs-liberty.json` in Prometheus file_sd format
   - Runs via cron every minute

2. **Prometheus Configuration**:
   ```yaml
   scrape_configs:
     - job_name: 'ecs-liberty'
       metrics_path: '/metrics'
       file_sd_configs:
         - files:
             - /etc/prometheus/targets/ecs-liberty.json
           refresh_interval: 30s
   ```

3. **IAM Permissions**: Monitoring server has IAM role with:
   - `ecs:ListClusters`
   - `ecs:ListTasks`
   - `ecs:DescribeTasks`
   - `ecs:DescribeServices`
   - `ec2:DescribeNetworkInterfaces`

4. **Target File Format**:
   ```json
   [
     {
       "targets": ["10.10.2.45:9080"],
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

## Consequences

### Positive

1. **Standard Prometheus Binary**: Uses official release without custom builds
2. **Simple Implementation**: Shell script is easy to understand and debug
3. **Rich Labels**: Discovery script adds custom labels (task ID, cluster, deployment type)
4. **Flexible Refresh**: Can adjust cron frequency independent of Prometheus
5. **Transparent Operation**: Target file can be inspected directly for troubleshooting
6. **AWS API Consistency**: Uses same AWS CLI available for other operations
7. **No External Dependencies**: No additional software or sidecars required

### Negative

1. **Polling Delay**: Up to 1 minute delay discovering new tasks (cron interval)
2. **External Process**: Separate cron job to monitor and maintain
3. **File I/O Overhead**: Writing to disk every minute
4. **Error Handling**: Script failures silently result in empty target file
5. **Not Real-Time**: Native SD would discover changes faster
6. **Maintenance Burden**: Custom script requires maintenance across Prometheus upgrades

## Alternatives Considered

### Alternative 1: Build Prometheus from Source with ecs_sd_configs

Build a custom Prometheus binary with the ECS service discovery module enabled.

**Rejected because**:
- Adds complexity to deployment (custom build pipeline)
- Must rebuild for each Prometheus security update
- Diverges from upstream releases, making upgrades harder
- Custom builds may lack community testing

### Alternative 2: Prometheus Operator Community Build

Use a community-maintained Prometheus build that includes ECS SD.

**Rejected because**:
- Uncertain long-term maintenance
- Security updates may lag behind official releases
- Trust concerns with non-official binaries
- Different behavior from documented upstream Prometheus

### Alternative 3: Consul or HashiCorp-Based Discovery

Deploy Consul agent on ECS tasks and use Consul service discovery.

**Rejected because**:
- Significant additional infrastructure (Consul cluster)
- Increased cost and complexity
- Overkill for the scale of this deployment
- Adds another system to learn and maintain

### Alternative 4: AWS Cloud Map + DNS Service Discovery

Register ECS tasks with AWS Cloud Map and use DNS-based discovery.

**Rejected because**:
- Requires additional AWS service configuration
- DNS-based discovery has caching/TTL complexities
- Less flexible labeling compared to file-based approach
- Additional monthly costs for Cloud Map

### Alternative 5: Sidecar Container Running Discovery

Run a discovery sidecar container alongside Prometheus.

**Rejected because**:
- Prometheus runs on EC2, not in a container
- Would require additional container orchestration
- More complex than a simple cron script
- Adds failure modes

## Implementation Notes

The discovery script handles edge cases:
- Empty task list: Writes `[]` to target file
- API failures: Previous target file preserved (Prometheus continues using cached version)
- Network interfaces: Extracts private IPv4 from task network configuration

For EC2-based deployments, static targets are used instead since instance IPs are known at Terraform apply time:
```yaml
scrape_configs:
  - job_name: 'liberty'
    static_configs:
      - targets: ['${liberty1_ip}:9080', '${liberty2_ip}:9080']
```

## References

- Monitoring server setup: `automated/terraform/environments/prod-aws/templates/monitoring-user-data.sh`
- IAM permissions: `automated/terraform/environments/prod-aws/monitoring.tf`
- Prometheus documentation: https://prometheus.io/docs/prometheus/latest/configuration/configuration/#file_sd_config
- ECS SD discussion: https://github.com/prometheus/prometheus/issues/3865
