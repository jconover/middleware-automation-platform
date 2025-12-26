# Credential Setup Guide

This guide documents all credentials that **must be configured** before deploying the Middleware Automation Platform. Hardcoded default credentials have been removed for security - you must explicitly set all credentials.

## Overview

| Component | Credential Type | Storage Method |
|-----------|----------------|----------------|
| Grafana | Admin password | AWS Secrets Manager (auto-generated) |
| AWX | Admin password | Kubernetes Secret |
| Jenkins (K8s) | Admin password | Kubernetes Secret |
| Jenkins (AWS) | Admin password | Environment Variable |
| Liberty | Keystore password | Ansible Vault |
| Liberty | Admin credentials | Ansible Vault |

---

## 1. AWS Production Deployment

### 1.1 Grafana Credentials (Automatic)

Grafana credentials are **automatically generated** by Terraform and stored in AWS Secrets Manager.

**Retrieve the password after deployment:**
```bash
cd automated/terraform/environments/prod-aws

# Get the command to retrieve the password
terraform output grafana_admin_password_command

# Or directly:
aws secretsmanager get-secret-value \
  --secret-id mw-prod/monitoring/grafana-credentials \
  --query SecretString --output text | jq -r .admin_password
```

- **Username:** `admin`
- **Password:** Retrieved from Secrets Manager (24-character random)

### 1.2 AWX Credentials

AWX requires a Kubernetes secret to be created **before** or **after** the AWX deployment.

**Create the secret:**
```bash
# SSH to management server
MGMT_IP=$(terraform output -raw management_public_ip)
ssh -i ~/.ssh/ansible_ed25519 ubuntu@$MGMT_IP

# Create the AWX admin password secret
kubectl create secret generic awx-admin-password \
  --namespace=awx \
  --from-literal=password='YOUR_SECURE_PASSWORD_HERE'
```

**Alternative: Use a generated password:**
```bash
# Generate a secure password
PASSWORD=$(openssl rand -base64 24)
echo "Save this password: $PASSWORD"

kubectl create secret generic awx-admin-password \
  --namespace=awx \
  --from-literal=password="$PASSWORD"
```

**Retrieve existing password:**
```bash
kubectl get secret awx-admin-password -n awx -o jsonpath='{.data.password}' | base64 -d && echo
```

- **Username:** `admin`
- **Password:** From the secret you created

### 1.3 Management Server Access

Set your public IP in `terraform.tfvars` before deployment:

```bash
# Get your current public IP
curl -s ifconfig.me

# Edit terraform.tfvars
cd automated/terraform/environments/prod-aws
```

```hcl
# terraform.tfvars
management_allowed_cidrs = ["YOUR_PUBLIC_IP/32"]  # e.g., ["203.0.113.50/32"]
```

---

## 2. Liberty Server Credentials (Ansible)

Liberty deployments require credentials stored in **Ansible Vault**.

### 2.1 Create Vault-Encrypted Credentials

```bash
cd automated/ansible

# Create a vault password file (or use --ask-vault-pass)
echo 'your-vault-password' > .vault_pass
chmod 600 .vault_pass

# Generate encrypted values
ansible-vault encrypt_string 'YourSecureKeystorePassword123!' \
  --vault-password-file .vault_pass \
  --name 'liberty_keystore_password'

ansible-vault encrypt_string 'YourSecureAdminPassword!' \
  --vault-password-file .vault_pass \
  --name 'liberty_admin_password'

ansible-vault encrypt_string 'libertyadmin' \
  --vault-password-file .vault_pass \
  --name 'liberty_admin_user'
```

### 2.2 Add to Inventory

Create or edit `automated/ansible/inventory/group_vars/all/vault.yml`:

```yaml
# automated/ansible/inventory/group_vars/all/vault.yml
# This file should be encrypted with ansible-vault

liberty_keystore_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  [... encrypted content from step above ...]

liberty_admin_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  [... encrypted content from step above ...]

liberty_admin_user: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  [... encrypted content from step above ...]
```

### 2.3 Run Playbooks with Vault

```bash
# Using vault password file
ansible-playbook -i inventory/prod-aws.yml playbooks/site.yml \
  --vault-password-file .vault_pass

# Or prompt for password
ansible-playbook -i inventory/prod-aws.yml playbooks/site.yml \
  --ask-vault-pass
```

### 2.4 Password Requirements

| Variable | Minimum Length | Notes |
|----------|---------------|-------|
| `liberty_keystore_password` | 16 characters | Cannot be: changeit, password, changeme, liberty |
| `liberty_admin_password` | 12 characters | Cannot be: admin, password, changeme |
| `liberty_admin_user` | - | Cannot be empty |

