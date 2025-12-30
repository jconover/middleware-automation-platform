# Compute Module

## Status: STUB - Not Implemented

**This module is a placeholder/stub that was never completed.**

## Original Intent

The compute module was intended to provide EC2 instance deployment for Open Liberty application servers, similar to the inline implementation in `automated/terraform/environments/prod-aws/compute.tf`.

## Current State

The directory exists but contains **no Terraform files**:
- No `main.tf`
- No `variables.tf`
- No `outputs.tf`

This is an **empty stub** left over from initial project planning.

## Options

### Option 1: Remove This Module (Recommended)

The inline implementation in `prod-aws/compute.tf` is complete and working. There's no current need for this module.

```bash
rm -rf automated/terraform/modules/compute
```

### Option 2: Implement the Module

If you want to modularize EC2 Liberty deployments, create a module that wraps:

**Resources needed:**
- `aws_instance` for Liberty servers
- `aws_launch_template` for consistent configuration
- `aws_autoscaling_group` (optional, for HA)
- `aws_lb_target_group_attachment` for ALB integration

**Reference:** See `automated/terraform/environments/prod-aws/compute.tf`

## Recommendation

**Remove this directory.** The inline implementation in `prod-aws/compute.tf` is:
- Complete and tested
- Well-documented
- Integrated with existing infrastructure
- Sufficient for current single-environment needs

## Related Files

- [Production EC2 implementation](../../environments/prod-aws/compute.tf)
- [Modules overview](../README.md)

---

**Status:** Empty stub, candidate for removal
**Last Updated:** 2025-12-30
