# Local Kubernetes Deployment Guide

This guide covers deploying the Middleware Automation Platform to a **multi-node bare-metal Kubernetes cluster** for development and testing. This is designed for the 3-node Beelink homelab cluster, but can be adapted for any on-premises Kubernetes environment.

> **Note:** This guide is for physical/bare-metal multi-node clusters, NOT single-node development tools like minikube or Docker Desktop. For single-node local testing, consider using kind (Kubernetes in Docker) with the provided manifests.

## Target Environment

This documentation targets the **Beelink Mini PC Kubernetes Lab**:

| Node | Hostname | IP Address | Role | Hardware |
|------|----------|------------|------|----------|
| 1 | k8s-master-01 | 192.168.68.82 | Control Plane + Worker | Beelink Mini PC |
| 2 | k8s-worker-01 | 192.168.68.86 | Worker | Beelink Mini PC |
| 3 | k8s-worker-02 | 192.168.68.88 | Worker | Beelink Mini PC |

The cluster uses:
- **kubeadm** with containerd as the Kubernetes distribution
- **MetalLB** for bare-metal LoadBalancer services
- **Longhorn** for distributed persistent storage across nodes
- **Local network** 192.168.68.0/24

## Prerequisites

- **3-node Kubernetes cluster** (k3s, kubeadm, or similar) already running
- kubectl configured to access the cluster (`kubectl get nodes` should show all 3 nodes)
- MetalLB installed for LoadBalancer services (required for bare-metal)
- Storage class available (Longhorn recommended for multi-node)
- Helm 3.x installed
- SSH access to all cluster nodes (for image distribution)

## Architecture Overview

```
Beelink Kubernetes Lab (192.168.68.0/24)
=========================================

Physical Nodes:
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│  k8s-master-01   │  │  k8s-worker-01   │  │  k8s-worker-02   │
│  192.168.68.82   │  │  192.168.68.86   │  │  192.168.68.88   │
│  Control Plane   │  │     Worker       │  │     Worker       │
│  + Worker        │  │                  │  │                  │
└────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘
         │                     │                     │
         └─────────────────────┼─────────────────────┘
                               │
                    ┌──────────▼──────────┐
                    │   MetalLB L2 Pool   │
                    │ 192.168.68.200-210  │
                    └─────────────────────┘
                               │
         ┌─────────────────────┼─────────────────────┐
         │                     │                     │
         ▼                     ▼                     ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│   Prometheus    │  │    Grafana      │  │      AWX        │
│ 192.168.68.201  │  │ 192.168.68.202  │  │ 192.168.68.205  │
└─────────────────┘  └─────────────────┘  └─────────────────┘

┌─────────────────┐  ┌─────────────────────────────────────────┐
│    Jenkins      │  │            Liberty Pods                 │
│ 192.168.68.206  │  │  (Distributed across all 3 nodes)       │
└─────────────────┘  └─────────────────────────────────────────┘
```

## MetalLB IP Assignments

| Service       | IP Address      | Port |
|---------------|-----------------|------|
| Liberty       | 192.168.68.200  | 9080 |
| Prometheus    | 192.168.68.201  | 9090 |
| Grafana       | 192.168.68.202  | 80   |
| AlertManager  | 192.168.68.203  | 9093 |
| ArgoCD        | 192.168.68.204  | 443  |
| AWX           | 192.168.68.205  | 80   |
| Jenkins       | 192.168.68.206  | 8080 |
| Reserved      | 192.168.68.207-210 | - |

## Deployment Steps

### 1. Deploy Liberty Application

This section covers building and deploying the Open Liberty application to the local Kubernetes cluster.

#### Step 1: Build the Sample Application

Build the WAR file from the sample-app directory using Maven:

```bash
# Navigate to project root
cd /home/justin/Projects/middleware-automation-platform

# Build the WAR file
mvn -f sample-app/pom.xml clean package

# Verify the WAR was created
ls -la sample-app/target/sample-app.war
```

The build produces `sample-app.war` containing a demo REST API using:
- Jakarta EE 10 Web Profile
- MicroProfile 6.0 (Health, Metrics, Config)
- Java 17

#### Step 2: Copy WAR to Container Build Directory

```bash
cp sample-app/target/sample-app.war containers/liberty/apps/
```

#### Step 3: Build the Liberty Container Image

```bash
cd /home/justin/Projects/middleware-automation-platform/containers/liberty

# Build the image
podman build -t liberty-app:1.0.0 -f Containerfile .

# Verify the image was created
podman images | grep liberty-app
```

The Containerfile uses the official Open Liberty base image (`icr.io/appcafe/open-liberty:kernel-slim-java17-openj9-ubi`) and includes:
- **server.xml** with configured features: `restfulWS-3.1`, `jsonb-3.0`, `cdi-4.0`, `mpHealth-4.0`, `mpMetrics-5.0`, `mpConfig-3.0`, `jdbc-4.3`, `ssl-1.0`
- **jvm.options** for JVM tuning
- Built-in health check using `/health/ready` endpoint

#### Step 4: Load Image into Kubernetes Cluster

For the Beelink kubeadm cluster, import the image directly on each node:

```bash
# Save the image to a tar file
podman save liberty-app:1.0.0 -o /tmp/liberty-app.tar

# Import on k8s-master-01 (192.168.68.82)
sudo ctr -n k8s.io images import /tmp/liberty-app.tar

# Import on k8s-worker-01 (192.168.68.86)
scp /tmp/liberty-app.tar 192.168.68.86:/tmp/
ssh 192.168.68.86 "sudo ctr -n k8s.io images import /tmp/liberty-app.tar"

# Import on k8s-worker-02 (192.168.68.88)
scp /tmp/liberty-app.tar 192.168.68.88:/tmp/
ssh 192.168.68.88 "sudo ctr -n k8s.io images import /tmp/liberty-app.tar"

# Verify import
sudo crictl images | grep liberty-app
```

#### Step 5: Create Namespace and Secrets

```bash
# Create the liberty namespace
kubectl create namespace liberty

# Create the ConfigMap for Liberty configuration
kubectl create configmap liberty-config \
  --namespace liberty \
  --from-file=server.xml=/home/justin/Projects/middleware-automation-platform/containers/liberty/server.xml \
  --from-literal=db.host=postgresql.liberty.svc.cluster.local

# Create secrets for sensitive data
kubectl create secret generic liberty-secrets \
  --namespace liberty \
  --from-literal=db.password='your-secure-password'

# Verify resources
kubectl get configmap,secret -n liberty
```

#### Step 6: Create Kustomize Overlay for Local Deployment

```bash
# Create overlay directory
mkdir -p /home/justin/Projects/middleware-automation-platform/kubernetes/overlays/local

# Create kustomization file
cat > /home/justin/Projects/middleware-automation-platform/kubernetes/overlays/local/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: liberty
resources:
  - ../../base/liberty-deployment.yaml
images:
  - name: icr.io/appcafe/open-liberty:kernel-slim-java17-openj9-ubi
    newName: liberty-app
    newTag: "1.0.0"
EOF
```

#### Step 7: Apply the Deployment

```bash
cd /home/justin/Projects/middleware-automation-platform

# Apply with kustomize overlay
kubectl apply -k kubernetes/overlays/local
```

This creates the following resources:

| Resource | Name | Description |
|----------|------|-------------|
| Deployment | liberty-app | 3 replicas with rolling update strategy |
| Service | liberty-service | ClusterIP on ports 9080 (HTTP) and 9443 (HTTPS) |
| HorizontalPodAutoscaler | liberty-hpa | Scales 3-10 replicas based on CPU |
| PodDisruptionBudget | liberty-pdb | Minimum 2 pods during disruptions |

#### Step 8: Verify Pods Are Running

```bash
# Watch pod creation
kubectl get pods -n liberty -w

# Check deployment status
kubectl rollout status deployment/liberty-app -n liberty

# Check logs
kubectl logs -n liberty -l app=liberty --tail=50
```

Expected output:
```
NAME                          READY   STATUS    RESTARTS   AGE
liberty-app-7d8f9b6c5-abc12   1/1     Running   0          2m
liberty-app-7d8f9b6c5-def34   1/1     Running   0          2m
liberty-app-7d8f9b6c5-ghi56   1/1     Running   0          2m
```

#### Step 9: Access the Application

**Option A: Port Forward (Quick Testing)**

```bash
kubectl port-forward svc/liberty-service 9080:9080 -n liberty
```

Then test endpoints:
```bash
curl http://localhost:9080/health/ready
curl http://localhost:9080/health/live
curl http://localhost:9080/metrics
curl http://localhost:9080/sample-app/api/health
```

**Option B: Ingress via NGINX**

```bash
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: liberty-ingress
  namespace: liberty
spec:
  ingressClassName: nginx
  rules:
  - host: liberty.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: liberty-service
            port:
              number: 9080
EOF

# Add to /etc/hosts
echo "192.168.68.200 liberty.local" | sudo tee -a /etc/hosts
```

Access at: http://liberty.local/sample-app/

**Option C: MetalLB LoadBalancer**

```bash
kubectl patch svc liberty-service -n liberty \
  -p '{"spec": {"type": "LoadBalancer"}}'

kubectl get svc liberty-service -n liberty
```

#### Deployment Verification Checklist

| Check | Command | Expected Result |
|-------|---------|-----------------|
| Pods running | `kubectl get pods -n liberty` | 3/3 Running |
| Service exists | `kubectl get svc -n liberty` | liberty-service listed |
| Health ready | `curl localhost:9080/health/ready` | `{"status":"UP"}` |
| Metrics exposed | `curl localhost:9080/metrics` | Prometheus metrics |

