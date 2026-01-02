# Contributing to Enterprise Middleware Automation Platform

Thank you for your interest in contributing to the Enterprise Middleware Automation Platform. This document provides guidelines and best practices for contributing to the project. We welcome contributions of all kinds: bug fixes, new features, documentation improvements, and more.

## Table of Contents

1. [Code of Conduct](#code-of-conduct)
2. [Getting Started](#getting-started)
3. [Development Environment Setup](#development-environment-setup)
4. [Code Style Guidelines](#code-style-guidelines)
5. [Commit Message Conventions](#commit-message-conventions)
6. [Pull Request Process](#pull-request-process)
7. [Testing Requirements](#testing-requirements)
8. [Issue Reporting Guidelines](#issue-reporting-guidelines)
9. [Code Review Process](#code-review-process)
10. [AI-Assisted Development](#ai-assisted-development)
11. [Getting Help](#getting-help)

---

## Code of Conduct

This project adheres to a Code of Conduct that all contributors are expected to follow. Please read [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) before contributing.

---

## Getting Started

### Quick Contribution Workflow

1. **Fork** the repository to your GitHub account
2. **Clone** your fork locally:
   ```bash
   git clone https://github.com/<your-username>/middleware-automation-platform.git
   cd middleware-automation-platform
   ```
3. **Add upstream remote** to stay synchronized:
   ```bash
   git remote add upstream https://github.com/<org>/middleware-automation-platform.git
   ```
4. **Create a feature branch** from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```
5. **Make your changes** following the guidelines in this document
6. **Test your changes** locally (see [Testing Requirements](#testing-requirements))
7. **Commit** with a descriptive message following our conventions
8. **Push** to your fork and **open a Pull Request**

### Types of Contributions

We welcome the following types of contributions:

| Type | Description | Branch Prefix |
|------|-------------|---------------|
| Features | New functionality or capabilities | `feature/` |
| Bug Fixes | Corrections to existing functionality | `fix/` |
| Documentation | README updates, guides, runbooks | `docs/` |
| Refactoring | Code improvements without behavior changes | `refactor/` |
| Tests | New or improved test coverage | `test/` |
| Infrastructure | Terraform, Ansible, CI/CD changes | `infra/` |

---

## Development Environment Setup

### Prerequisites

Before contributing, ensure you have the required tools installed. See [docs/PREREQUISITES.md](docs/PREREQUISITES.md) for complete installation instructions.

#### Universal Requirements (All Contributions)

| Tool | Minimum Version | Purpose |
|------|-----------------|---------|
| Git | 2.30+ | Version control |
| Java | 17+ | Build sample application |
| Maven | 3.8+ | Build WAR file |

#### Infrastructure Contributions (Terraform/Ansible)

| Tool | Minimum Version | Purpose |
|------|-----------------|---------|
| Terraform | 1.5+ | Infrastructure as Code |
| Ansible | 2.14+ | Configuration management |
| AWS CLI | 2.0+ | AWS API interactions (for testing) |

#### Container Contributions

| Tool | Minimum Version | Purpose |
|------|-----------------|---------|
| Podman | 4.0+ | Container builds and testing |
| OR Docker | 20.10+ | Alternative container runtime |

#### Kubernetes Contributions

| Tool | Minimum Version | Purpose |
|------|-----------------|---------|
| kubectl | 1.25+ | Kubernetes CLI |
| Helm | 3.0+ | Package management |

### Cloning and Building

```bash
# Clone your fork
git clone https://github.com/<your-username>/middleware-automation-platform.git
cd middleware-automation-platform

# Build the sample application
mvn -f sample-app/pom.xml clean package

# Build the container image (from project root)
podman build -t liberty-app:dev -f containers/liberty/Containerfile .

# Run locally to verify
podman run -d -p 9080:9080 -p 9443:9443 --name liberty-dev liberty-app:dev

# Verify the application is running
curl http://localhost:9080/health/ready

# Clean up
podman rm -f liberty-dev
```

### Verification Script

Run the prerequisites check script to verify your environment:

```bash
# Check prerequisites for your target area
# Usage: ./check-prerequisites.sh [all|podman|kubernetes|aws]

# Example: Check all prerequisites
./check-prerequisites.sh all
```

---

## Code Style Guidelines

Maintaining consistent code style improves readability and reduces merge conflicts. Follow these guidelines for each technology in the project.

### Terraform

Our Terraform code follows HashiCorp's best practices. Reference existing modules in `automated/terraform/` for patterns.

- **Formatting**: Run `terraform fmt` before committing (required)
- **Validation**: Run `terraform validate` to check syntax
- **Naming**: Use `snake_case` for resources, variables, and outputs
- **Variables**: Include `description` for all variables and outputs
- **Tags**: All AWS resources must include standard tags:
  ```hcl
  tags = {
    Environment = var.environment
    Project     = var.project
    ManagedBy   = "terraform"
  }
  ```
- **Security**: Follow least-privilege IAM principles; no `0.0.0.0/0` ingress without justification

Example:
```hcl
variable "instance_type" {
  description = "EC2 instance type for Liberty servers"
  type        = string
  default     = "t3.medium"
}

resource "aws_instance" "liberty" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  tags = {
    Name        = "${var.project}-liberty-${count.index + 1}"
    Environment = var.environment
    Project     = var.project
    ManagedBy   = "terraform"
  }
}
```

### Ansible

Our Ansible code uses the production profile. See `.ansible-lint` in `automated/ansible/` for the complete configuration.

- **Linting**: Run `ansible-lint` before committing (required)
- **FQCNs**: Use fully qualified collection names:
  ```yaml
  # Good
  - ansible.builtin.template:

  # Avoid
  - template:
  ```
- **Naming**: Variables use `snake_case` pattern: `^[a-z_][a-z0-9_]*$`
- **Task Names**: Use descriptive names with role prefix: `liberty | Configure server.xml`
- **Secrets**: Include `no_log: true` for tasks handling sensitive data
- **Idempotency**: All tasks must be idempotent (running twice produces same result)

Example:
```yaml
- name: liberty | Deploy server configuration
  ansible.builtin.template:
    src: server.xml.j2
    dest: "{{ liberty_home }}/usr/servers/{{ liberty_server_name }}/server.xml"
    owner: "{{ liberty_user }}"
    group: "{{ liberty_group }}"
    mode: "0640"
  notify: restart liberty
```

### Containers (Dockerfile/Containerfile)

- **Multi-stage builds**: Separate build and runtime stages to minimize image size
- **Non-root user**: Run containers as non-root for security
- **Health checks**: Include HEALTHCHECK instructions
- **Labels**: Add metadata labels (maintainer, version, description)
- **Layer optimization**: Order instructions to maximize cache usage

Example pattern from `containers/liberty/Containerfile`:
```dockerfile
# Build stage
FROM maven:3.9-eclipse-temurin-17 AS builder
WORKDIR /build
COPY sample-app/pom.xml .
RUN mvn dependency:go-offline
COPY sample-app/src ./src
RUN mvn package -DskipTests

# Runtime stage
FROM icr.io/appcafe/open-liberty:kernel-slim-java17-openj9-ubi
USER 1001
COPY --from=builder /build/target/*.war /config/dropins/
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s \
  CMD curl -f http://localhost:9080/health/ready || exit 1
```

### Kubernetes Manifests

- **API Versions**: Use stable API versions when available
- **Resource Limits**: Always specify CPU and memory limits
- **Health Probes**: Include readiness and liveness probes
- **Labels**: Use standard Kubernetes labels for selection and organization
- **Namespaces**: Deploy to appropriate namespaces, not `default`

### Java/Maven

- **Code Style**: Follow standard Java conventions
- **Dependencies**: Keep dependencies minimal and up-to-date
- **Testing**: Include unit tests for new functionality

### Shell Scripts

- **Shebang**: Use `#!/bin/bash` or `#!/usr/bin/env bash`
- **Error Handling**: Use `set -e` and handle errors appropriately
- **Quoting**: Quote variables to prevent word splitting
- **Dry-run**: Support `--dry-run` flag for destructive operations

---

## Commit Message Conventions

We follow the [Conventional Commits](https://www.conventionalcommits.org/) specification for clear, structured commit history.

### Format

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

### Types

| Type | Description |
|------|-------------|
| `feat` | New feature or functionality |
| `fix` | Bug fix |
| `docs` | Documentation changes only |
| `style` | Code style changes (formatting, no logic changes) |
| `refactor` | Code changes that neither fix bugs nor add features |
| `perf` | Performance improvements |
| `test` | Adding or updating tests |
| `build` | Build system or dependency changes |
| `ci` | CI/CD pipeline changes |
| `chore` | Maintenance tasks (updating dependencies, etc.) |

### Scopes

Use the component or area being changed:

| Scope | Description |
|-------|-------------|
| `terraform` | Infrastructure as Code changes |
| `ansible` | Configuration management changes |
| `ecs` | ECS-specific changes |
| `ec2` | EC2-specific changes |
| `k8s` | Kubernetes manifest changes |
| `liberty` | Open Liberty configuration |
| `container` | Containerfile/image changes |
| `ci` | GitHub Actions/Jenkins changes |
| `docs` | Documentation |
| `monitoring` | Prometheus/Grafana changes |

### Examples

```bash
# Feature
feat(ecs): add auto-scaling based on request count

# Bug fix
fix(terraform): correct security group ingress rule for ALB

# Documentation
docs(readme): update deployment instructions for ECS

# Refactoring
refactor(ansible): consolidate Liberty configuration tasks

# Breaking change (use ! after type)
feat(terraform)!: migrate from EC2 to ECS Fargate by default

BREAKING CHANGE: Default compute platform changed from EC2 to ECS.
Set ecs_enabled=false for EC2 deployments.
```

### Rules

1. **Subject line**: Maximum 72 characters, imperative mood ("add" not "added")
2. **Body**: Explain *what* and *why*, not *how* (code shows how)
3. **Footer**: Reference issues with `Fixes #123` or `Closes #456`
4. **Breaking changes**: Use `!` and include `BREAKING CHANGE:` footer

---

## Pull Request Process

### Before Opening a PR

1. **Sync with upstream**: Ensure your branch is up-to-date with `main`
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

2. **Run all relevant tests** (see [Testing Requirements](#testing-requirements))

3. **Self-review your changes**:
   - Code follows style guidelines
   - No secrets or credentials committed
   - Documentation updated if needed
   - Commit messages follow conventions

### PR Requirements

Every pull request must include:

| Requirement | Description |
|-------------|-------------|
| **Clear Title** | Follows commit message format: `type(scope): description` |
| **Description** | Explains what changes were made and why |
| **Testing Evidence** | Describes how changes were tested |
| **Documentation** | Updates to relevant docs if behavior changed |
| **Clean History** | Logical, atomic commits (squash if needed) |

### PR Template

When opening a PR, include:

```markdown
## Summary
Brief description of changes and motivation.

## Changes Made
- Change 1
- Change 2
- Change 3

## Testing Performed
- [ ] Ran `terraform fmt` and `terraform validate`
- [ ] Ran `ansible-lint`
- [ ] Tested locally with Podman
- [ ] Tested in development environment
- [ ] Updated documentation

## Related Issues
Fixes #<issue-number>

## Checklist
- [ ] My code follows the project's style guidelines
- [ ] I have performed a self-review of my changes
- [ ] I have added tests that prove my fix/feature works
- [ ] I have updated the documentation accordingly
- [ ] My changes generate no new warnings
```

### Review Timeline

- PRs are typically reviewed within 2-3 business days
- Complex changes may require additional review time
- Address review feedback promptly to keep PRs moving

---

## Testing Requirements

All contributions must be tested before submitting a PR. The testing requirements depend on the type of change.

### Terraform Changes

```bash
cd automated/terraform/environments/prod-aws

# Required: Format check
terraform fmt -check -recursive

# Required: Validation
terraform init -backend=false
terraform validate

# Required: Plan (verify no unexpected changes)
terraform plan

# Recommended: Security scan
# Install: pip install checkov
checkov -d .
```

### Ansible Changes

```bash
cd automated/ansible

# Required: Lint check
ansible-lint

# Required: Syntax check
ansible-playbook --syntax-check playbooks/site.yml

# Recommended: Dry run against test inventory
ansible-playbook -i inventory/dev.yml playbooks/site.yml --check
```

### Container Changes

```bash
# Required: Build succeeds
podman build -t liberty-app:test -f containers/liberty/Containerfile .

# Required: Container runs and passes health checks
podman run -d --name liberty-test -p 9080:9080 liberty-app:test
sleep 30
curl -f http://localhost:9080/health/ready
podman rm -f liberty-test
```

### Kubernetes Changes

```bash
# Required: YAML validation
kubectl apply --dry-run=client -f kubernetes/base/

# Recommended: Deploy to test cluster
kubectl apply -f kubernetes/base/
kubectl wait --for=condition=ready pod -l app=liberty --timeout=120s
```

### Sample Application Changes

```bash
cd sample-app

# Required: Build succeeds
mvn clean package

# Required: Tests pass
mvn test
```

### End-to-End Testing

For significant changes, follow the complete testing guide:
[docs/END_TO_END_TESTING.md](docs/END_TO_END_TESTING.md)

---

## Issue Reporting Guidelines

Good issue reports help us understand and resolve problems quickly.

### Before Opening an Issue

1. **Search existing issues** to avoid duplicates
2. **Check documentation** for known solutions
3. **Test with latest version** from `main` branch

### Bug Reports

Use this template for bug reports:

```markdown
## Bug Description
A clear description of what the bug is.

## Environment
- OS: [e.g., Ubuntu 22.04]
- Tool versions:
  - Terraform: [e.g., 1.7.0]
  - Ansible: [e.g., 2.16.0]
  - Podman/Docker: [e.g., 4.9.0]
- Deployment target: [e.g., AWS ECS, Local Kubernetes]

## Steps to Reproduce
1. Run command '...'
2. Configure setting '...'
3. Observe error

## Expected Behavior
What you expected to happen.

## Actual Behavior
What actually happened.

## Error Output
```
Paste relevant error messages, logs, or terraform plan output
```

## Additional Context
Any other context about the problem.
```

### Feature Requests

Use this template for feature requests:

```markdown
## Feature Description
A clear description of the feature you'd like.

## Use Case
Explain the problem this feature would solve.

## Proposed Solution
Your idea for how this could be implemented.

## Alternatives Considered
Other solutions you've considered.

## Additional Context
Any other context, mockups, or examples.
```

### Issue Labels

We use labels to categorize issues:

| Label | Description |
|-------|-------------|
| `bug` | Something isn't working |
| `enhancement` | New feature or improvement |
| `documentation` | Documentation improvements |
| `good first issue` | Good for newcomers |
| `help wanted` | Extra attention needed |
| `question` | Further information requested |
| `terraform` | Terraform-related |
| `ansible` | Ansible-related |
| `kubernetes` | Kubernetes-related |

---

## Code Review Process

All contributions go through code review to ensure quality and consistency.

### What Reviewers Look For

| Category | Checklist |
|----------|-----------|
| **Correctness** | Does the code do what it's supposed to? |
| **Security** | No secrets, least-privilege IAM, secure defaults |
| **Style** | Follows project conventions and patterns |
| **Testing** | Adequate test coverage and evidence |
| **Documentation** | Clear comments, updated docs |
| **Maintainability** | Code is readable and maintainable |
| **Performance** | No unnecessary resource usage |

### Review Feedback

Reviewers may leave different types of comments:

| Prefix | Meaning |
|--------|---------|
| `blocking:` | Must be addressed before merge |
| `suggestion:` | Recommended but not required |
| `question:` | Seeking clarification |
| `nitpick:` | Minor style preference |
| `praise:` | Positive feedback |

### Responding to Reviews

1. **Address all blocking comments** before requesting re-review
2. **Respond to each comment** (even if just to acknowledge)
3. **Push fixes as new commits** (don't force-push during review)
4. **Request re-review** when ready

### Approval Requirements

- At least **1 approval** required for most changes
- **2 approvals** required for:
  - Security-sensitive changes (IAM, secrets, networking)
  - Breaking changes
  - Production infrastructure changes

---

## AI-Assisted Development

This repository may use AI-assisted tooling for scaffolding, code generation, and documentation.

### Guidelines for AI-Generated Code

All AI-generated contributions must:

1. **Be reviewed by a human** before submission
2. **Follow all project standards** documented here
3. **Include proper attribution** if substantial portions are AI-generated
4. **Pass all automated checks** (linting, validation, tests)

### Technical Requirements

AI-generated infrastructure code must adhere to:

- Terraform AWS Provider v5+
- Least-privilege IAM policies
- Idempotent operations
- Explicit region configuration
- Cost-aware defaults (right-sized instances, lifecycle policies)
- Security best practices (encryption, network isolation)

### Review Expectations

AI-generated output receives the same scrutiny as human-written code. Reviewers will verify:

- Correctness and appropriateness for the use case
- Security implications fully understood
- No hallucinated resources or configurations
- Proper error handling

---

## Getting Help

If you need help with your contribution:

1. **Check existing documentation** in the `docs/` directory
2. **Review similar PRs** for examples and patterns
3. **Open a discussion** for questions about approach
4. **Ask in PR comments** for implementation guidance

### Key Documentation

| Document | Purpose |
|----------|---------|
| [README.md](README.md) | Project overview and quick start |
| [CLAUDE.md](CLAUDE.md) | AI assistant guidance and architecture |
| [docs/PREREQUISITES.md](docs/PREREQUISITES.md) | Development environment setup |
| [docs/END_TO_END_TESTING.md](docs/END_TO_END_TESTING.md) | Complete testing guide |
| [docs/CREDENTIAL_SETUP.md](docs/CREDENTIAL_SETUP.md) | Credential configuration |

---

Thank you for contributing to the Enterprise Middleware Automation Platform. Your contributions help improve middleware deployment automation for everyone.
