# Code Review: Portfolio Improvements

**Review Date:** 2026-01-02
**Purpose:** Improvements to make this project look professional for resume/portfolio
**Status:** Pending implementation

---

## Table of Contents

- [High Priority](#high-priority)
  - [Terraform](#terraform)
  - [Ansible](#ansible)
  - [CI/CD & Containers](#cicd--containers)
  - [Java Application](#java-application)
  - [Documentation & Structure](#documentation--structure)
- [Medium Priority](#medium-priority)
- [Quick Wins](#quick-wins)
- [Already Excellent](#already-excellent-highlight-these)

---

## High Priority

### Terraform

| Issue | Location | Details |
|-------|----------|---------|
| **Unused modules directory** | `automated/terraform/modules/` | Modules exist but are never used in prod-aws. Either delete them entirely or refactor prod-aws to use them. This is explicitly noted in `modules/README.md` but looks like incomplete refactoring. |
| **Security group egress too permissive** | All security groups in `security.tf`, `ecs.tf` | Every security group allows `0.0.0.0/0` outbound. ECS and Liberty servers should have restricted egress (only to RDS port 5432, Redis port 6379, HTTPS 443 for AWS APIs). |
| **Hardcoded backend config** | `automated/terraform/environments/prod-aws/backend.tf:9-15` | Backend configuration is hardcoded. Use a `backend.hcl` file pattern or partial configuration for multi-environment awareness. |
| **Missing tflint/tfsec integration** | Project root | No static analysis tooling configured. Add `.tflint.hcl` and document tfsec usage. |

**Hardcoded values to extract:**

| File | Line | Value | Suggested Variable |
|------|------|-------|-------------------|
| `compute.tf` | 94 | `volume_size = 30` | `liberty_root_volume_size` |
| `monitoring.tf` | 255 | `volume_size = 30` | `monitoring_root_volume_size` |
| `management.tf` | 472 | `volume_size = 50` | `management_root_volume_size` |
| `database.tf` | 73-74 | `backup_window = "03:00-04:00"` | `db_backup_window` |
| `ecs.tf` | 11 | `retention_in_days = 30` | `ecs_log_retention_days` |
| `loadbalancer.tf` | 101 | `expiration { days = 90 }` | `alb_log_retention_days` |

---

### Ansible

| Issue | Location | Details |
|-------|----------|---------|
| **Missing Molecule tests** | `roles/common/`, `roles/monitoring/` | Only the `liberty` role has Molecule tests. Add `molecule/default/` directories with full test lifecycle. |
| **Monitoring role is monolithic** | `roles/monitoring/tasks/main.yml` (430 lines) | Single file handles Prometheus, Node Exporter, Alertmanager, and Grafana. Split into: `prometheus.yml`, `node_exporter.yml`, `alertmanager.yml`, `grafana.yml`, `verify.yml` |
| **Idempotency issue** | `roles/common/tasks/main.yml:21-24` | Timezone task uses `command` with `changed_when: false`. Use `community.general.timezone` module instead. |
| **Missing meta/main.yml** | `roles/common/`, `roles/monitoring/` | Add Galaxy-compatible metadata with `galaxy_info` and dependencies. |
| **Inconsistent variable usage** | `roles/common/tasks/main.yml:9-18` | Packages hardcoded in tasks despite `common_packages` being defined in defaults. |
| **Missing requirements.yml** | `automated/ansible/` | No Galaxy requirements file for collections. Add one listing `community.general` and `ansible.posix`. |
| **Missing .ansible-lint** | Project root | No linting configuration present. |
| **Duplicate variables** | `inventory/prod-aws.yml` vs `group_vars/aws.yml` | Same variables defined in multiple places (liberty_version, liberty_install_dir, etc.). |

---

### CI/CD & Containers

| Issue | Location | Details |
|-------|----------|---------|
| **No integration tests stage** | `ci-cd/Jenkinsfile` (after line 198) | Pipeline has unit tests but lacks integration tests. Add stage using Testcontainers or contract testing. |
| **No semantic versioning** | `ci-cd/Jenkinsfile:113` | Image version is `${BUILD_NUMBER}-${GIT_COMMIT_SHORT}`. Implement `MAJOR.MINOR.PATCH` from VERSION file or git tags. |
| **No image signing** | `ci-cd/Jenkinsfile` (after Security Scan ~line 311) | Images scanned but not signed. Add Sigstore/Cosign for supply chain security (SLSA compliance). |
| **DRY violation** | `ci-cd/Jenkinsfile:358-428, 517-558, 582-657, 700-744, 858-906` | `aws_cli_with_retry()` function duplicated 5 times. Extract to `automated/scripts/lib/aws-retry.sh`. |
| **No SBOM generation** | `ci-cd/Jenkinsfile` (after Build Container) | Add Syft or Trivy SBOM generation: `trivy image --format spdx-json -o sbom.spdx.json` |
| **Agent images use latest** | `ci-cd/Jenkinsfile:14, 18, 26` | Pin to SHA digests for reproducible builds. |
| **No GitOps manifest generation** | `ci-cd/Jenkinsfile` | Pipeline deploys directly. Add stage to update K8s manifest image tags and commit to GitOps repo. |
| **No topology spread constraints** | `kubernetes/base/liberty-deployment.yaml:55-64` | Uses `podAntiAffinity` with preferred. Add `topologySpreadConstraints` for better zone distribution. |
| **No External Secrets example** | `kubernetes/base/kustomization.yaml:32-36` | Secrets commented out with note to use external secrets, but no example provided. |
| **No Ingress resource** | `kubernetes/base/` | Service is ClusterIP with no Ingress. Add Ingress with TLS and cert-manager annotations. |

---

### Java Application

| Issue | Location | Details |
|-------|----------|---------|
| **Flat package structure** | `sample-app/src/main/java/com/example/sample/` | All classes in flat structure. Reorganize into: `controller/`, `service/`, `dto/`, `exception/`, `config/` |
| **God class** | `SampleResource.java` (433 lines) | Handles 8 concerns. Split into: `GreetingController`, `SystemController`, `LoadTestController`, `StatisticsController` |
| **Missing Response DTOs** | `SampleResource.java:68-71, 108-111, 152-163, etc.` | All endpoints return `Map.of(...)`. Create typed DTOs: `GreetingResponse`, `SystemInfoResponse`, `EchoResponse` with OpenAPI annotations. |
| **No service layer** | `SampleResource.java:136-172, 327-351` | Business logic in controller. Extract to `SystemInfoService`, `ComputeService`. |
| **Generic package name** | `com.example.sample` | Rename to meaningful name: `com.middleware.loadtest` or `io.github.jconover.liberty` |
| **Missing integration tests** | `sample-app/src/test/java/` | Only unit tests exist. Add integration tests with REST Assured or Arquillian. |
| **Missing beans.xml** | `sample-app/src/main/webapp/WEB-INF/` | Add explicit CDI configuration file. |
| **Missing global exception handler** | `sample-app/.../exception/` | Only `ValidationExceptionMapper` exists. Add `GenericExceptionMapper` for 500 errors. |
| **No JaCoCo coverage** | `sample-app/pom.xml` | README mentions coverage but no plugin configured. Add JaCoCo plugin. |
| **EchoRequest missing annotations** | `sample-app/.../dto/EchoRequest.java:9-30` | No OpenAPI `@Schema` annotations despite using OpenAPI elsewhere. |
| **EchoRequest missing methods** | `sample-app/.../dto/EchoRequest.java` | Lacks `equals()`, `hashCode()`, `toString()`. Convert to Java 17 record. |
| **Missing mpOpenAPI feature** | `containers/liberty/server.xml` | OpenAPI annotations used but feature not in server.xml. Add `mpOpenAPI-3.1`. |

---

### Documentation & Structure

| Issue | Location | Details |
|-------|----------|---------|
| **No CHANGELOG.md** | Root | Add changelog following Keep a Changelog format with semantic versioning. |
| **No screenshots in README** | `README.md` | Add visual proof: Grafana dashboards, ECS console, Prometheus targets, deployment output. |
| **Missing SECURITY.md** | Root | Standard file for security policy and vulnerability reporting. |
| **CONTRIBUTING.md is minimal** | `CONTRIBUTING.md` (54 lines) | Expand with: issue/PR templates, commit conventions, dev setup, testing requirements. |
| **LICENSE year outdated** | `LICENSE:3` | Says "2024-2025", should be "2024-2026". |
| **Shell script issues** | `automated/scripts/` | Unquoted variables: `aws-start.sh:152` (`$INSTANCE_IDS`), `deploy.sh:87,90` (`$args`). Run shellcheck. |
| **Runbook URLs relative** | `monitoring/prometheus/rules/liberty-alerts.yml` | Use full GitHub URLs instead of relative paths. |
| **Missing infrastructure runbooks** | `monitoring/prometheus/rules/liberty-alerts.yml:41-57` | HighCPUUsage, HighMemoryUsage alerts have no runbook_url. Create runbooks. |
| **docs/README.md date** | `docs/README.md:226` | Shows "Last Updated: 2025-12-30" - update or remove. |
| **Temp files in repo** | `sample-app/.github/java-upgrade/` | Contains `20251222155438/plan.md` and `progress.md` - clean up or gitignore. |

---

## Medium Priority

### Terraform
- Inconsistent tagging strategy (two different tag sets in `locals.tf` vs `providers.tf`)
- Outputs scattered across files (`monitoring.tf:322-367`, `management.tf:519-543`) - consolidate to `outputs.tf`
- Missing `tls` provider version constraint in `providers.tf`
- Unused data source `aws_secretsmanager_secret.alertmanager_slack` in `monitoring.tf:56-59`
- Missing `point_in_time_recovery` on DynamoDB in `bootstrap/main.tf:93-106`

### Ansible
- Task naming inconsistency (mix of title case and sentence case)
- Unused defaults in `common` role (`common_nofile_soft/hard`, `common_configure_firewall`, etc. defined but not implemented)
- Missing `vars/main.yml` for role-internal constants (download URLs should not be overridable)
- Handler naming could use role prefix for uniqueness

### CI/CD & Containers
- No resource requests on Jenkins agent containers in Jenkinsfile (though Helm values has them)
- No Kyverno/Gatekeeper policy examples
- Prometheus annotations AND ServiceMonitor could cause duplicate scraping
- `server.xml` expected as ConfigMap mount but not in configMapGenerator

### Java Application
- 17 `@SuppressWarnings("unchecked")` in tests - creating DTOs would eliminate these
- Test method names could be more descriptive (Given-When-Then style)
- Minimal Javadoc - missing `@param`, `@return` tags
- Hardcoded strings: "Hello from Liberty!", magic numbers for validation limits

---

## Quick Wins

High impact, low effort items to tackle first:

| Item | Effort | Files |
|------|--------|-------|
| Add `CHANGELOG.md` | 30 min | New file |
| Add screenshots to README | 1 hour | `README.md` |
| Create `SECURITY.md` | 30 min | New file |
| Rename package from `com.example.sample` | 15 min | All Java files |
| Add JaCoCo plugin | 10 min | `pom.xml` |
| Add `.ansible-lint` and `requirements.yml` | 20 min | New files |
| Convert `EchoRequest` to Java 17 record | 10 min | `EchoRequest.java` |
| Update LICENSE year | 2 min | `LICENSE` |
| Add `mpOpenAPI-3.1` feature | 5 min | `server.xml` |
| Add `GenericExceptionMapper` | 15 min | New file |

---

## Already Excellent (Highlight These!)

These are portfolio-quality and should be emphasized:

### Terraform
- Comprehensive variable validation with clear error messages
- IMDSv2 enforcement, encrypted EBS, VPC flow logs
- Least-privilege IAM policies with detailed comments
- Secrets Manager integration with auto-generated passwords
- Cost estimation output in `outputs.tf`
- Provider default tags

### Ansible
- `no_log: true` on all sensitive tasks
- AES password encoding using Liberty's `securityUtility`
- Molecule tests on liberty role with full lifecycle (prepare, converge, verify)
- FQCNs throughout (`ansible.builtin.apt`)
- Retry logic on download tasks

### CI/CD & Containers
- Multi-stage container builds with proper layer caching (pom.xml before source)
- OCI-compliant image labels with build metadata
- Comprehensive security contexts (runAsNonRoot, readOnlyRootFilesystem, drop ALL capabilities, seccomp)
- Zero-trust NetworkPolicies with default-deny
- Trivy security scanning with checksum verification
- AWS CLI retry logic with exponential backoff and jitter
- PodDisruptionBudget, ResourceQuota, LimitRange
- HPA with sophisticated scaling behavior

### Documentation
- Excellent Architecture Decision Records (ADRs)
- Production-ready runbooks with escalation paths
- Mermaid diagrams for visual architecture
- Clear value proposition (7 hours → 28 minutes)
- Professional badges in README
- Comprehensive GETTING_STARTED.md (642 lines)

---

## Implementation Notes

When implementing these changes:

1. **Run tests after each major change** - especially after Java refactoring
2. **Terraform changes** - run `terraform plan` to verify no infrastructure drift
3. **Ansible changes** - run Molecule tests: `cd roles/liberty && molecule test`
4. **Container changes** - rebuild and test locally: `podman build -t liberty-app:test -f containers/liberty/Containerfile .`
5. **Java changes** - run full test suite: `cd sample-app && mvn clean verify`

---

*This document was generated by Claude Code on 2026-01-02. Use `/review` or ask Claude to implement specific items when ready.*