#### Liberty Cleanup

```bash
kubectl delete -f kubernetes/base/liberty-deployment.yaml -n liberty
kubectl delete configmap liberty-config -n liberty
kubectl delete secret liberty-secrets -n liberty
kubectl delete namespace liberty
```

### 2. Deploy Monitoring Stack

This section covers deploying Prometheus and Grafana using the kube-prometheus-stack Helm chart, which provides a complete monitoring solution including Prometheus Operator, Grafana, AlertManager, and node exporters.

#### Step 2.1: Create Monitoring Namespace

```bash
kubectl create namespace monitoring
```

#### Step 2.2: Add Helm Repository

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

#### Step 2.3: Deploy Prometheus Stack with LoadBalancer IPs

Deploy the kube-prometheus-stack chart with LoadBalancer services configured for MetalLB:

```bash
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --set prometheus.service.type=LoadBalancer \
    --set prometheus.service.loadBalancerIP=192.168.68.201 \
    --set grafana.service.type=LoadBalancer \
    --set grafana.service.loadBalancerIP=192.168.68.202 \
    --set grafana.adminPassword=admin \
    --set alertmanager.service.type=LoadBalancer \
    --set alertmanager.service.loadBalancerIP=192.168.68.203 \
    --wait --timeout 10m
```

For production-like deployments with persistence, create a values file:

```bash
cat <<'EOF' > monitoring-values.yaml
prometheus:
  service:
    type: LoadBalancer
    loadBalancerIP: 192.168.68.201
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    retention: 15d
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: longhorn
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 50Gi

grafana:
  service:
    type: LoadBalancer
    loadBalancerIP: 192.168.68.202
  adminPassword: admin
  persistence:
    enabled: true
    storageClassName: longhorn
    size: 10Gi

alertmanager:
  service:
    type: LoadBalancer
    loadBalancerIP: 192.168.68.203
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: longhorn
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 5Gi
EOF

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    -f monitoring-values.yaml \
    --wait --timeout 10m
```

#### Step 2.4: Verify Deployment

Check that all pods are running:

```bash
kubectl get pods -n monitoring
```

Verify LoadBalancer IPs are assigned:

```bash
kubectl get svc -n monitoring | grep LoadBalancer
```

Expected output:
```
prometheus-kube-prometheus-prometheus   LoadBalancer   10.43.x.x   192.168.68.201   9090:xxxxx/TCP
prometheus-grafana                      LoadBalancer   10.43.x.x   192.168.68.202   80:xxxxx/TCP
prometheus-kube-prometheus-alertmanager LoadBalancer   10.43.x.x   192.168.68.203   9093:xxxxx/TCP
```

#### Step 2.5: Access Monitoring Services

| Service | URL | Default Credentials |
|---------|-----|---------------------|
| Prometheus | http://192.168.68.201:9090 | No authentication required |
| Grafana | http://192.168.68.202:3000 | admin / admin |
| AlertManager | http://192.168.68.203:9093 | No authentication required |

#### Step 2.6: Configure Liberty Scrape Targets

**Option A: ServiceMonitor for Kubernetes-Deployed Liberty**

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: liberty-monitor
  namespace: monitoring
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app: liberty
  namespaceSelector:
    matchNames:
      - middleware
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
EOF
```

**Option B: Additional Scrape Config for External Liberty Servers**

For Liberty servers running outside Kubernetes (e.g., on VMs at 192.168.68.86 and 192.168.68.88):

```bash
cat <<'EOF' > liberty-scrape-config.yaml
- job_name: 'liberty'
  metrics_path: /metrics
  static_configs:
    - targets:
        - '192.168.68.88:9080'
        - '192.168.68.86:9080'
      labels:
        environment: 'development'
EOF

kubectl create secret generic additional-scrape-configs \
    --namespace monitoring \
    --from-file=prometheus-additional.yaml=liberty-scrape-config.yaml \
    --dry-run=client -o yaml | kubectl apply -f -

helm upgrade prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --reuse-values \
    --set prometheus.prometheusSpec.additionalScrapeConfigsSecret.enabled=true \
    --set prometheus.prometheusSpec.additionalScrapeConfigsSecret.name=additional-scrape-configs \
    --set prometheus.prometheusSpec.additionalScrapeConfigsSecret.key=prometheus-additional.yaml
```

#### Step 2.7: Import Liberty Dashboard

**Method 1: Import via Grafana UI**

1. Open Grafana at http://192.168.68.202:3000
2. Log in with **admin** / **admin**
3. Navigate to **Dashboards** > **Import**
4. Click **Upload JSON file**
5. Select: `monitoring/grafana/dashboards/ecs-liberty.json`
6. Select the Prometheus data source
7. Click **Import**

**Method 2: Import via API**

```bash
curl -X POST http://192.168.68.202:3000/api/dashboards/db \
    -H "Content-Type: application/json" \
    -u admin:admin \
    -d @- <<EOF
{
    "dashboard": $(cat monitoring/grafana/dashboards/ecs-liberty.json),
    "overwrite": true,
    "inputs": [{
        "name": "DS_PROMETHEUS",
        "type": "datasource",
        "pluginId": "prometheus",
        "value": "Prometheus"
    }]
}
EOF
```

**Method 3: Persistent Import via ConfigMap**

```bash
kubectl create configmap liberty-dashboard \
    --namespace monitoring \
    --from-file=liberty-dashboard.json=monitoring/grafana/dashboards/ecs-liberty.json

kubectl label configmap liberty-dashboard -n monitoring grafana_dashboard=1
```

The Grafana sidecar automatically loads dashboards from ConfigMaps with the `grafana_dashboard=1` label.

#### Liberty Dashboard Panels

| Panel | Description | Key Metrics |
|-------|-------------|-------------|
| Healthy Tasks | Liberty instances reporting up | `up{job="liberty"} == 1` |
| Unhealthy Tasks | Liberty instances reporting down | `up{job="liberty"} == 0` |
| Request Rate | HTTP requests per second | `rate(servlet_request_total{mp_scope="base"}[5m])` |
| Error Rates | 4xx and 5xx error percentages | `servlet_request_total{mp_scope="base", status=~"4.."}` |
| Heap Usage % | JVM heap utilization | `memory_usedHeap_bytes{mp_scope="base"} / memory_maxHeap_bytes{mp_scope="base"}` |
| Heap Memory | Used vs maximum heap bytes | `memory_usedHeap_bytes{mp_scope="base"}`, `memory_maxHeap_bytes{mp_scope="base"}` |

### 3. Deploy AWX

```bash
# Install AWX Operator
kubectl apply -f https://raw.githubusercontent.com/ansible/awx-operator/devel/deploy/awx-operator.yaml

# Create AWX admin password secret
kubectl create secret generic awx-admin-password \
  --namespace=awx \
  --from-literal=password='your-secure-password'

# Deploy AWX
kubectl apply -f awx/awx-deployment.yaml
```

### 4. Deploy Jenkins

Jenkins provides CI/CD pipeline capabilities with dynamic Kubernetes pod agents for building and deploying the middleware platform. The deployment uses Helm with a customized values file that pre-configures plugins, pod templates, and Jenkins Configuration as Code (JCasC).

#### Overview

| Property | Value |
|----------|-------|
| Namespace | `jenkins` |
| LoadBalancer IP | 192.168.68.206 |
| Port | 8080 |
| Storage | 20Gi (Longhorn) |
| Access URL | http://192.168.68.206:8080 |

#### Step 1: Create the Jenkins Namespace

```bash
kubectl create namespace jenkins
```

#### Step 2: Create the Admin Credentials Secret

Jenkins requires an admin password secret to exist **before** installation. The Helm chart references this secret via the `existingSecret` configuration. Never commit passwords to version control.

**Option A: Set a specific password**

```bash
kubectl create secret generic jenkins-admin-secret \
  --namespace jenkins \
  --from-literal=jenkins-admin-password='YOUR_SECURE_PASSWORD'
```

**Option B: Generate a random secure password**

```bash
# Generate a 24-character random password
JENKINS_PASSWORD=$(openssl rand -base64 24)
echo "Jenkins admin password: $JENKINS_PASSWORD"
echo "Save this password securely!"

# Create the secret
kubectl create secret generic jenkins-admin-secret \
  --namespace jenkins \
  --from-literal=jenkins-admin-password="$JENKINS_PASSWORD"
```

**Verify the secret was created:**

```bash
kubectl get secret jenkins-admin-secret -n jenkins
```

For comprehensive credential management documentation, see [CREDENTIAL_SETUP.md](CREDENTIAL_SETUP.md#31-kubernetes-deployment-localhelm).

#### Step 3: Add the Jenkins Helm Repository

```bash
helm repo add jenkins https://charts.jenkins.io
helm repo update
```

#### Step 4: Deploy Jenkins Using Helm

Deploy Jenkins using the customized values file located at `ci-cd/jenkins/kubernetes/values.yaml`. This configuration includes:

- **LoadBalancer service** with MetalLB IP 192.168.68.206
- **Longhorn persistent storage** (20Gi)
- **Pre-configured plugins**: Kubernetes, AWS credentials, ECR, Pipeline, Blue Ocean, Git
- **Dynamic pod agents** with Maven, Podman, and Ansible containers
- **JCasC** (Jenkins Configuration as Code) for automated setup
- **Setup wizard disabled** for immediate access

```bash
helm upgrade --install jenkins jenkins/jenkins \
  --namespace jenkins \
  --values ci-cd/jenkins/kubernetes/values.yaml \
  --wait --timeout 15m
