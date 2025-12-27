# Contributing

Thank you for your interest in contributing to the Enterprise Middleware Automation Platform.

## Getting Started

1. Fork the repository
2. Clone your fork locally
3. Create a feature branch: `git checkout -b feature/your-feature-name`
4. Make your changes
5. Test your changes locally
6. Commit with a descriptive message
7. Push to your fork and open a Pull Request

## Code Standards

### Terraform
- Use `terraform fmt` before committing
- Run `terraform validate` to check syntax
- Include descriptions for all variables and outputs
- Use consistent naming: `snake_case` for resources and variables
- Tag all resources appropriately

### Ansible
- Follow ansible-lint rules (see `.ansible-lint`)
- Use fully qualified collection names (e.g., `ansible.builtin.template`)
- Include `no_log: true` for tasks handling secrets
- Write idempotent tasks

### Containers
- Use multi-stage builds where applicable
- Run as non-root user
- Include health checks
- Minimize layer count and image size

## Pull Request Process

1. Ensure all tests pass
2. Update documentation if needed
3. Add a clear description of changes
4. Reference any related issues

## AI-Assisted Development

This repository may use AI-assisted tooling for scaffolding and documentation.
All changes must adhere to:
- Terraform AWS Provider v5+
- Least-privilege IAM
- Idempotent infrastructure changes
- Explicit region configuration
- Cost-aware defaults

Generated output must be reviewed and validated before merge.
