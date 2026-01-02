# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) that document significant technical decisions made in the Middleware Automation Platform.

## What are ADRs?

Architecture Decision Records are short text documents that capture important architectural decisions along with their context and consequences. They provide a decision log that helps current and future team members understand why certain technical choices were made.

## ADR Format

Each ADR follows this structure:

- **Title**: Short descriptive name
- **Status**: Proposed | Accepted | Deprecated | Superseded
- **Context**: The forces at play and the problem being addressed
- **Decision**: What we decided to do
- **Consequences**: The positive and negative outcomes of this decision
- **Alternatives Considered**: Other options that were evaluated

## Index of ADRs

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| [001](001-dual-compute-model.md) | Dual Compute Model (ECS Fargate and EC2) | Accepted | 2025-01 |
| [002](002-hybrid-deployment-architecture.md) | Hybrid Deployment Architecture | Accepted | 2025-01 |
| [003](003-prometheus-file-based-discovery.md) | Prometheus File-Based Discovery for ECS | Accepted | 2025-01 |
| [004](004-secrets-management-strategy.md) | Secrets Management Strategy | Accepted | 2024-12 |
| [005](005-container-base-image-strategy.md) | Container Base Image Strategy | Accepted | 2026-01 |

## Adding New ADRs

When adding a new ADR:

1. Create a new file with the pattern `NNN-short-title.md`
2. Use the next sequential number
3. Follow the standard format above
4. Update this index file
5. Set status to "Proposed" initially, then "Accepted" after review

## Related Documentation

- [Architecture Overview](../architecture/HYBRID_ARCHITECTURE.md) - High-level system architecture
- [ECS Migration Plan](../plans/ecs-migration-plan.md) - Detailed ECS Fargate migration checklist
- [Credential Setup](../CREDENTIAL_SETUP.md) - Security and credential configuration