```

**Monitor the deployment progress:**

```bash
# Watch pod status until Running
kubectl get pods -n jenkins -w

# Check events if pod is stuck
kubectl get events -n jenkins --sort-by='.lastTimestamp'

# View controller logs during startup
kubectl logs -n jenkins jenkins-0 -f
```

The Jenkins controller pod should reach `Running` status within 5-10 minutes. Initial plugin downloads may take additional time.

#### Step 5: Verify LoadBalancer IP Assignment

Confirm MetalLB assigned the correct external IP address:

```bash
kubectl get svc -n jenkins
```

**Expected output:**

```
NAME            TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)          AGE
jenkins         LoadBalancer   10.43.x.x       192.168.68.206   8080:xxxxx/TCP   5m
jenkins-agent   ClusterIP      10.43.x.x       <none>           50000/TCP        5m
```

If `EXTERNAL-IP` shows `<pending>`:
1. Verify MetalLB is running: `kubectl get pods -n metallb-system`
2. Check that 192.168.68.206 is within MetalLB's configured IP pool
3. Review MetalLB logs: `kubectl logs -n metallb-system -l app=metallb`

#### Step 6: Access Jenkins

| Property | Value |
|----------|-------|
| **URL** | http://192.168.68.206:8080 |
| **Username** | `admin` |
| **Password** | The password you created in Step 2 |

**Retrieve the password if needed:**

```bash
kubectl get secret jenkins-admin-secret -n jenkins \
  -o jsonpath='{.data.jenkins-admin-password}' | base64 -d && echo
```

#### Step 7: Initial Configuration

The Helm chart pre-configures Jenkins using JCasC, automating most setup tasks. Complete these post-installation steps to enable full functionality:

##### 7.1 Configure AWS Credentials

Required for deploying to AWS production environment:

1. Navigate to **Manage Jenkins** > **Credentials** > **System** > **Global credentials (unrestricted)**
2. Click **Add Credentials**
3. Configure the following:
   - **Kind:** AWS Credentials
   - **Scope:** Global
   - **ID:** `aws-prod`
   - **Access Key ID:** Your AWS IAM access key
   - **Secret Access Key:** Your AWS IAM secret key
   - **Description:** AWS Production Account Credentials
4. Click **Create**

##### 7.2 Configure Git Repository Credentials

Required for accessing your source code repository:

1. Navigate to **Manage Jenkins** > **Credentials** > **System** > **Global credentials (unrestricted)**
2. Click **Add Credentials**
3. Configure the following:
   - **Kind:** Username with password
   - **Scope:** Global
   - **ID:** `github-token`
   - **Username:** Your GitHub username
   - **Password:** GitHub Personal Access Token (requires `repo` scope)
   - **Description:** GitHub Repository Access
4. Click **Create**

##### 7.3 Update the Pipeline Job Repository URL

The JCasC configuration creates a `middleware-platform` pipeline job with a placeholder repository URL. Update it to point to your repository:

1. From the Jenkins dashboard, click on the `middleware-platform` job
2. Click **Configure** in the left sidebar
3. Scroll to **Pipeline** > **Definition** > **SCM**
4. Under **Repositories**, update:
   - **Repository URL:** Your repository URL (e.g., `https://github.com/YOUR_ORG/middleware-automation-platform.git`)
   - **Credentials:** Select `github-token`
5. Verify **Script Path** is set to `ci-cd/Jenkinsfile`
6. Click **Save**

##### 7.4 Verify Dynamic Pod Agents

Test that Jenkins can create dynamic pod agents in Kubernetes:

1. Trigger a build of the `middleware-platform` job by clicking **Build with Parameters**
2. Select your desired options and click **Build**
3. Monitor agent pod creation:

```bash
kubectl get pods -n jenkins -w
```

**Expected behavior:**

During a build, you should see a new pod created with the pattern `middleware-platform-<build>-<hash>`:

```
NAME                                  READY   STATUS    RESTARTS   AGE
jenkins-0                             1/1     Running   0          30m
middleware-platform-17-abc123-xyz     3/3     Running   0          15s
```

The agent pod contains three containers (maven, podman, ansible) as defined in the pod template. The pod is automatically deleted after the build completes.

#### Pre-Configured Pod Template

The values file configures a `middleware-agent` pod template with the following containers:

| Container | Image | Purpose | Resources |
|-----------|-------|---------|-----------|
| maven | `maven:3.9-eclipse-temurin-17` | Build Java WAR files | 512Mi-1Gi RAM |
| podman | `quay.io/podman/stable:latest` | Build and push container images | 512Mi-2Gi RAM |
| ansible | `cytopia/ansible:latest` | Run deployment playbooks | 256Mi-512Mi RAM |

This matches the container requirements in `ci-cd/Jenkinsfile`.

#### Pre-Installed Plugins

The Helm deployment installs these plugins automatically:

| Plugin | Purpose |
|--------|---------|
| kubernetes | Dynamic pod agents in Kubernetes |
| workflow-aggregator | Pipeline support |
| git | Git SCM integration |
| configuration-as-code | JCasC support |
| credentials-binding | Secure credential usage in pipelines |
| aws-credentials | AWS IAM credential management |
| amazon-ecr | Amazon ECR authentication for container pushes |
| pipeline-stage-view | Visual pipeline stage progress |
| blueocean | Modern pipeline UI |
| job-dsl | Programmatic job creation |

#### Upgrade Jenkins

To upgrade Jenkins or apply configuration changes:

```bash
helm upgrade jenkins jenkins/jenkins \
  --namespace jenkins \
  --values ci-cd/jenkins/kubernetes/values.yaml \
  --wait --timeout 15m
```

#### Uninstall Jenkins

To completely remove Jenkins from the cluster:

```bash
# Remove the Helm release
helm uninstall jenkins -n jenkins

# Delete persistent volume claims (removes all Jenkins data)
kubectl delete pvc -n jenkins --all

# Delete the namespace
kubectl delete namespace jenkins
```

**Warning:** Deleting PVCs removes all Jenkins configuration, jobs, and build history permanently.

## Verification

This section provides comprehensive verification procedures for all deployed services. Use these commands to confirm successful deployment and ongoing health monitoring.

### 1. Liberty Server Health Checks

Liberty servers expose MicroProfile Health endpoints for monitoring readiness, liveness, and startup status.

#### Readiness Check (Ready to Accept Traffic)

```bash
# Liberty Server 01
curl -s http://192.168.68.86:9080/health/ready
# Expected output: {"checks":[],"status":"UP"}

# Liberty Server 02
curl -s http://192.168.68.88:9080/health/ready
# Expected output: {"checks":[],"status":"UP"}

# Check with HTTP status code only
curl -s -o /dev/null -w "%{http_code}" http://192.168.68.86:9080/health/ready
# Expected output: 200
```

#### Liveness Check (Application Running)

```bash
# Liberty Server 01
curl -s http://192.168.68.86:9080/health/live
# Expected output: {"checks":[],"status":"UP"}

# Liberty Server 02
curl -s http://192.168.68.88:9080/health/live
# Expected output: {"checks":[],"status":"UP"}
```

#### Startup Check (Initialization Complete)

```bash
# Liberty Server 01
curl -s http://192.168.68.86:9080/health/started
# Expected output: {"checks":[],"status":"UP"}

# Liberty Server 02
curl -s http://192.168.68.88:9080/health/started
# Expected output: {"checks":[],"status":"UP"}
```

#### Combined Health Check (All Checks)

```bash
curl -s http://192.168.68.86:9080/health | jq .
# Expected output:
# {
#   "checks": [],
#   "status": "UP"
# }
```

### 2. Liberty Metrics Endpoint

Liberty exposes Prometheus-compatible metrics at the `/metrics` endpoint for monitoring JVM performance, HTTP requests, and application-specific data.

```bash
# View all metrics
curl -s http://192.168.68.86:9080/metrics

# Check specific metric categories
curl -s http://192.168.68.86:9080/metrics/base      # JVM metrics
curl -s http://192.168.68.86:9080/metrics/vendor    # Liberty-specific metrics
curl -s http://192.168.68.86:9080/metrics/application  # Application metrics

# Verify metrics endpoint returns data (check line count)
curl -s http://192.168.68.86:9080/metrics | wc -l
# Expected output: 100+ lines of metrics data

# Sample key metrics to verify (MicroProfile Metrics 5.0 naming):
# - jvm_uptime_seconds{mp_scope="base"}
# - memory_usedHeap_bytes{mp_scope="base"}
# - cpu_processCpuLoad_percent{mp_scope="base"}
# - servlet_request_total{mp_scope="vendor"}
```

### 3. Prometheus Targets Verification

Verify that Prometheus is successfully scraping all configured targets.

#### Prometheus Health Check

```bash
# Prometheus readiness
curl -s http://192.168.68.82:9090/-/ready
# Expected output: Prometheus Server is Ready.

# Prometheus health
curl -s http://192.168.68.82:9090/-/healthy
# Expected output: Prometheus Server is Healthy.

# Check with HTTP status code
curl -s -o /dev/null -w "%{http_code}" http://192.168.68.82:9090/-/ready
# Expected output: 200
```

#### Verify Scrape Targets