---

## 3. Jenkins Credentials

### 3.1 Kubernetes Deployment (Local/Helm)

Create the Kubernetes secret **before** installing Jenkins:

```bash
# Create namespace if needed
kubectl create namespace jenkins

# Create the admin password secret
kubectl create secret generic jenkins-admin-secret \
  --namespace jenkins \
  --from-literal=jenkins-admin-password='YOUR_SECURE_PASSWORD'
```

The Helm values reference this secret:
```yaml
# ci-cd/jenkins/kubernetes/values.yaml
controller:
  adminUser: "admin"
  admin:
    existingSecret: "jenkins-admin-secret"
    passwordKey: "jenkins-admin-password"
```

### 3.2 AWS Deployment (EC2/Ansible)

Set the password via environment variable **before** running the playbook:

```bash
# Set the environment variable
export JENKINS_ADMIN_PASSWORD='YOUR_SECURE_PASSWORD'

# Run the playbook
ansible-playbook ci-cd/jenkins/aws/jenkins-install.yml
```

The playbook will fail with a clear error if `JENKINS_ADMIN_PASSWORD` is not set.

---

## 4. Database Credentials

Database credentials are **automatically generated** by Terraform and stored in AWS Secrets Manager.

**Retrieve credentials:**
```bash
aws secretsmanager get-secret-value \
  --secret-id mw-prod/database/credentials \
  --query SecretString --output text | jq .
```

The Liberty servers automatically retrieve these credentials at deployment time.

---

## 5. Pre-Deployment Checklist

Before running `terraform apply`:

- [ ] Set `management_allowed_cidrs` in `terraform.tfvars` to your IP
- [ ] Prepare AWX admin password (will create secret after management server deploys)

Before running Ansible playbooks:

- [ ] Create `vault.yml` with encrypted Liberty credentials
- [ ] Test vault decryption: `ansible-vault view inventory/group_vars/all/vault.yml`

Before deploying Jenkins (Kubernetes):

- [ ] Create `jenkins-admin-secret` in the jenkins namespace

Before deploying Jenkins (AWS):

- [ ] Set `JENKINS_ADMIN_PASSWORD` environment variable

---

## 6. Credential Rotation

### Rotate Grafana Password

```bash
# Generate new password
NEW_PASS=$(openssl rand -base64 24)

# Update in Secrets Manager
aws secretsmanager update-secret \
  --secret-id mw-prod/monitoring/grafana-credentials \
  --secret-string "{\"admin_user\":\"admin\",\"admin_password\":\"$NEW_PASS\"}"

# Restart Grafana to pick up new password
ssh ubuntu@$MONITORING_IP 'sudo systemctl restart grafana-server'
```

### Rotate AWX Password

```bash
# SSH to management server
ssh -i ~/.ssh/ansible_ed25519 ubuntu@$MGMT_IP

# Delete and recreate secret
kubectl delete secret awx-admin-password -n awx
kubectl create secret generic awx-admin-password \
  --namespace=awx \
  --from-literal=password='NEW_SECURE_PASSWORD'

# Restart AWX
kubectl rollout restart deployment awx -n awx
```

### Rotate Liberty Credentials

```bash
# Re-encrypt with new passwords
ansible-vault encrypt_string 'NewKeystorePassword!' \
  --vault-password-file .vault_pass \
  --name 'liberty_keystore_password'

# Update vault.yml and re-run playbook
ansible-playbook -i inventory/prod-aws.yml playbooks/site.yml \
  --vault-password-file .vault_pass --tags liberty
```

---

## 7. Troubleshooting

### "liberty_keystore_password must be defined"

The Ansible playbook requires Liberty credentials. Create them in Ansible Vault:

```bash
ansible-vault encrypt_string 'YourPassword123!' --name 'liberty_keystore_password'
```

### "JENKINS_ADMIN_PASSWORD environment variable must be set"

Export the environment variable before running the playbook:

```bash
export JENKINS_ADMIN_PASSWORD='YourSecurePassword'
```

### "Error: secret awx-admin-password not found"

Create the AWX secret on the management server:

```bash
kubectl create secret generic awx-admin-password \
  --namespace=awx \
  --from-literal=password='YourPassword'
```

### Cannot access Grafana

Retrieve the auto-generated password from Secrets Manager:

```bash
aws secretsmanager get-secret-value \
  --secret-id mw-prod/monitoring/grafana-credentials \
  --query SecretString --output text | jq -r .admin_password
```
