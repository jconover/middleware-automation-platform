# Secrets Management Guide

This document explains how secrets are managed in the middleware-automation-platform using External Secrets Operator (ESO) for unified secrets management across AWS and local Kubernetes environments.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [AWS Secrets Manager Integration](#aws-secrets-manager-integration)
- [Local Development Setup](#local-development-setup)
- [Adding New Secrets](#adding-new-secrets)
- [Secret Rotation](#secret-rotation)
- [Troubleshooting](#troubleshooting)
- [Security Best Practices](#security-best-practices)

## Overview

The platform uses **External Secrets Operator (ESO)** to synchronize secrets from external providers into Kubernetes Secrets. This approach provides:

- **Unified Management**: Single source of truth for secrets (AWS Secrets Manager or Vault)
- **Automatic Sync**: Secrets are automatically refreshed on a configurable interval
- **GitOps Compatible**: ExternalSecret manifests can be safely committed to Git
- **Audit Trail**: All secret access is logged in the external provider
- **Rotation Support**: Update secrets in the provider, ESO syncs automatically

### Secrets in This Platform

| Secret | Provider Key | Purpose |
|--------|-------------|---------|
| Database credentials | `mw-prod/database/credentials` | PostgreSQL username, password, host, port |
| Redis AUTH token | `mw-prod/redis/auth-token` | ElastiCache Redis authentication |
| Grafana admin | `mw-prod/monitoring/grafana-credentials` | Grafana admin username and password |

## Architecture

```
+------------------+      +-----------------------+      +------------------+
| AWS Secrets      | <--- | External Secrets      | ---> | Kubernetes       |
| Manager          |      | Operator              |      | Secrets          |
|                  |      |                       |      |                  |
| mw-prod/database |      | ClusterSecretStore    |      | liberty-secrets  |
| mw-prod/redis    |      | ExternalSecret        |      | grafana-admin    |
| mw-prod/grafana  |      | (refreshInterval: 1h) |      |                  |
+------------------+      +-----------------------+      +------------------+
                                   |
                                   v
                          +------------------+
                          | Applications     |
                          | (Liberty, etc.)  |
                          +------------------+
```

### How ESO Works

1. **ClusterSecretStore**: Defines how to connect to the external secrets provider (AWS Secrets Manager, Vault, etc.)
2. **ExternalSecret**: Specifies which secrets to fetch and how to map them to Kubernetes Secret keys
3. **ESO Controller**: Watches ExternalSecret resources and creates/updates Kubernetes Secrets
4. **Refresh Loop**: Periodically checks for updates and syncs changes

## AWS Secrets Manager Integration

### Prerequisites

1. **External Secrets Operator installed**:
   ```bash
   helm repo add external-secrets https://charts.external-secrets.io
   helm install external-secrets external-secrets/external-secrets \
       --namespace external-secrets \
       --create-namespace \
       -f kubernetes/base/external-secrets/helm-values.yaml
   ```

2. **IAM permissions configured** (choose one method):

#### Option A: IRSA (Recommended for EKS)

Create an IAM role with this policy:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret"
            ],
            "Resource": "arn:aws:secretsmanager:us-east-1:*:secret:mw-prod/*"
        }
    ]
}
```

Annotate the ESO service account:
```bash
kubectl annotate serviceaccount external-secrets \
    -n external-secrets \
    eks.amazonaws.com/role-arn=arn:aws:iam::ACCOUNT_ID:role/external-secrets-role
```

#### Option B: Access Keys (Non-EKS)

Create a secret with AWS credentials:
```bash
kubectl create secret generic aws-credentials \
    --namespace external-secrets \
    --from-literal=access-key=YOUR_ACCESS_KEY \
    --from-literal=secret-access-key=YOUR_SECRET_KEY
```

Then uncomment the `auth` section in `aws-clustersecretstore.yaml`.

### Setup Steps

1. **Apply the ClusterSecretStore**:
   ```bash
   kubectl apply -f kubernetes/base/external-secrets/aws-clustersecretstore.yaml
   ```

2. **Verify the store is ready**:
   ```bash
   kubectl get clustersecretstore aws-secrets-manager
   # Should show: READY: True
   ```

3. **Create the liberty namespace**:
   ```bash
   kubectl create namespace liberty
   ```

4. **Apply the ExternalSecrets**:
   ```bash
   kubectl apply -f kubernetes/base/secrets/liberty-secrets.yaml
   kubectl apply -f kubernetes/base/secrets/grafana-secrets.yaml
   ```

5. **Verify secrets are synced**:
   ```bash
   kubectl get externalsecret -n liberty
   kubectl get secret liberty-secrets -n liberty -o yaml
   ```

## Local Development Setup

For local Kubernetes clusters (homelab, minikube, kind) without AWS access, use the Kubernetes secrets backend.

### Setup Steps

1. **Create the source namespace**:
   ```bash
   kubectl create namespace secrets-source
   ```

2. **Create source secrets**:
   ```bash
   # Database credentials
   kubectl create secret generic liberty-db-credentials \
       --namespace secrets-source \
       --from-literal=password='local-dev-password' \
       --from-literal=username='liberty' \
       --from-literal=host='postgres.database.svc.cluster.local' \
       --from-literal=port='5432' \
       --from-literal=dbname='libertydb'

   # Redis credentials
   kubectl create secret generic liberty-redis-credentials \
       --namespace secrets-source \
       --from-literal=auth_token='local-redis-token' \
       --from-literal=host='redis.database.svc.cluster.local' \
       --from-literal=port='6379'

   # Grafana credentials
   kubectl create secret generic grafana-source-credentials \
       --namespace secrets-source \
       --from-literal=admin_user='admin' \
       --from-literal=admin_password='local-grafana-password'
   ```

3. **Apply the local ClusterSecretStore**:
   ```bash
   kubectl apply -f kubernetes/base/external-secrets/local-clustersecretstore.yaml
   ```

4. **Update ExternalSecrets to use local store**:

   Edit `kubernetes/base/secrets/liberty-secrets.yaml` and change:
   ```yaml
   secretStoreRef:
     name: kubernetes-secrets  # Changed from aws-secrets-manager
     kind: ClusterSecretStore
   ```

5. **Apply ExternalSecrets**:
   ```bash
   kubectl apply -f kubernetes/base/secrets/
   ```

### Alternative: Direct Secret Creation

For quick local testing without ESO:

```bash
kubectl create secret generic liberty-secrets \
    --namespace liberty \
    --from-literal=db.password='devpassword123' \
    --from-literal=db.username='liberty' \
    --from-literal=db.host='postgres.database.svc.cluster.local' \
    --from-literal=db.port='5432' \
    --from-literal=db.name='libertydb' \
    --from-literal=redis.auth='redis-auth-token' \
    --from-literal=redis.host='redis.database.svc.cluster.local' \
    --from-literal=redis.port='6379'
```

## Adding New Secrets

### Step 1: Create Secret in AWS Secrets Manager

Using AWS CLI:
```bash
aws secretsmanager create-secret \
    --name mw-prod/myapp/new-secret \
    --secret-string '{"api_key":"secret-value","api_secret":"another-secret"}'
```

Or using Terraform (add to `database.tf` or create new file):
```hcl
resource "aws_secretsmanager_secret" "myapp" {
  name        = "${local.name_prefix}/myapp/credentials"
  description = "MyApp API credentials"
}

resource "aws_secretsmanager_secret_version" "myapp" {
  secret_id     = aws_secretsmanager_secret.myapp.id
  secret_string = jsonencode({
    api_key    = var.myapp_api_key
    api_secret = random_password.myapp.result
  })
}
```

### Step 2: Create ExternalSecret

Create a new file `kubernetes/base/secrets/myapp-secrets.yaml`:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: myapp-secrets
  namespace: myapp
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: myapp-secrets
    creationPolicy: Owner
  data:
    - secretKey: api-key
      remoteRef:
        key: mw-prod/myapp/new-secret
        property: api_key
    - secretKey: api-secret
      remoteRef:
        key: mw-prod/myapp/new-secret
        property: api_secret
```

### Step 3: Update Kustomization

Add to `kubernetes/base/secrets/kustomization.yaml`:
```yaml
resources:
  - liberty-secrets.yaml
  - grafana-secrets.yaml
  - myapp-secrets.yaml  # Add new file
```

### Step 4: Reference in Deployment

```yaml
env:
  - name: API_KEY
    valueFrom:
      secretKeyRef:
        name: myapp-secrets
        key: api-key
```

## Secret Rotation

### Automatic Rotation (Recommended)

1. **Update secret in AWS Secrets Manager**:
   ```bash
   aws secretsmanager update-secret \
       --secret-id mw-prod/database/credentials \
       --secret-string '{"username":"liberty","password":"new-rotated-password",...}'
   ```

2. **ESO syncs automatically** based on `refreshInterval` (default: 1 hour)

3. **Force immediate sync**:
   ```bash
   # Delete and recreate the ExternalSecret to trigger immediate sync
   kubectl annotate externalsecret liberty-secrets -n liberty force-sync=$(date +%s)
   ```

4. **Restart pods to pick up new secrets**:
   ```bash
   kubectl rollout restart deployment liberty-app -n liberty
   ```

### AWS Secrets Manager Rotation

For automated rotation, configure AWS Secrets Manager rotation:

```hcl
resource "aws_secretsmanager_secret_rotation" "db_credentials" {
  secret_id           = aws_secretsmanager_secret.db_credentials.id
  rotation_lambda_arn = aws_lambda_function.rotation.arn

  rotation_rules {
    automatically_after_days = 30
  }
}
```

### Rotation Procedure Checklist

1. [ ] Update secret value in AWS Secrets Manager
2. [ ] Wait for ESO refresh (or force sync)
3. [ ] Verify new secret value in Kubernetes: `kubectl get secret -o yaml`
4. [ ] Restart affected deployments
5. [ ] Verify application connectivity
6. [ ] Update any documentation if secret format changed

## Troubleshooting

### Check ESO Status

```bash
# ESO controller pods
kubectl get pods -n external-secrets

# Controller logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
```

### Check ClusterSecretStore

```bash
# Store status
kubectl get clustersecretstore
kubectl describe clustersecretstore aws-secrets-manager
```

### Check ExternalSecret

```bash
# ExternalSecret status
kubectl get externalsecret -A
kubectl describe externalsecret liberty-secrets -n liberty

# Check sync status
kubectl get externalsecret liberty-secrets -n liberty -o jsonpath='{.status.conditions}'
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| `SecretSyncedError` | IAM permissions | Check IAM role/policy attached to ESO |
| `ProviderError` | Wrong secret path | Verify secret name in AWS console |
| `InvalidClusterSecretStoreRef` | Store not ready | Check ClusterSecretStore status |
| Secret not updating | Refresh interval | Force sync or wait for next refresh |

### Verify AWS Connectivity

```bash
# From ESO pod
kubectl exec -it -n external-secrets deploy/external-secrets -- \
    aws secretsmanager list-secrets --region us-east-1
```

## Security Best Practices

### IAM Least Privilege

- Grant only `GetSecretValue` and `DescribeSecret` permissions
- Restrict to specific secret paths: `arn:aws:secretsmanager:*:*:secret:mw-prod/*`
- Use IRSA for EKS instead of long-lived access keys

### Kubernetes RBAC

- ESO service accounts should have minimal permissions
- Use namespace-scoped SecretStores when possible for multi-tenant clusters

### Secret Hygiene

- Set appropriate `refreshInterval` (1h is a good default)
- Use `deletionPolicy: Retain` to prevent accidental secret deletion
- Enable AWS Secrets Manager audit logging via CloudTrail

### Encryption

- AWS Secrets Manager encrypts at rest with KMS
- Kubernetes Secrets are encrypted at rest (ensure etcd encryption is enabled)
- Use Transit encryption for ElastiCache Redis (`transit_encryption_enabled = true`)

### Access Control

```bash
# View who can access secrets in a namespace
kubectl auth can-i get secrets -n liberty --as=system:serviceaccount:liberty:liberty-app
```

### Audit Logging

Enable CloudTrail logging for Secrets Manager:
```bash
aws cloudtrail lookup-events \
    --lookup-attributes AttributeKey=EventSource,AttributeValue=secretsmanager.amazonaws.com
```

## Files Reference

| File | Purpose |
|------|---------|
| `kubernetes/base/external-secrets/aws-clustersecretstore.yaml` | AWS Secrets Manager connection |
| `kubernetes/base/external-secrets/local-clustersecretstore.yaml` | Local development backend |
| `kubernetes/base/external-secrets/helm-values.yaml` | ESO Helm installation values |
| `kubernetes/base/secrets/liberty-secrets.yaml` | Liberty app ExternalSecret |
| `kubernetes/base/secrets/grafana-secrets.yaml` | Grafana ExternalSecret |
| `automated/terraform/environments/prod-aws/database.tf` | AWS secret definitions |

## Related Documentation

- [External Secrets Operator Docs](https://external-secrets.io/)
- [AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/)
- [Credential Setup Guide](./CREDENTIAL_SETUP.md)
- [Kubernetes Security](./KUBERNETES_SECURITY.md)