```bash
# Query Prometheus API for all target status
curl -s http://192.168.68.82:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance, health: .health}'

# Expected output (all targets should show "health": "up"):
# {"job":"liberty","instance":"192.168.68.88:9080","health":"up"}
# {"job":"liberty","instance":"192.168.68.86:9080","health":"up"}
# {"job":"node","instance":"192.168.68.82:9100","health":"up"}
# {"job":"node","instance":"192.168.68.88:9100","health":"up"}
# {"job":"node","instance":"192.168.68.86:9100","health":"up"}
# {"job":"prometheus","instance":"localhost:9090","health":"up"}
# {"job":"jenkins","instance":"192.168.68.206:8080","health":"up"}

# Count healthy vs unhealthy targets
curl -s http://192.168.68.82:9090/api/v1/targets | jq '[.data.activeTargets[] | .health] | group_by(.) | map({health: .[0], count: length})'
# Expected output: [{"health":"up","count":7}]
```

#### Verify Liberty Metrics in Prometheus

```bash
# Query Liberty up status
curl -s 'http://192.168.68.82:9090/api/v1/query?query=up{job="liberty"}' | jq '.data.result[] | {instance: .metric.instance, value: .value[1]}'
# Expected output:
# {"instance":"192.168.68.86:9080","value":"1"}
# {"instance":"192.168.68.88:9080","value":"1"}

# Check JVM heap usage across Liberty servers (MicroProfile Metrics 5.0 naming)
curl -s 'http://192.168.68.82:9090/api/v1/query?query=memory_usedHeap_bytes{mp_scope="base"}' | jq '.data.result[] | {instance: .metric.instance, heap_bytes: .value[1]}'
```

### 4. Grafana Dashboard Access

#### Grafana Health Check

```bash
# API health check
curl -s http://192.168.68.82:3000/api/health
# Expected output: {"commit":"...","database":"ok","version":"..."}

# Check with HTTP status code
curl -s -o /dev/null -w "%{http_code}" http://192.168.68.82:3000/api/health
# Expected output: 200
```

#### Access Grafana UI

1. Open browser: `http://192.168.68.82:3000`
2. Login with credentials (see [CREDENTIAL_SETUP.md](./CREDENTIAL_SETUP.md))
3. Navigate to Dashboards > Liberty Performance

#### Verify Data Sources

```bash
# List configured data sources (requires authentication)
curl -s -u admin:PASSWORD http://192.168.68.82:3000/api/datasources | jq '.[].name'
# Expected output: "Prometheus"

# Test Prometheus data source connectivity
curl -s -u admin:PASSWORD http://192.168.68.82:3000/api/datasources/proxy/1/api/v1/query?query=up | jq '.status'
# Expected output: "success"
```

### 5. Jenkins Pipeline Test

#### Jenkins Health Check

```bash
# Basic connectivity test
curl -s -o /dev/null -w "%{http_code}" http://192.168.68.206:8080/login
# Expected output: 200

# Jenkins API status (requires authentication)
curl -s -u admin:API_TOKEN http://192.168.68.206:8080/api/json?pretty=true | jq '.mode'
# Expected output: "NORMAL"
```

#### Run Test Pipeline via UI

1. Access Jenkins: `http://192.168.68.206:8080`
2. Navigate to the "middleware-platform" job
3. Click "Build with Parameters"
4. Select:
   - ENVIRONMENT: `dev`
   - DEPLOY_TYPE: `full`
   - DRY_RUN: `true` (for testing without making changes)
5. Click "Build"
6. Monitor console output for successful completion

#### Trigger Pipeline via CLI

```bash
# Trigger a dry-run build (requires Jenkins API token)
curl -X POST -u admin:API_TOKEN \
  "http://192.168.68.206:8080/job/middleware-platform/buildWithParameters?ENVIRONMENT=dev&DEPLOY_TYPE=full&DRY_RUN=true"
# Expected: HTTP 201 Created

# Check last build status
curl -s -u admin:API_TOKEN \
  http://192.168.68.206:8080/job/middleware-platform/lastBuild/api/json | jq '{result: .result, duration: .duration}'
# Expected output: {"result":"SUCCESS","duration":...}
```

### 6. AWX Job Template Test

#### AWX Health Check

```bash
# Basic connectivity check
curl -s -o /dev/null -w "%{http_code}" http://192.168.68.205/api/v2/ping/
# Expected output: 200

# AWX API ping (returns version info)
curl -s http://192.168.68.205/api/v2/ping/ | jq '.version'
# Expected output: AWX version string (e.g., "21.10.0")
```

#### Verify AWX Configuration

```bash
# List job templates (requires authentication)
curl -s -u admin:PASSWORD http://192.168.68.205/api/v2/job_templates/ | jq '.results[].name'
# Expected output:
# "Deploy Liberty - Local"
# "Deploy Monitoring - Local"
# "Health Check - Local"

# Check inventory hosts
curl -s -u admin:PASSWORD http://192.168.68.205/api/v2/inventories/1/hosts/ | jq '.results[] | {name: .name, enabled: .enabled}'
```

#### Launch Test Job via API

```bash
# Launch Health Check job (read-only, safe to run anytime)
curl -s -X POST -u admin:PASSWORD \
  -H "Content-Type: application/json" \
  http://192.168.68.205/api/v2/job_templates/5/launch/ | jq '{id: .id, status: .status}'
# Expected output: {"id":123,"status":"pending"}

# Check job status (replace JOB_ID with actual ID from above)
JOB_ID=123
curl -s -u admin:PASSWORD \
  http://192.168.68.205/api/v2/jobs/${JOB_ID}/ | jq '{status: .status, failed: .failed}'
# Expected output: {"status":"successful","failed":false}
```

#### Launch Test Job via UI

1. Access AWX: `http://192.168.68.205`
2. Navigate to Templates > "Health Check - Local"
3. Click the rocket icon to launch
4. Monitor job output for successful completion

### 7. Quick Verification Script

Save this script as `verify-services.sh` to quickly check all services in one command:

```bash
#!/bin/bash
# Service Verification Script - Local Kubernetes Deployment
# Usage: ./verify-services.sh
# Returns: Exit code 0 if all services healthy, 1 if any failures

set -e

RED='[0;31m'
GREEN='[0;32m'
YELLOW='[1;33m'
NC='[0m'

LIBERTY_SERVERS=("192.168.68.86" "192.168.68.88")
PROMETHEUS_HOST="192.168.68.82"
GRAFANA_HOST="192.168.68.82"
JENKINS_HOST="192.168.68.206"
AWX_HOST="192.168.68.205"

PASSED=0
FAILED=0

check_endpoint() {
    local name="$1"; local url="$2"; local expected_code="${3:-200}"
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null || echo "000")
    if [ "$http_code" = "$expected_code" ]; then
        echo -e "${GREEN}[PASS]${NC} $name (HTTP $http_code)"; ((PASSED++))
    else
        echo -e "${RED}[FAIL]${NC} $name (HTTP $http_code, expected $expected_code)"; ((FAILED++))
    fi
}

check_health_json() {
    local name="$1"; local url="$2"
    response=$(curl -s --connect-timeout 5 "$url" 2>/dev/null || echo '{"status":"DOWN"}')
    status=$(echo "$response" | jq -r '.status' 2>/dev/null || echo "ERROR")
    if [ "$status" = "UP" ]; then
        echo -e "${GREEN}[PASS]${NC} $name (status: UP)"; ((PASSED++))
    else
        echo -e "${RED}[FAIL]${NC} $name (status: $status)"; ((FAILED++))
    fi
}

echo "=== Service Verification ==="
echo -e "${YELLOW}Liberty Servers${NC}"
for server in "${LIBERTY_SERVERS[@]}"; do
    check_health_json "Liberty $server - Ready" "http://$server:9080/health/ready"
    check_health_json "Liberty $server - Live" "http://$server:9080/health/live"
    check_endpoint "Liberty $server - Metrics" "http://$server:9080/metrics"
done

echo -e "${YELLOW}Monitoring${NC}"
check_endpoint "Prometheus" "http://$PROMETHEUS_HOST:9090/-/ready"
check_endpoint "Grafana" "http://$GRAFANA_HOST:3000/api/health"

echo -e "${YELLOW}CI/CD${NC}"
check_endpoint "Jenkins" "http://$JENKINS_HOST:8080/login"
check_endpoint "AWX" "http://$AWX_HOST/api/v2/ping/"

echo ""; echo "Passed: $PASSED | Failed: $FAILED"
[ $FAILED -eq 0 ] && echo -e "${GREEN}All healthy!${NC}" && exit 0
echo -e "${RED}Issues detected${NC}" && exit 1
```

### 8. End-to-End Verification Checklist

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | `curl http://192.168.68.86:9080/health/ready` | `{"status":"UP"}` |
| 2 | `curl http://192.168.68.88:9080/health/ready` | `{"status":"UP"}` |
| 3 | `curl http://192.168.68.82:9090/-/ready` | `Prometheus Server is Ready.` |
| 4 | Access `http://192.168.68.82:3000` | Grafana login page loads |
| 5 | Access `http://192.168.68.206:8080` | Jenkins login page loads |
| 6 | Access `http://192.168.68.205` | AWX login page loads |
| 7 | Query Prometheus targets API | All targets show `"health":"up"` |
| 8 | Run Health Check job in AWX | Job completes successfully |
| 9 | Trigger dry-run build in Jenkins | Pipeline completes without errors |

---

## Troubleshooting

This section covers common issues encountered when deploying to local Kubernetes clusters and how to diagnose and resolve them.

### 1. Pods Not Starting

#### ImagePullBackOff

