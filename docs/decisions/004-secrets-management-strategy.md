# ADR-004: Secrets Management Strategy

## Status

Accepted

## Date

2024-12-31

## Context

The Middleware Automation Platform deploys Open Liberty application servers across multiple environments:

- **AWS Production**: ECS Fargate containers and/or EC2 instances with RDS PostgreSQL
- **Local Kubernetes**: 3-node Beelink homelab cluster for development
- **Local Podman**: Single-machine development environment

Each environment requires secure management of various credentials:

| Component | Credential Type | Environments |
|-----------|----------------|--------------|
| Database (RDS) | Connection credentials | AWS |
| Liberty | Keystore password, admin password | AWS (EC2), Local |
| Grafana | Admin password | AWS, Local K8s |
| AWX | Admin password | AWS, Local K8s |
| Jenkins | Admin password | AWS, Local K8s |

The platform must:

1. **Never store plaintext credentials** in version control or configuration files
2. **Support credential rotation** without redeploying infrastructure
3. **Provide secure access** for both automated deployments and manual retrieval
4. **Handle environment-specific requirements** (cloud vs. on-premises)
5. **Meet security audit requirements** for enterprise deployments

## Decision

We adopt a **hybrid secrets management strategy** using environment-appropriate tools:

### 1. AWS Secrets Manager for Cloud Resources

All AWS-native credentials use Secrets Manager with auto-generation:

```hcl
# Database credentials (database.tf)
resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name = "${local.name_prefix}/database/credentials"
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    host     = aws_db_instance.main.address
    port     = 5432
    dbname   = var.db_name
  })
}
```

**Secrets stored in AWS Secrets Manager:**

| Secret Path | Contents | Auto-Generated |
|-------------|----------|----------------|
| `mw-prod/database/credentials` | DB username, password, host, port | Yes |
| `mw-prod/monitoring/grafana-credentials` | Grafana admin user/password | Yes |

### 2. Ansible Vault for Liberty Application Credentials

Liberty server credentials are encrypted using Ansible Vault and transformed at deployment time using Liberty's `securityUtility`:

**Storage (vault.yml):**
```yaml
liberty_keystore_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  [encrypted content]

liberty_admin_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  [encrypted content]
```

**Runtime Encoding (encode-passwords.yml):**
```yaml
- name: Encode keystore password using Liberty securityUtility
  ansible.builtin.command:
    cmd: "{{ liberty_install_dir }}/bin/securityUtility encode --encoding=aes {{ liberty_keystore_password }}"
  register: encoded_keystore_result
  no_log: true

- name: Set encoded keystore password fact
  ansible.builtin.set_fact:
    liberty_keystore_password_encoded: "{{ encoded_keystore_result.stdout | trim }}"
  no_log: true
```

**Result in server.xml:**
```xml
<keyStore password="{aes}AJk3N2f8k..." />
```

This two-stage approach ensures:
- Source passwords are encrypted at rest (Ansible Vault)
- Runtime passwords are AES-encoded for Liberty consumption
- No plaintext passwords exist in configuration files on target servers
- Credential exposure is prevented via `no_log: true` on all sensitive tasks

### 3. Kubernetes Secrets for Local Deployments

Local Kubernetes deployments use native K8s secrets:

```bash
# AWX admin password
kubectl create secret generic awx-admin-password \
  --namespace=awx \
  --from-literal=password='SECURE_PASSWORD'

# Jenkins admin password
kubectl create secret generic jenkins-admin-secret \
  --namespace=jenkins \
  --from-literal=jenkins-admin-password='SECURE_PASSWORD'
```

The `setup-local-env.sh` script supports:
- Manual password provision via environment variables
- Auto-generation with `--generate-passwords` flag
- Secure storage to `~/.local-env-credentials` (mode 600)

### 4. Password Requirements and Validation

Minimum security requirements enforced by playbooks:

| Variable | Min Length | Forbidden Values |
|----------|-----------|------------------|
| `liberty_keystore_password` | 16 chars | changeit, password, changeme, liberty |
| `liberty_admin_password` | 12 chars | admin, password, changeme |
| `GRAFANA_ADMIN_PASSWORD` | 8 chars | - |
| `JENKINS_ADMIN_PASSWORD` | 8 chars | - |

## Consequences

### Positive

