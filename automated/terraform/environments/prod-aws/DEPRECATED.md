# DEPRECATED

> **This environment is deprecated.** Use `environments/aws/` instead.

## Migration Notice

As of January 2026, the `prod-aws/` environment has been superseded by the unified `environments/aws/` directory, which now has full feature parity plus additional benefits:

| Feature | prod-aws (Legacy) | aws (Recommended) |
|---------|-------------------|-------------------|
| Multi-environment support | No (prod only) | Yes (dev/stage/prod) |
| Modular architecture | Partial (networking only) | Full (8 modules) |
| Code reuse | ~20% | ~85% |
| Backend isolation | Single state file | Per-environment state |
| Feature flags | Limited | Comprehensive |

## What Changed

The unified `environments/aws/` environment now includes all features from this legacy environment:

- Management Server (AWX/Jenkins EC2)
- Route53 DNS Failover
- S3 Cross-Region Replication
- SLO/SLI CloudWatch Alarms
- X-Ray Distributed Tracing
- ECR Cross-Region Replication

## Migration Steps

1. **Review the new environment:**
   ```bash
   cd ../aws
   cat README.md
   ```

2. **Initialize with your target environment:**
   ```bash
   terraform init -backend-config=backends/prod.backend.hcl
   ```

3. **Plan with production variables:**
   ```bash
   terraform plan -var-file=envs/prod.tfvars
   ```

4. **Migrate state (if applicable):**
   ```bash
   # Export resources from old state, import to new
   # See docs/plans/aws-migration-guide.md for details
   ```

## Timeline

- **Now**: New deployments should use `environments/aws/`
- **Future**: This directory will be archived after all production workloads migrate

## Questions?

See `environments/aws/README.md` for full documentation of the unified environment.