**Symptoms:**
```bash
$ kubectl get pods -n liberty
NAME                          READY   STATUS             RESTARTS   AGE
liberty-app-7d8f9b6c4-x2k9m   0/1     ImagePullBackOff   0          5m
```

**Diagnosis:**
```bash
# Get detailed error message
kubectl describe pod liberty-app-7d8f9b6c4-x2k9m -n liberty | grep -A 10 "Events:"

# Check the exact image being pulled
kubectl get pod liberty-app-7d8f9b6c4-x2k9m -n liberty -o jsonpath='{.spec.containers[*].image}'
```

**Common Causes and Solutions:**

1. **Image does not exist or wrong tag:**
   ```bash
   # Verify image exists in registry
   podman search icr.io/appcafe/open-liberty

   # Check available tags
   skopeo list-tags docker://icr.io/appcafe/open-liberty
   ```

2. **Private registry authentication required:**
   ```bash
   # Create image pull secret
   kubectl create secret docker-registry regcred \
     --namespace=liberty \
     --docker-server=your-registry.example.com \
     --docker-username=your-username \
     --docker-password=your-password

   # Patch the deployment to use the secret
   kubectl patch deployment liberty-app -n liberty \
     -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"regcred"}]}}}}'
   ```

3. **Network issues reaching registry:**
   ```bash
   # Test connectivity from a debug pod
   kubectl run debug --rm -it --image=busybox --restart=Never -- wget -q -O- https://icr.io/v2/

   # Check DNS resolution
   kubectl run debug --rm -it --image=busybox --restart=Never -- nslookup icr.io
   ```

#### CrashLoopBackOff

**Symptoms:**
```bash
$ kubectl get pods -n liberty
NAME                          READY   STATUS             RESTARTS   AGE
liberty-app-7d8f9b6c4-x2k9m   0/1     CrashLoopBackOff   5          10m
```

**Diagnosis:**
```bash
# Check container logs
kubectl logs liberty-app-7d8f9b6c4-x2k9m -n liberty

# Check previous container logs (if restarted)
kubectl logs liberty-app-7d8f9b6c4-x2k9m -n liberty --previous

# Check events
kubectl describe pod liberty-app-7d8f9b6c4-x2k9m -n liberty
```

**Common Causes and Solutions:**

1. **Application startup failure:**
   ```bash
   # Check Liberty server logs
   kubectl logs liberty-app-7d8f9b6c4-x2k9m -n liberty | grep -i error

   # Common Liberty issues:
   # - Missing features in server.xml
   # - Invalid server.xml configuration
   # - Port conflicts
   ```

2. **Missing ConfigMap or Secret:**
   ```bash
   # Verify ConfigMap exists
   kubectl get configmap liberty-config -n liberty

   # Verify Secret exists
   kubectl get secret liberty-secrets -n liberty

   # Create missing resources
   kubectl create configmap liberty-config \
     --namespace=liberty \
     --from-literal=db.host='postgres-service'
   ```

3. **Health probe failures:**
   ```bash
   # Check probe configuration
   kubectl get deployment liberty-app -n liberty -o yaml | grep -A 10 "livenessProbe:"

   # Temporarily disable probes for debugging
   kubectl patch deployment liberty-app -n liberty --type='json' \
     -p='[{"op": "remove", "path": "/spec/template/spec/containers/0/livenessProbe"}]'
   ```

4. **Resource constraints (OOMKilled):**
   ```bash
   # Check if pod was OOMKilled
   kubectl describe pod liberty-app-7d8f9b6c4-x2k9m -n liberty | grep -i oom

   # Increase memory limits
   kubectl patch deployment liberty-app -n liberty --type='json' \
     -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "4Gi"}]'
   ```

---

### 2. LoadBalancer Pending (MetalLB Issues)

**Symptoms:**
```bash
$ kubectl get svc -n liberty
NAME              TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
liberty-service   LoadBalancer   10.96.45.123    <pending>     9080:31234/TCP   10m
```

**Diagnosis:**
```bash
# Check if MetalLB is installed and running
kubectl get pods -n metallb-system

# Check MetalLB speaker logs
kubectl logs -n metallb-system -l app=metallb,component=speaker

# Check MetalLB controller logs
kubectl logs -n metallb-system -l app=metallb,component=controller

# Verify IPAddressPool configuration
kubectl get ipaddresspools -n metallb-system -o yaml
```

**Common Causes and Solutions:**

1. **MetalLB not installed:**
   ```bash
   # Install MetalLB
   kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

   # Wait for MetalLB pods to be ready
   kubectl wait --namespace metallb-system \
     --for=condition=ready pod \
     --selector=app=metallb \
     --timeout=90s
   ```

2. **Missing IPAddressPool configuration:**
   ```bash
   # Create IPAddressPool
   cat <<EOF | kubectl apply -f -
   apiVersion: metallb.io/v1beta1
   kind: IPAddressPool
   metadata:
     name: default-pool
     namespace: metallb-system
   spec:
     addresses:
     - 192.168.68.200-192.168.68.250
   ---
   apiVersion: metallb.io/v1beta1
   kind: L2Advertisement
   metadata:
     name: default
     namespace: metallb-system
   spec:
     ipAddressPools:
     - default-pool
   EOF
   ```

3. **IP address already in use:**
   ```bash
   # Check which service has the IP
   kubectl get svc -A -o wide | grep "192.168.68.205"

   # Ping the IP from outside the cluster to check if it responds
   ping -c 3 192.168.68.205

   # Use a different IP or release the existing one
   kubectl annotate svc awx-lb -n awx metallb.universe.tf/loadBalancerIPs=192.168.68.207 --overwrite
   ```

4. **MetalLB speaker cannot ARP (network isolation):**
   ```bash
   # Ensure speaker pods can send ARP requests
   # Check if nodes have the correct interface
   kubectl exec -n metallb-system -it $(kubectl get pod -n metallb-system -l app=metallb,component=speaker -o jsonpath='{.items[0].metadata.name}') -- ip addr
   ```

---

### 3. Services Not Accessible

**Symptoms:**
- Cannot reach services from outside the cluster
- Connection timeouts or refused connections

**Diagnosis:**
```bash
# Test connectivity from within the cluster
kubectl run debug --rm -it --image=busybox --restart=Never -- wget -q -O- http://liberty-service.liberty.svc.cluster.local:9080/health/ready

# Test connectivity from a node
ssh user@k8s-node "curl -v http://192.168.68.210:9080/health/ready"

# Check if service endpoints exist
kubectl get endpoints liberty-service -n liberty
```

**Common Causes and Solutions:**

1. **Firewall blocking traffic:**
   ```bash
   # Check firewall status on nodes
   sudo firewall-cmd --state

   # Allow traffic to LoadBalancer IPs (on each node)
   sudo firewall-cmd --permanent --add-port=9080/tcp
   sudo firewall-cmd --permanent --add-port=9443/tcp
   sudo firewall-cmd --permanent --add-port=80/tcp
   sudo firewall-cmd --permanent --add-port=443/tcp
   sudo firewall-cmd --reload

   # Or with iptables
   sudo iptables -A INPUT -p tcp --dport 9080 -j ACCEPT
   sudo iptables -A INPUT -p tcp --dport 9443 -j ACCEPT
   ```

2. **Kube-proxy issues:**
   ```bash
   # Check kube-proxy logs
   kubectl logs -n kube-system -l k8s-app=kube-proxy

   # Restart kube-proxy
   kubectl rollout restart daemonset kube-proxy -n kube-system
   ```

3. **Service selector mismatch:**
   ```bash
   # Check service selectors
   kubectl get svc liberty-service -n liberty -o jsonpath='{.spec.selector}'

   # Compare with pod labels
   kubectl get pods -n liberty --show-labels

   # Fix selector if needed
   kubectl patch svc liberty-service -n liberty --type='json' \
     -p='[{"op": "replace", "path": "/spec/selector/app", "value": "liberty"}]'
   ```

4. **No endpoints available:**
   ```bash
   # If endpoints are empty, pods are not matching the service selector
   kubectl get endpoints liberty-service -n liberty

   # Check pod readiness
   kubectl get pods -n liberty -o wide
   ```

5. **Client machine routing:**
   ```bash
   # Ensure client can reach the LoadBalancer network
   ip route | grep 192.168.68

   # Add route if missing
   sudo ip route add 192.168.68.0/24 via <gateway-ip>
   ```

---

### 4. Prometheus Not Scraping Targets

**Symptoms:**
- Targets showing as DOWN in Prometheus UI
- Missing metrics in Grafana dashboards

**Diagnosis:**
```bash
# Access Prometheus UI and check targets
curl http://192.168.68.201:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health, lastError: .lastError}'

# Check Prometheus configuration
kubectl exec -n monitoring prometheus-prometheus-kube-prometheus-prometheus-0 -- cat /etc/prometheus/prometheus.yml

# Check Prometheus logs
kubectl logs -n monitoring prometheus-prometheus-kube-prometheus-prometheus-0
```

**Common Causes and Solutions:**

1. **ServiceMonitor not configured correctly:**
   ```bash
   # Check if ServiceMonitor exists
   kubectl get servicemonitor -n liberty

   # Create ServiceMonitor for Liberty
   cat <<EOF | kubectl apply -f -
   apiVersion: monitoring.coreos.com/v1
   kind: ServiceMonitor
   metadata:
     name: liberty-monitor
     namespace: liberty
     labels:
       release: prometheus
   spec:
     selector:
       matchLabels:
         app: liberty
     endpoints:
     - port: http
       path: /metrics
       interval: 15s
   EOF
   ```