1. **No hardcoded credentials**: All secrets are externalized and environment-specific
2. **Audit compliance**: AES-encoded passwords in Liberty config files satisfy security audits
3. **Credential rotation**: Each tool supports rotation without full redeployment
   - AWS: Update secret value, restart services
   - Ansible Vault: Re-encrypt, run playbook with `--tags liberty`
   - K8s: Delete/recreate secret, rollout restart
4. **Automation-friendly**: Terraform auto-generates AWS credentials; scripts can auto-generate local credentials
5. **Defense in depth**: Multiple encryption layers (vault encryption + runtime encoding)
6. **Log safety**: `no_log: true` prevents credential exposure in Ansible output

### Negative

1. **Tool complexity**: Three different secrets management approaches require understanding multiple tools
2. **Operational overhead**: Credential rotation procedures differ by environment
3. **Vault password management**: Ansible Vault requires secure storage of the vault password itself
4. **Local credential persistence**: `~/.local-env-credentials` file could be overlooked during cleanup
5. **No centralized secret store**: Unlike HashiCorp Vault, secrets are distributed across tools

### Mitigations

| Risk | Mitigation |
|------|------------|
| Vault password exposure | Store in password manager; use `--ask-vault-pass` in interactive sessions |
| Local credential file forgotten | Document cleanup steps; add to `.gitignore` |
| Inconsistent rotation procedures | Comprehensive rotation guide in `CREDENTIAL_SETUP.md` |

## Alternatives Considered

### 1. HashiCorp Vault

**Pros:**
- Unified secrets management across all environments
- Dynamic secret generation
- Fine-grained access policies
- Audit logging

**Cons:**
- Additional infrastructure to deploy and maintain
- Overkill for current scale (< 10 services)
- Requires high availability setup for production reliability
- Learning curve for operations team

**Decision:** Not adopted. The added operational complexity does not justify the benefits at current scale. Can be revisited if the platform grows significantly.

### 2. AWS SSM Parameter Store Only

**Pros:**
- Simpler than Secrets Manager (no rotation overhead)
- Lower cost for string parameters
- Native AWS integration

**Cons:**
- No automatic rotation support
- 10,000 parameter limit per account
- Less suitable for complex JSON credentials
- Does not solve local/on-premises requirements

**Decision:** Not adopted. Secrets Manager provides better features for database credentials and integrates cleanly with RDS. Parameter Store could supplement for non-sensitive configuration.

### 3. SOPS (Secrets OPerationS) with Git

**Pros:**
- Secrets stored in version control (encrypted)
- Supports AWS KMS, GCP KMS, PGP
- GitOps-friendly workflow

**Cons:**
- Requires KMS setup and key management
- Secrets in git history (encrypted but present)
- Additional tooling in CI/CD pipelines

**Decision:** Not adopted. Ansible Vault provides similar functionality with simpler setup and is already integrated with our deployment tooling.

### 4. External Secrets Operator (for Kubernetes)

**Pros:**
- Syncs external secrets (AWS, Vault, etc.) to K8s secrets
- Single source of truth
- Automatic refresh

**Cons:**
- Only benefits Kubernetes environments
- Requires operator installation and maintenance
- Does not help with EC2/Ansible deployments

**Decision:** Could be adopted as an enhancement for local K8s deployments to sync from AWS Secrets Manager, but not a replacement for the overall strategy.

## Implementation Files

| File | Purpose |
|------|---------|
| `automated/terraform/environments/prod-aws/database.tf` | RDS credentials in Secrets Manager |
| `automated/terraform/environments/prod-aws/monitoring.tf` | Grafana credentials in Secrets Manager |
| `automated/ansible/roles/liberty/tasks/encode-passwords.yml` | Liberty password AES encoding |
| `automated/ansible/inventory/group_vars/all/vault.yml` | Ansible Vault encrypted credentials |
| `local-setup/setup-local-env.sh` | Local K8s credential generation |
| `docs/CREDENTIAL_SETUP.md` | Complete credential configuration guide |

## References

- [AWS Secrets Manager Documentation](https://docs.aws.amazon.com/secretsmanager/)
- [Ansible Vault Documentation](https://docs.ansible.com/ansible/latest/vault_guide/)
- [Liberty Security Utility](https://openliberty.io/docs/latest/reference/command/securityUtility-encode.html)
- [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
