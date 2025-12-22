# Jenkins on Kubernetes

Deploy Jenkins to a Kubernetes cluster using Helm with dynamic pod agents.

## Prerequisites

- Kubernetes cluster with kubectl access
- Helm 3.x installed
- MetalLB configured (for LoadBalancer IPs)
- Longhorn storage class (or modify `values.yaml` for your storage)

## Quick Start

```bash
# Add Jenkins Helm repository
helm repo add jenkins https://charts.jenkins.io
helm repo update

# Create namespace
kubectl create namespace jenkins

# Install Jenkins
helm upgrade --install jenkins jenkins/jenkins \
    --namespace jenkins \
    -f values.yaml \
    --wait --timeout 15m

# Check status
kubectl get pods -n jenkins
kubectl get svc -n jenkins
```

## Access Jenkins

- **URL**: http://192.168.68.206:8080
- **Username**: admin
- **Password**: JenkinsAdmin2024!

## Configuration

### Pod Templates

The configuration includes a pod template `middleware-agent` with three containers matching the Jenkinsfile requirements:

| Container | Image | Purpose |
|-----------|-------|---------|
| maven | maven:3.9-eclipse-temurin-17 | Build Java applications |
| podman | quay.io/podman/stable:latest | Build container images |
| ansible | cytopia/ansible:latest | Run Ansible playbooks |

### Plugins Installed

- kubernetes - Dynamic pod agents
- workflow-aggregator - Pipeline support
- git - Source control
- aws-credentials - AWS authentication
- amazon-ecr - ECR integration
- configuration-as-code - JCasC
- blueocean - Modern UI

## Post-Installation Setup

### 1. Configure AWS Credentials

Navigate to **Manage Jenkins > Credentials > System > Global credentials**

Add credentials:
- **Kind**: AWS Credentials
- **ID**: `aws-prod`
- **Access Key ID**: Your AWS access key
- **Secret Access Key**: Your AWS secret key

### 2. Configure Git Credentials

Add credentials for your Git repository:
- **Kind**: Username with password (or SSH key)
- **ID**: `github-token`
- **Username**: Your GitHub username
- **Password**: GitHub personal access token

### 3. Update Pipeline Job

Edit the `middleware-platform` job:
1. Go to **Configure**
2. Update the Git repository URL
3. Save and run a build

## Verify Dynamic Agents

When a pipeline runs, you should see pods created in the jenkins namespace:

```bash
kubectl get pods -n jenkins -w
```

Expected output during build:
```
jenkins-0                          1/1     Running   0          10m
middleware-platform-xyz-abc        3/3     Running   0          30s
```

## Troubleshooting

### Pods not starting

Check RBAC permissions:
```bash
kubectl auth can-i create pods -n jenkins --as=system:serviceaccount:jenkins:jenkins
```

### Plugin installation issues

View controller logs:
```bash
kubectl logs -n jenkins jenkins-0 -f
```

### Storage issues

Verify Longhorn is available:
```bash
kubectl get sc
kubectl get pvc -n jenkins
```

## Customization

### Change LoadBalancer IP

Edit `values.yaml`:
```yaml
controller:
  loadBalancerIP: "192.168.68.XXX"
```

### Use different storage class

Edit `values.yaml`:
```yaml
persistence:
  storageClass: "your-storage-class"
```

### Add more plugins

Edit `values.yaml` and add to `installPlugins` list.

## Uninstall

```bash
helm uninstall jenkins -n jenkins
kubectl delete pvc -n jenkins --all
kubectl delete namespace jenkins
```