2. **Network policy blocking scrape:**
   ```bash
   # Check network policies
   kubectl get networkpolicy -A

   # Allow Prometheus to scrape Liberty pods
   cat <<EOF | kubectl apply -f -
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: allow-prometheus-scrape
     namespace: liberty
   spec:
     podSelector:
       matchLabels:
         app: liberty
     ingress:
     - from:
       - namespaceSelector:
           matchLabels:
             name: monitoring
       ports:
       - protocol: TCP
         port: 9080
   EOF
   ```

3. **Target endpoint not exposing metrics:**
   ```bash
   # Test metrics endpoint directly
   kubectl exec -n liberty deploy/liberty-app -- curl -s localhost:9080/metrics | head -20

   # If metrics endpoint returns 404, check server.xml has mpMetrics feature
   # Required features: mpMetrics-5.0, monitor-1.0
   ```

4. **Wrong scrape configuration:**
   ```bash
   # Check static config targets
   kubectl get configmap prometheus-prometheus-kube-prometheus-prometheus -n monitoring -o yaml | grep -A 20 "scrape_configs"

   # Verify target IPs and ports are correct
   # Liberty default: port 9080, path /metrics
   ```

5. **Prometheus pod cannot reach target network:**
   ```bash
   # Test connectivity from Prometheus pod
   kubectl exec -n monitoring prometheus-prometheus-kube-prometheus-prometheus-0 -- wget -q -O- http://192.168.68.88:9080/metrics | head -5
   ```

---

### 5. AWX Operator Not Ready

**Symptoms:**
- AWX pods not starting
- AWX operator in CrashLoopBackOff

**Diagnosis:**
```bash
# Check AWX operator status
kubectl get pods -n awx -l app.kubernetes.io/name=awx-operator

# Check AWX operator logs
kubectl logs -n awx -l app.kubernetes.io/name=awx-operator

# Check AWX CR status
kubectl get awx -n awx -o yaml

# Check all AWX-related resources
kubectl get all -n awx
```

**Common Causes and Solutions:**

1. **Missing admin password secret:**
   ```bash
   # Check if secret exists
   kubectl get secret awx-admin-password -n awx

   # Create the secret
   kubectl create secret generic awx-admin-password \
     --namespace=awx \
     --from-literal=password='YourSecurePassword123!'
   ```

2. **Storage class not available:**
   ```bash
   # Check storage classes
   kubectl get storageclass

   # Check PVC status
   kubectl get pvc -n awx

   # If PVC is pending, check events
   kubectl describe pvc -n awx

   # Use a different storage class
   kubectl patch awx awx -n awx --type='json' \
     -p='[{"op": "replace", "path": "/spec/postgres_storage_class", "value": "local-path"}]'
   ```

3. **Resource constraints:**
   ```bash
   # Check node resources
   kubectl describe nodes | grep -A 5 "Allocated resources"

   # Reduce AWX resource requests
   kubectl patch awx awx -n awx --type='json' \
     -p='[{"op": "replace", "path": "/spec/web_resource_requirements/requests/memory", "value": "512Mi"}]'
   ```

4. **PostgreSQL pod failing:**
   ```bash
   # Check PostgreSQL pod
   kubectl get pods -n awx -l app.kubernetes.io/component=database

   # Check PostgreSQL logs
   kubectl logs -n awx -l app.kubernetes.io/component=database

   # Common fix: delete PVC and let it recreate
   kubectl delete pvc postgres-15-awx-postgres-15-0 -n awx
   kubectl delete pod awx-postgres-15-0 -n awx
   ```

5. **AWX web pod failing:**
   ```bash
   # Check AWX web pod logs
   kubectl logs -n awx -l app.kubernetes.io/name=awx-web

   # Check AWX task pod logs
   kubectl logs -n awx -l app.kubernetes.io/name=awx-task

   # Restart AWX pods
   kubectl rollout restart deployment awx-web -n awx
   kubectl rollout restart deployment awx-task -n awx
   ```

---

### 6. Jenkins Agents Not Connecting

**Symptoms:**
- Jenkins builds stuck in queue
- Agent shows as offline in Jenkins UI
- "Waiting for next available executor" messages

**Diagnosis:**
```bash
# Check Jenkins controller logs
kubectl logs -n jenkins -l app.kubernetes.io/name=jenkins

# Check if agent pods are being created
kubectl get pods -n jenkins

# Check Jenkins agent pod logs (if pod exists)
kubectl logs -n jenkins -l jenkins/label=jenkins-agent
```

**Common Causes and Solutions:**

1. **JNLP port not accessible:**
   ```bash
   # Check if JNLP service exists
   kubectl get svc -n jenkins | grep agent

   # Expose JNLP port if not exposed
   kubectl expose deployment jenkins \
     --name=jenkins-agent \
     --port=50000 \
     --target-port=50000 \
     --namespace=jenkins
   ```

2. **ServiceAccount permissions:**
   ```bash
   # Check Jenkins ServiceAccount
   kubectl get serviceaccount jenkins -n jenkins

   # Create ClusterRoleBinding for agent management
   cat <<EOF | kubectl apply -f -
   apiVersion: rbac.authorization.k8s.io/v1
   kind: ClusterRoleBinding
   metadata:
     name: jenkins-admin
   roleRef:
     apiGroup: rbac.authorization.k8s.io
     kind: ClusterRole
     name: cluster-admin
   subjects:
   - kind: ServiceAccount
     name: jenkins
     namespace: jenkins
   EOF
   ```

3. **Kubernetes cloud not configured in Jenkins:**
   ```bash
   # Access Jenkins UI and navigate to:
   # Manage Jenkins -> Nodes and Clouds -> Configure Clouds

   # Verify Kubernetes URL (should be https://kubernetes.default.svc)
   # Verify Jenkins URL (should be http://jenkins.jenkins.svc:8080)
   # Verify Jenkins tunnel (should be jenkins-agent.jenkins.svc:50000)
   ```

4. **Agent image pull issues:**
   ```bash
   # Check agent pod events
   kubectl describe pod -n jenkins -l jenkins/label=jenkins-agent

   # Verify agent image is accessible
   kubectl run test-agent --rm -it --image=jenkins/inbound-agent:latest --restart=Never -- echo "success"
   ```

5. **Network policies blocking agent communication:**
   ```bash
   # Allow agent to controller communication
   cat <<EOF | kubectl apply -f -
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: allow-jenkins-agent
     namespace: jenkins
   spec:
     podSelector:
       matchLabels:
         app.kubernetes.io/name: jenkins
     ingress:
     - from:
       - podSelector:
           matchLabels:
             jenkins/label: jenkins-agent
       ports:
       - protocol: TCP
         port: 50000
   EOF
   ```

---

### 7. Useful kubectl Debugging Commands

#### Pod Inspection
```bash
# Get all pods with wide output (includes node and IP)
kubectl get pods -A -o wide

# Get pods with specific status
kubectl get pods -A --field-selector=status.phase!=Running

# Get detailed pod information
kubectl describe pod <pod-name> -n <namespace>

# Get pod YAML (useful for seeing resolved values)
kubectl get pod <pod-name> -n <namespace> -o yaml

# Watch pods in real-time
kubectl get pods -n <namespace> -w
```

#### Log Analysis
```bash
# Get current logs
kubectl logs <pod-name> -n <namespace>

# Get logs from previous container instance
kubectl logs <pod-name> -n <namespace> --previous

# Follow logs in real-time
kubectl logs -f <pod-name> -n <namespace>

# Get logs from all containers in a pod
kubectl logs <pod-name> -n <namespace> --all-containers

# Get logs from all pods matching a label
kubectl logs -n <namespace> -l app=liberty --all-containers

# Get logs with timestamps
kubectl logs <pod-name> -n <namespace> --timestamps

# Get last N lines
kubectl logs <pod-name> -n <namespace> --tail=100
```

#### Interactive Debugging
```bash
# Execute command in running container
kubectl exec -it <pod-name> -n <namespace> -- /bin/bash

# Execute command in specific container (multi-container pod)
kubectl exec -it <pod-name> -n <namespace> -c <container-name> -- /bin/bash

# Run a debug pod with network tools
kubectl run debug --rm -it --image=nicolaka/netshoot --restart=Never -- bash

# Copy files from pod
kubectl cp <namespace>/<pod-name>:/path/to/file ./local-file

# Port forward for local testing
kubectl port-forward <pod-name> -n <namespace> 8080:9080
```

#### Resource Inspection
```bash
# Get all resources in a namespace
kubectl get all -n <namespace>

# Get events sorted by time
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Get events for a specific pod
kubectl get events -n <namespace> --field-selector involvedObject.name=<pod-name>

# Check resource usage
kubectl top pods -n <namespace>
kubectl top nodes

# Check resource quotas
kubectl describe resourcequota -n <namespace>
```

#### Network Debugging
```bash
# Test DNS resolution
kubectl run debug --rm -it --image=busybox --restart=Never -- nslookup kubernetes.default

# Test service connectivity
kubectl run debug --rm -it --image=busybox --restart=Never -- wget -q -O- http://liberty-service.liberty.svc:9080/health/ready

# Check endpoints
kubectl get endpoints -n <namespace>

# Check network policies
kubectl get networkpolicy -A
```

#### Cluster Health
```bash
# Check node status
kubectl get nodes -o wide

# Check component status
kubectl get componentstatuses

# Check cluster info
kubectl cluster-info

# Check API server health
kubectl get --raw='/healthz'

# Check etcd health (if accessible)
kubectl get --raw='/healthz/etcd'
```

