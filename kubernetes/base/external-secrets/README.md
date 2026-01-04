# External Secrets Operator Installation

This directory contains configuration for External Secrets Operator (ESO), which syncs
secrets from external providers (AWS Secrets Manager, HashiCorp Vault) into Kubernetes.

## Prerequisites

Install External Secrets Operator using Helm:

```bash
# Add the External Secrets Helm repository
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Create namespace
kubectl create namespace external-secrets

# Install ESO with IRSA support for AWS (recommended for EKS)
helm install external-secrets external-secrets/external-secrets \
    --namespace external-secrets \
    --set installCRDs=true \
    --set webhook.port=9443 \
    --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::ACCOUNT_ID:role/external-secrets-role"

# Or install for local development (no IRSA)
helm install external-secrets external-secrets/external-secrets \
    --namespace external-secrets \
    --set installCRDs=true
```

## Verify Installation

```bash
# Check that ESO is running
kubectl get pods -n external-secrets

# Verify CRDs are installed
kubectl get crd | grep external-secrets
```

## Apply ClusterSecretStores

After ESO is running, apply the secret stores:

```bash
# For AWS Secrets Manager (production)
kubectl apply -f aws-clustersecretstore.yaml

# For local development (Kubernetes secrets backend)
kubectl apply -f local-clustersecretstore.yaml
```

## Files in This Directory

| File | Purpose |
|------|---------|
| `aws-clustersecretstore.yaml` | ClusterSecretStore for AWS Secrets Manager |
| `local-clustersecretstore.yaml` | ClusterSecretStore for local/dev environments |
| `helm-values.yaml` | Helm values for ESO installation |
| `kustomization.yaml` | Kustomize configuration |

## AWS IAM Configuration

For AWS Secrets Manager access, the External Secrets service account needs IAM permissions.

### Option 1: IRSA (Recommended for EKS)

Create an IAM role with the following policy:

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
            "Resource": "arn:aws:secretsmanager:*:*:secret:mw-prod/*"
        }
    ]
}
```

Trust relationship for the role:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/oidc.eks.REGION.amazonaws.com/id/OIDC_ID"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "oidc.eks.REGION.amazonaws.com/id/OIDC_ID:sub": "system:serviceaccount:external-secrets:external-secrets"
                }
            }
        }
    ]
}
```

### Option 2: AWS Access Keys (Local Development)

For non-EKS clusters, create a Kubernetes secret with AWS credentials:

```bash
kubectl create secret generic aws-credentials \
    --namespace external-secrets \
    --from-literal=access-key=YOUR_ACCESS_KEY \
    --from-literal=secret-access-key=YOUR_SECRET_KEY
```

## Troubleshooting

```bash
# Check ClusterSecretStore status
kubectl get clustersecretstore

# Check ExternalSecret sync status
kubectl get externalsecret -n liberty

# View ESO controller logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets

# Describe failed ExternalSecret for details
kubectl describe externalsecret liberty-secrets -n liberty
```