---

### 8. How to Reset/Reinstall Components

#### Reset Liberty Deployment
```bash
# Delete and recreate Liberty resources
kubectl delete -f kubernetes/base/liberty-deployment.yaml -n liberty
kubectl delete pvc -n liberty --all
kubectl delete configmap liberty-config -n liberty
kubectl delete secret liberty-secrets -n liberty

# Recreate namespace (clean slate)
kubectl delete namespace liberty
kubectl create namespace liberty

# Redeploy
kubectl create configmap liberty-config --namespace=liberty --from-literal=db.host='postgres-service'
kubectl create secret generic liberty-secrets --namespace=liberty --from-literal=db.password='your-password'
kubectl apply -f kubernetes/base/liberty-deployment.yaml -n liberty
```

#### Reset Monitoring Stack
```bash
# Uninstall Prometheus stack
helm uninstall prometheus -n monitoring

# Delete PVCs to remove all data
kubectl delete pvc -n monitoring --all

# Delete namespace
kubectl delete namespace monitoring

# Reinstall
kubectl create namespace monitoring
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.service.type=LoadBalancer \
  --set prometheus.service.loadBalancerIP=192.168.68.201 \
  --set grafana.service.type=LoadBalancer \
  --set grafana.service.loadBalancerIP=192.168.68.202
```

#### Reset AWX
```bash
# Delete AWX CR (this deletes all AWX pods but preserves data)
kubectl delete awx awx -n awx

# Delete everything including data
kubectl delete namespace awx

# Reinstall operator
kubectl apply -f https://raw.githubusercontent.com/ansible/awx-operator/devel/deploy/awx-operator.yaml

# Wait for operator to be ready
kubectl wait --namespace awx \
  --for=condition=ready pod \
  --selector=control-plane=controller-manager \
  --timeout=120s

# Create secret and deploy AWX
kubectl create secret generic awx-admin-password --namespace=awx --from-literal=password='YourSecurePassword123!'
kubectl apply -f awx/awx-deployment.yaml
```

#### Reset Jenkins
```bash
# Uninstall Jenkins
helm uninstall jenkins -n jenkins

# Delete PVCs
kubectl delete pvc -n jenkins --all

# Delete namespace
kubectl delete namespace jenkins

# Reinstall
kubectl create namespace jenkins
helm install jenkins jenkins/jenkins \
  --namespace jenkins \
  --set controller.serviceType=LoadBalancer \
  --set controller.loadBalancerIP=192.168.68.206
```

#### Reset MetalLB
```bash
# Delete MetalLB
kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

# Wait for resources to be deleted
sleep 30

# Reinstall MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

# Wait for pods
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=90s

# Reconfigure IP pool
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.68.200-192.168.68.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
EOF
```

#### Full Cluster Reset (Nuclear Option)
```bash
# WARNING: This deletes ALL workloads and data

# Delete all non-system namespaces
kubectl get namespaces -o name | grep -v -E '^namespace/(default|kube-system|kube-public|kube-node-lease)$' | xargs kubectl delete

# Reset kubeadm cluster (if using kubeadm)
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d
sudo rm -rf $HOME/.kube/config

# Reinitialize cluster
sudo kubeadm init --pod-network-cidr=10.244.0.0/16
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install CNI (Flannel example)
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
```

---

## Quick Reference: Common Error Messages

| Error Message | Likely Cause | Quick Fix |
|--------------|--------------|-----------|
| `ImagePullBackOff` | Image not found or auth required | Check image name, create pull secret |
| `CrashLoopBackOff` | Application crashing on startup | Check logs with `kubectl logs --previous` |
| `Pending` (Pod) | No node with sufficient resources | Check node resources, adjust requests |
| `Pending` (PVC) | No storage class or capacity | Check storage class, PV availability |
| `<pending>` (External-IP) | MetalLB not configured | Install MetalLB, create IPAddressPool |
| `connection refused` | Service/pod not running | Check pod status, service endpoints |
| `no endpoints available` | No pods match service selector | Verify labels match selector |
| `context deadline exceeded` | Timeout reaching target | Check network connectivity, firewall |

---

## Quick Reference

### Service URLs

| Service | IP Address | Port | URL |
|---------|------------|------|-----|
| **Liberty Server 1** | 192.168.68.86 | 9080/9443 | http://192.168.68.86:9080 |
| **Liberty Server 2** | 192.168.68.88 | 9080/9443 | http://192.168.68.88:9080 |
| **NGINX Ingress** | 192.168.68.200 | 80/443 | http://192.168.68.200 |
| **Prometheus** | 192.168.68.201 | 9090 | http://192.168.68.201:9090 |
| **Grafana** | 192.168.68.202 | 3000 | http://192.168.68.202:3000 |
| **AlertManager** | 192.168.68.203 | 9093 | http://192.168.68.203:9093 |
| **ArgoCD** | 192.168.68.204 | 443 | https://192.168.68.204 |
| **AWX** | 192.168.68.205 | 80 | http://192.168.68.205 |
| **Jenkins** | 192.168.68.206 | 8080 | http://192.168.68.206:8080 |
| **Liberty Controller** | 192.168.68.82 | 9080 | http://192.168.68.82:9080 |

#### Liberty Endpoints

| Endpoint | URL |
|----------|-----|
| Health (Ready) | http://192.168.68.86:9080/health/ready |
| Health (Live) | http://192.168.68.86:9080/health/live |
| Health (Started) | http://192.168.68.86:9080/health/started |
| Metrics | http://192.168.68.86:9080/metrics |
| Admin Console | https://192.168.68.86:9443/adminCenter |

---

### Credential Retrieval Commands

#### AWX

```bash
# Get AWX admin password
kubectl get secret awx-admin-password -n awx \
  -o jsonpath='{.data.password}' | base64 -d && echo

# Username: admin
```

#### Jenkins

```bash
# Get Jenkins admin password
kubectl get secret jenkins-admin-secret -n jenkins \
  -o jsonpath='{.data.jenkins-admin-password}' | base64 -d && echo

# Username: admin
```

#### Grafana

```bash
# Get Grafana admin password (kube-prometheus-stack)
kubectl get secret prometheus-grafana -n monitoring \
  -o jsonpath='{.data.admin-password}' | base64 -d && echo

# Username: admin
```

#### ArgoCD

```bash
# Get ArgoCD initial admin password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d && echo

# Username: admin
```

#### All Credentials Summary Script

```bash
#!/bin/bash
echo "=== Credential Summary ==="
echo ""
echo "AWX (http://192.168.68.205)"
echo "  Username: admin"
echo -n "  Password: "
kubectl get secret awx-admin-password -n awx -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "(not set)"
echo ""
echo ""
echo "Jenkins (http://192.168.68.206:8080)"
echo "  Username: admin"
echo -n "  Password: "
kubectl get secret jenkins-admin-secret -n jenkins -o jsonpath='{.data.jenkins-admin-password}' 2>/dev/null | base64 -d || echo "(not set)"
echo ""
echo ""
echo "Grafana (http://192.168.68.202:3000)"
echo "  Username: admin"
echo -n "  Password: "
kubectl get secret prometheus-grafana -n monitoring -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d || echo "(not set)"
echo ""
echo ""
echo "ArgoCD (https://192.168.68.204)"
echo "  Username: admin"
echo -n "  Password: "
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "(not set)"
echo ""
```

---

### Common kubectl Commands Cheatsheet

#### Pod Management

```bash
# List all pods across namespaces
kubectl get pods -A

# List pods in specific namespace
kubectl get pods -n liberty
kubectl get pods -n jenkins
kubectl get pods -n awx
kubectl get pods -n monitoring

# Watch pod status (real-time)
kubectl get pods -n liberty -w

# Get pod details
kubectl describe pod <pod-name> -n <namespace>

# View pod logs
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> -f          # Follow logs
kubectl logs <pod-name> -n <namespace> --previous  # Previous container logs

# Execute command in pod
kubectl exec -it <pod-name> -n <namespace> -- /bin/bash
kubectl exec -it <pod-name> -n <namespace> -- cat /config/server.xml
```

#### Service Management

```bash
# List all services
kubectl get svc -A

# Get LoadBalancer IPs
kubectl get svc -A | grep LoadBalancer

# Get service endpoints
kubectl get endpoints -n liberty
```

#### Deployment Management

```bash
# List deployments
kubectl get deployments -n liberty

# Scale deployment
kubectl scale deployment liberty-app -n liberty --replicas=3

# Rollout status
kubectl rollout status deployment/liberty-app -n liberty

# Rollout history
kubectl rollout history deployment/liberty-app -n liberty

# Rollback deployment
kubectl rollout undo deployment/liberty-app -n liberty
kubectl rollout undo deployment/liberty-app -n liberty --to-revision=2

# Restart deployment (rolling restart)
kubectl rollout restart deployment/liberty-app -n liberty
```

#### Resource Inspection

```bash
# Get all resources in namespace
kubectl get all -n liberty

# Get ConfigMaps
kubectl get configmap -n liberty
kubectl describe configmap liberty-config -n liberty

# Get Secrets (metadata only)
kubectl get secrets -n jenkins

# Get PersistentVolumeClaims
kubectl get pvc -n jenkins

# Get HorizontalPodAutoscaler
kubectl get hpa -n liberty
```

---

### Helm Commands for Upgrades

#### Repository Management

```bash
# Add Helm repositories
helm repo add jenkins https://charts.jenkins.io
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add awx-operator https://ansible.github.io/awx-operator/
helm repo add bitnami https://charts.bitnami.com/bitnami

# Update repositories
helm repo update

# List repositories
helm repo list
```

#### Release Management

```bash
# List installed releases
helm list -A

# Get release status
helm status jenkins -n jenkins

# Get release values
helm get values jenkins -n jenkins
helm get values jenkins -n jenkins --all  # Include defaults

# Get release manifest
helm get manifest jenkins -n jenkins
```

#### Upgrade Commands

```bash
# Upgrade Jenkins
helm upgrade jenkins jenkins/jenkins \
  --namespace jenkins \
  -f ci-cd/jenkins/kubernetes/values.yaml \
  --wait --timeout 15m

# Upgrade Prometheus stack
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --reuse-values \
  --wait --timeout 10m

# Upgrade AWX Operator
helm upgrade awx-operator awx-operator/awx-operator \
  --namespace awx \
  --wait --timeout 5m

# Dry-run upgrade (preview changes)
helm upgrade jenkins jenkins/jenkins \
  --namespace jenkins \
  -f ci-cd/jenkins/kubernetes/values.yaml \
  --dry-run
```

#### Rollback

```bash
# View release history
helm history jenkins -n jenkins

# Rollback to previous release
helm rollback jenkins -n jenkins

# Rollback to specific revision
helm rollback jenkins 2 -n jenkins
```

---

### Full Deployment Command Sequence

Copy and paste this entire block to deploy all services from scratch:

```bash
#!/bin/bash
set -e

echo "=== Middleware Automation Platform - Local K8s Deployment ==="
echo ""

# 1. Add Helm repositories
echo "[1/8] Adding Helm repositories..."
helm repo add jenkins https://charts.jenkins.io
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add awx-operator https://ansible.github.io/awx-operator/
helm repo update

# 2. Create namespaces
echo "[2/8] Creating namespaces..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace awx --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace jenkins --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace liberty --dry-run=client -o yaml | kubectl apply -f -

# 3. Create secrets
echo "[3/8] Creating secrets..."

# AWX admin password
AWX_PASS=$(openssl rand -base64 24)
kubectl create secret generic awx-admin-password \
  --namespace=awx \
  --from-literal=password="$AWX_PASS" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "AWX Admin Password: $AWX_PASS"

# Jenkins admin password
JENKINS_PASS=$(openssl rand -base64 24)
kubectl create secret generic jenkins-admin-secret \
  --namespace=jenkins \
  --from-literal=jenkins-admin-password="$JENKINS_PASS" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "Jenkins Admin Password: $JENKINS_PASS"

# 4. Deploy Prometheus/Grafana stack
echo "[4/8] Deploying monitoring stack..."
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.service.type=LoadBalancer \
  --set prometheus.service.loadBalancerIP=192.168.68.201 \
  --set grafana.service.type=LoadBalancer \
  --set grafana.service.loadBalancerIP=192.168.68.202 \
  --set alertmanager.service.type=LoadBalancer \
  --set alertmanager.service.loadBalancerIP=192.168.68.203 \
  --wait --timeout 10m

# 5. Deploy AWX Operator
echo "[5/8] Deploying AWX Operator..."
helm upgrade --install awx-operator awx-operator/awx-operator \
  --namespace awx \
  --wait --timeout 5m

# 6. Deploy AWX instance
echo "[6/8] Deploying AWX instance..."
kubectl apply -f awx/awx-deployment.yaml
echo "Waiting for AWX to be ready (this may take several minutes)..."
sleep 30
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=awx-web -n awx --timeout=600s || true

# 7. Deploy Jenkins
echo "[7/8] Deploying Jenkins..."
helm upgrade --install jenkins jenkins/jenkins \
  --namespace jenkins \
  -f ci-cd/jenkins/kubernetes/values.yaml \
  --wait --timeout 15m

# 8. Deploy Liberty application
echo "[8/8] Deploying Liberty application..."
kubectl create configmap liberty-config \
  --namespace=liberty \
  --from-file=server.xml=containers/liberty/config/server.xml \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f kubernetes/base/liberty-deployment.yaml -n liberty

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Service URLs:"
echo "  Prometheus:   http://192.168.68.201:9090"
echo "  Grafana:      http://192.168.68.202:3000"
echo "  AlertManager: http://192.168.68.203:9093"
echo "  AWX:          http://192.168.68.205"
echo "  Jenkins:      http://192.168.68.206:8080"
echo ""
echo "Credentials saved above. Run the credential retrieval commands to view them again."
```

---

### Teardown / Cleanup Commands

#### Remove Individual Services

```bash
# Remove Jenkins
helm uninstall jenkins -n jenkins
kubectl delete pvc -n jenkins --all

# Remove AWX
kubectl delete -f awx/awx-deployment.yaml
helm uninstall awx-operator -n awx

# Remove Prometheus stack
helm uninstall prometheus -n monitoring

# Remove Liberty
kubectl delete -f kubernetes/base/liberty-deployment.yaml -n liberty
kubectl delete configmap liberty-config -n liberty
kubectl delete secret liberty-secrets -n liberty
```

#### Remove All Services (Full Teardown)

```bash
#!/bin/bash
set -e

echo "=== Removing all Middleware Platform services ==="

# Uninstall Helm releases
echo "Removing Helm releases..."
helm uninstall jenkins -n jenkins 2>/dev/null || true
helm uninstall awx-operator -n awx 2>/dev/null || true
helm uninstall prometheus -n monitoring 2>/dev/null || true

# Remove AWX instance
echo "Removing AWX instance..."
kubectl delete -f awx/awx-deployment.yaml 2>/dev/null || true

# Remove Liberty
echo "Removing Liberty..."
kubectl delete -f kubernetes/base/liberty-deployment.yaml -n liberty 2>/dev/null || true

# Clean up PVCs
echo "Cleaning up PersistentVolumeClaims..."
kubectl delete pvc -n jenkins --all 2>/dev/null || true
kubectl delete pvc -n awx --all 2>/dev/null || true
kubectl delete pvc -n monitoring --all 2>/dev/null || true
kubectl delete pvc -n liberty --all 2>/dev/null || true

# Remove namespaces (this also deletes remaining resources)
echo "Removing namespaces..."
kubectl delete namespace jenkins --wait=false 2>/dev/null || true
kubectl delete namespace awx --wait=false 2>/dev/null || true
kubectl delete namespace monitoring --wait=false 2>/dev/null || true
kubectl delete namespace liberty --wait=false 2>/dev/null || true

echo ""
echo "=== Cleanup Complete ==="
echo "Note: Namespaces may take a few minutes to fully terminate."
echo "Run 'kubectl get ns' to check status."
```

#### Force Delete Stuck Namespace

```bash
# If a namespace is stuck in Terminating state
NAMESPACE=awx
kubectl get namespace $NAMESPACE -o json | \
  jq '.spec.finalizers = []' | \
  kubectl replace --raw "/api/v1/namespaces/$NAMESPACE/finalize" -f -
```

---

### Health Check Commands

```bash
#!/bin/bash
# Quick health check for all services

echo "=== Liberty Health ==="
curl -s http://192.168.68.86:9080/health/ready | jq . 2>/dev/null || echo "Liberty 1: UNREACHABLE"
curl -s http://192.168.68.88:9080/health/ready | jq . 2>/dev/null || echo "Liberty 2: UNREACHABLE"

echo ""
echo "=== Prometheus Health ==="
curl -s http://192.168.68.201:9090/-/ready && echo " OK" || echo "UNREACHABLE"

echo ""
echo "=== Grafana Health ==="
curl -s http://192.168.68.202:3000/api/health | jq . 2>/dev/null || echo "UNREACHABLE"

echo ""
echo "=== AWX Health ==="
curl -s -o /dev/null -w "%{http_code}" http://192.168.68.205/api/v2/ping/ && echo " OK" || echo "UNREACHABLE"

echo ""
echo "=== Jenkins Health ==="
curl -s -o /dev/null -w "%{http_code}" http://192.168.68.206:8080/login && echo " OK" || echo "UNREACHABLE"
```

---

### Related Documentation

| Document | Description |
|----------|-------------|
| [CREDENTIAL_SETUP.md](./CREDENTIAL_SETUP.md) | Complete credential configuration for all services |
| [README.md](../README.md) | Project overview, quick start, and AWS deployment guide |
| [HYBRID_ARCHITECTURE.md](./architecture/HYBRID_ARCHITECTURE.md) | Detailed local vs AWS architecture comparison |
| [Jenkins Kubernetes README](../ci-cd/jenkins/kubernetes/README.md) | Jenkins Helm deployment details |
| [terraform-aws.md](./troubleshooting/terraform-aws.md) | AWS/Terraform troubleshooting guide |
| [ecs-migration-plan.md](./plans/ecs-migration-plan.md) | ECS Fargate migration documentation |

### External Resources

| Resource | URL |
|----------|-----|
| Open Liberty Documentation | https://openliberty.io/docs/ |
| Kubernetes Documentation | https://kubernetes.io/docs/home/ |
| Helm Documentation | https://helm.sh/docs/ |
| AWX Documentation | https://ansible.readthedocs.io/projects/awx/en/latest/ |
| Jenkins Helm Chart | https://github.com/jenkinsci/helm-charts |
| Prometheus Operator | https://prometheus-operator.dev/ |
| MetalLB Documentation | https://metallb.universe.tf/ |
