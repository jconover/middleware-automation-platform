# CI/CD Pipeline Guide

This guide covers the Jenkins CI/CD pipeline for the Enterprise Middleware Automation Platform, including configuration, usage, and troubleshooting.

## Table of Contents

- [Pipeline Overview](#pipeline-overview)
- [Quick Start: Your First Build](#quick-start-your-first-build)
- [Pipeline Parameters](#pipeline-parameters)
- [Pipeline Stages Explained](#pipeline-stages-explained)
- [Deployment Targets](#deployment-targets)
- [Troubleshooting Common Failures](#troubleshooting-common-failures)
- [Customization](#customization)

---

## Pipeline Overview

### High-Level Flow

```
+------------------+     +------------------+     +------------------+
|   Code Commit    | --> |  Jenkins Build   | --> |    Deployment    |
|   (Git Push)     |     |  (Kubernetes)    |     |  (ECS/EC2/K8s)   |
+------------------+     +------------------+     +------------------+
                                 |
                                 v
                    +------------------------+
                    |     Pipeline Stages    |
                    +------------------------+
                    | 1. Validate Parameters |  ~1 min
                    | 2. Checkout            |  ~1 min
                    | 3. Build Application   |  ~5 min
                    | 4. Unit Tests          |  ~3 min
                    | 5. Code Quality        |  ~3 min
                    | 6. Build Container     |  ~5 min
                    | 7. Security Scan       |  ~3 min
                    | 8. Push to Registry    |  ~2 min
                    | 9. Deploy              |  ~5 min
                    | 10. Health Check       |  ~5 min
                    +------------------------+
                         Total: ~25-30 min
```

### Build Triggers

The pipeline can be triggered by:

| Trigger | Description |
|---------|-------------|
| **Manual** | Click "Build with Parameters" in Jenkins UI |
| **Git Webhook** | Automatic trigger on push to repository |
| **Scheduled** | Cron-based scheduling (configure in Jenkins job) |
| **API** | POST to Jenkins REST API with parameters |

### Estimated Stage Duration

| Stage | Duration | Notes |
|-------|----------|-------|
| Validate Parameters | <1 min | Parameter validation |
| Checkout | ~1 min | Git clone |
| Build Application | 3-5 min | Maven build |
| Unit Tests | 2-3 min | JUnit tests |
| Code Quality | 2-3 min | PMD + Checkstyle |
| Build Container | 3-5 min | Podman build |
| Security Scan | 2-5 min | Trivy vulnerability scan |
| Push to Registry | 1-2 min | ECR or local registry |
| Deploy to ECS | 3-5 min | ECS update + stabilize |
| Health Check | 1-5 min | Up to 30 retries |
| **Total** | **~25-30 min** | Compared to ~7 hours manual |

---

## Quick Start: Your First Build

### Prerequisites

Before running your first build, ensure:

1. **Jenkins Access**: You have credentials to access Jenkins at http://192.168.68.206:8080
2. **AWS Credentials Configured**: The `aws-prod` credential ID exists in Jenkins with valid AWS access keys
3. **Git Credentials Configured**: The `github-token` credential ID exists for repository access
4. **Infrastructure Deployed**: ECS cluster, ECR repository, and ALB exist (created via Terraform)

### Step-by-Step: Run a Build

1. **Navigate to Jenkins**
   ```
   Open: http://192.168.68.206:8080
   Login with your credentials
   ```

2. **Open the Pipeline Job**
   ```
   Click: middleware-platform (or your job name)
   ```

3. **Start Build with Parameters**
   ```
   Click: Build with Parameters (left sidebar)
   ```

4. **Configure Parameters**
   ```
   ENVIRONMENT:      prod-aws (or dev, staging)
   DEPLOY_TYPE:      full
   DRY_RUN:          unchecked (for actual deployment)
   LIBERTY_VERSION:  24.0.0.1 (default)
   AWS_CREDENTIALS_ID: aws-prod
   ```

5. **Run the Build**
   ```
   Click: Build
   ```

6. **Monitor Progress**
   ```
   Click: Build number (e.g., #1) in Build History
   Click: Console Output (for detailed logs)
   Or use Blue Ocean UI for visual pipeline view
   ```

### Expected Output

Successful build completion shows:

```
================================================================
DEPLOYMENT COMPLETE
Status:    SUCCESS
Version:   42-a1b2c3d
Commit:    a1b2c3d
Started:   2024-01-15 10:30:00
Completed: 2024-01-15 10:55:32

TIMING COMPARISON:
Manual Deployment:    ~7 hours
Automated Pipeline:   ~25 minutes
================================================================
```

---

## Pipeline Parameters

### Parameter Reference Table

| Parameter | Type | Default | Valid Options | Description |
|-----------|------|---------|---------------|-------------|
| `ENVIRONMENT` | Choice | `dev` | `dev`, `staging`, `prod-aws` | Target deployment environment |
| `DEPLOY_TYPE` | Choice | `full` | `full`, `application-only` | Scope of deployment |
| `DRY_RUN` | Boolean | `false` | `true`, `false` | Simulate without actual deployment |
| `LIBERTY_VERSION` | String | `24.0.0.1` | Format: `XX.X.X.X` | Open Liberty version for EC2 deployments |
| `AWS_CREDENTIALS_ID` | String | `aws-prod` | Any valid Jenkins credential ID | Jenkins credential ID for AWS access |

### When to Use Each Parameter

#### ENVIRONMENT

| Value | Use Case |
|-------|----------|
| `dev` | Local development testing, uses Ansible deployment to dev inventory |
| `staging` | Pre-production validation, uses Ansible deployment to staging inventory |
| `prod-aws` | Production deployment to AWS ECS Fargate or EC2 |

#### DEPLOY_TYPE

| Value | Use Case |
|-------|----------|
| `full` | Complete pipeline: build, test, scan, deploy |
| `application-only` | Skip infrastructure, deploy application code only |

#### DRY_RUN

| Value | Use Case |
|-------|----------|
| `true` | Validate pipeline without deploying (Ansible uses `--check` mode) |
| `false` | Execute actual deployment |

#### AWS_CREDENTIALS_ID

Change this when:
- Using different AWS accounts for different environments
- Rotating credentials (create new credential, update parameter)
- Testing with isolated AWS credentials

---

## Pipeline Stages Explained

### Stage 1: Validate Parameters

**What it does**: Validates all input parameters before pipeline execution.

**Validations performed**:
- ENVIRONMENT must be one of: `dev`, `staging`, `prod-aws`
- ENVIRONMENT cannot contain path traversal characters (`..`, `/`, `\`)
- LIBERTY_VERSION must match format `XX.X.X.X` (e.g., `24.0.0.1`)

**Prerequisites**: None

**Common failure causes**:
| Symptom | Cause | Resolution |
|---------|-------|------------|
| "Invalid environment" | Typo or API bypass | Use Jenkins UI to select valid option |
| "Invalid LIBERTY_VERSION format" | Wrong version format | Use format like `24.0.0.1` |

---

### Stage 2: Checkout

**What it does**: Clones the Git repository and sets version metadata.

**Variables set**:
- `GIT_COMMIT_SHORT`: Short commit hash (e.g., `a1b2c3d`)
- `VERSION`: Build version in format `{BUILD_NUMBER}-{COMMIT}` (e.g., `42-a1b2c3d`)
- `BUILD_TIMESTAMP`: Timestamp for tracking
- `ECS_CLUSTER`, `ECS_SERVICE`, `ALB_NAME`: Derived from environment

**Prerequisites**: Git credentials configured in Jenkins

**Common failure causes**:
| Symptom | Cause | Resolution |
|---------|-------|------------|
| "Permission denied" | Invalid Git credentials | Update `github-token` credential |
| "Repository not found" | Wrong repository URL | Update job SCM configuration |
| "Branch not found" | Branch deleted or renamed | Check branch name in job config |

---

### Stage 3: Build Application

**What it does**: Compiles the Java application using Maven.

**Container used**: `maven:3.9-eclipse-temurin-17`

**Command executed**:
```bash
mvn clean package -DskipTests -B
```

**Output**: WAR file in `sample-app/target/`

**Timeout**: 15 minutes

**Prerequisites**: Valid `pom.xml` in `sample-app/` directory

**Common failure causes**:
| Symptom | Cause | Resolution |
|---------|-------|------------|
| "Compilation failure" | Java syntax errors | Fix code in `sample-app/src/` |
| "Could not resolve dependencies" | Network or Maven repo issues | Check Maven settings, retry |
| "OutOfMemoryError" | Insufficient pod resources | Increase pod memory limits |

---

### Stage 4: Unit Tests

**What it does**: Runs JUnit tests and publishes results.

**Container used**: `maven:3.9-eclipse-temurin-17`

**Command executed**:
```bash
mvn test -B
```

**Output**: Test results in `sample-app/target/surefire-reports/`

**Timeout**: 10 minutes

**Prerequisites**: Successful Build Application stage

**Common failure causes**:
| Symptom | Cause | Resolution |
|---------|-------|------------|
| "Test failures" | Broken tests | Fix failing tests in `sample-app/src/test/` |
| "No tests found" | Missing test classes | Add tests or check naming conventions |

---

### Stage 5: Code Quality

**What it does**: Runs static code analysis with PMD and Checkstyle.

**Container used**: `maven:3.9-eclipse-temurin-17`

**Command executed**:
```bash
mvn pmd:pmd checkstyle:checkstyle -B
```

**Output**: XML reports in `sample-app/target/site/`

**Quality gate**: Unstable if >50 total issues

**Prerequisites**: Successful Build Application stage

**Common failure causes**:
| Symptom | Cause | Resolution |
|---------|-------|------------|
| "Build unstable" | Too many code issues | Address PMD/Checkstyle warnings |
| "Plugin not found" | Missing Maven plugin | Check `pom.xml` plugin configuration |

---

### Stage 6: Build Container

**What it does**: Builds the container image using Podman.

**Container used**: `quay.io/podman/stable:latest` (privileged)

**Command executed**:
```bash
podman build -t liberty-app:${VERSION} -f Containerfile .
```

**Output**: Container image tagged as `liberty-app:{VERSION}`

**Timeout**: 20 minutes

**Prerequisites**:
- Successful Build Application stage
- WAR file in `sample-app/target/`

**Common failure causes**:
| Symptom | Cause | Resolution |
|---------|-------|------------|
| "Containerfile not found" | Wrong directory | Check `containers/liberty/Containerfile` exists |
| "Base image pull failed" | Network or registry issues | Check network, retry |
| "COPY failed: file not found" | WAR not built | Ensure Build Application succeeded |

---

### Stage 7: Security Scan

**What it does**: Scans container image for vulnerabilities using Trivy.

**Container used**: `quay.io/podman/stable:latest`

**Command executed**:
```bash
trivy image --severity HIGH,CRITICAL --exit-code 1 liberty-app:${VERSION}
```

**Behavior**:
- Fails build if CRITICAL vulnerabilities found
- Reports HIGH and CRITICAL vulnerabilities
- Verifies Trivy binary checksum before scanning

**Timeout**: 10 minutes

**Prerequisites**: Successful Build Container stage

**Common failure causes**:
| Symptom | Cause | Resolution |
|---------|-------|------------|
| "CRITICAL vulnerabilities detected" | Security issues in image | Update base image or fix vulnerable packages |
| "Checksum verification failed" | Corrupted Trivy download | Retry build, check network |
| "Failed to download Trivy" | Network issues | Check outbound connectivity |

**Trivy database issues**:
```bash
# If Trivy database is outdated or corrupted, it auto-updates on first run
# For persistent issues, check GitHub releases for latest version
```

---

### Stage 8: Push to Registry

**What it does**: Pushes container image to the appropriate registry.

#### Push to ECR (prod-aws)

**Container used**: `quay.io/podman/stable:latest`

**Process**:
1. Retrieve AWS account ID
2. Authenticate with ECR
3. Tag image with version and `latest` (on main branch)
4. Push to ECR

**Prerequisites**:
- AWS credentials configured (`aws-prod`)
- ECR repository exists (created by Terraform)
- IAM permissions: `ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, `ecr:PutImage`, etc.

**Common failure causes**:
| Symptom | Cause | Resolution |
|---------|-------|------------|
| "Access denied" | Missing IAM permissions | Add ECR permissions to IAM role/user |
| "Repository not found" | ECR repo doesn't exist | Run Terraform to create ECR |
| "Expired credentials" | Token timeout | Refresh AWS credentials in Jenkins |

#### Push to Local Registry (dev/staging)

**Container used**: `quay.io/podman/stable:latest`

**Process**:
1. Tag image for local registry
2. Push to `registry.local`

**Prerequisites**: Local registry accessible at `registry.local`

---

### Stage 9: Deploy

**What it does**: Deploys the application to the target environment.

#### Deploy to ECS (prod-aws)

**Process**:
1. Capture current task definition ARN (for rollback)
2. Force new deployment with `aws ecs update-service --force-new-deployment`
3. Wait for service to stabilize
4. On failure: automatic rollback to previous task definition

**Prerequisites**:
- ECS cluster and service exist
- New container image pushed to ECR
- Valid AWS credentials

**Common failure causes**:
| Symptom | Cause | Resolution |
|---------|-------|------------|
| "Service not found" | ECS service doesn't exist | Run Terraform to create ECS service |
| "Cluster not found" | ECS cluster doesn't exist | Run Terraform to create cluster |
| "Failed to stabilize" | Container crashes | Check CloudWatch logs for container errors |

#### Deploy with Ansible (dev/staging)

**Container used**: `cytopia/ansible:latest`

**Command executed**:
```bash
ansible-playbook -i inventory/${ENVIRONMENT}.yml playbooks/site.yml \
    -e app_version=${VERSION} \
    -e liberty_version=${LIBERTY_VERSION}
```

**Prerequisites**:
- Inventory file exists: `automated/ansible/inventory/{env}.yml`
- Target hosts accessible
- SSH credentials configured

**Common failure causes**:
| Symptom | Cause | Resolution |
|---------|-------|------------|
| "Inventory file not found" | Missing inventory | Create `automated/ansible/inventory/{env}.yml` |
| "Unreachable host" | Network or SSH issues | Check host connectivity, SSH keys |
| "Permission denied" | Missing sudo or file permissions | Check Ansible become configuration |

---

### Stage 10: Health Check

**What it does**: Validates the deployment by checking application endpoints.

**Endpoints checked**:
| Endpoint | Priority | Description |
|----------|----------|-------------|
| `/health/ready` | Critical | MicroProfile Health readiness probe |
| `/api/info` | Critical | Application API info endpoint |
| `/metrics` | Non-critical | Prometheus metrics endpoint |

**Retry configuration**:
- Maximum retries: 30
- Delay between retries: 10 seconds
- Total maximum wait: ~5 minutes

**Timeout**: 10 minutes

**Prerequisites**: Successful deployment stage

**Common failure causes**:
| Symptom | Cause | Resolution |
|---------|-------|------------|
| "Readiness probe failed" | Container not ready | Check container logs, increase startup time |
| "Connection refused" | Container crashed | Check CloudWatch/pod logs |
| "Timeout" | Slow startup | Increase health check retries |

---

## Deployment Targets

### ECS Fargate Deployment Flow

```
+-------------+     +-------------+     +-------------+     +-------------+
|   Jenkins   | --> |     ECR     | --> |     ECS     | --> |     ALB     |
| Build Image |     | Push Image  |     | Update Svc  |     | Route Traffic|
+-------------+     +-------------+     +-------------+     +-------------+
                                              |
                                              v
                                    +-------------------+
                                    | ECS Fargate Tasks |
                                    | (Auto-scaling)    |
                                    +-------------------+
```

**Key characteristics**:
- Serverless container orchestration
- Auto-scaling: 2-6 tasks based on CPU/memory/requests
- Rolling deployment with automatic rollback on failure
- Health checks via ALB target group

**AWS resources involved**:
- ECR: `mw-prod-liberty` repository
- ECS Cluster: `mw-prod-cluster`
- ECS Service: `mw-prod-liberty`
- ALB: `mw-prod-alb`

**Deployment command**:
```bash
aws ecs update-service \
    --cluster mw-prod-cluster \
    --service mw-prod-liberty \
    --force-new-deployment
```

### EC2 Deployment Flow (Ansible)

```
+-------------+     +-------------+     +-------------+     +-------------+
|   Jenkins   | --> |   Ansible   | --> | EC2 Liberty | --> |     ALB     |
| Build WAR   |     | Deploy App  |     | Instances   |     | Route Traffic|
+-------------+     +-------------+     +-------------+     +-------------+
                          |
                          v
                +-------------------+
                | Configuration:    |
                | - server.xml      |
                | - Liberty runtime |
                | - Application WAR |
                +-------------------+
```

**Key characteristics**:
- Traditional VM-based deployment
- Full control over OS and runtime
- Configuration managed via Ansible roles
- Passwords auto-encoded using Liberty's `securityUtility`

**Ansible playbook**:
```bash
ansible-playbook -i inventory/prod.yml playbooks/site.yml \
    -e app_version=${VERSION} \
    -e liberty_version=${LIBERTY_VERSION}
```

**Key Ansible roles**:
- `liberty`: Installs and configures Open Liberty
- `app-deploy`: Deploys the application WAR

### Kubernetes Deployment Flow (Local)

```
+-------------+     +-------------+     +-------------+     +-------------+
|   Jenkins   | --> | Docker Hub  | --> | Kubernetes  | --> |   MetalLB   |
| Build Image |     | Push Image  |     | Deployment  |     | LoadBalancer|
+-------------+     +-------------+     +-------------+     +-------------+
                                              |
                                              v
                                    +-------------------+
                                    | K8s Pods          |
                                    | (192.168.68.200)  |
                                    +-------------------+
```

**Key characteristics**:
- 3-node Beelink homelab cluster
- MetalLB for LoadBalancer IPs
- Prometheus Operator for monitoring
- Local development and testing

**Kubernetes resources**:
- Deployment: `liberty-app`
- Service: `liberty-lb` (LoadBalancer)
- ServiceMonitor: For Prometheus scraping

**Manual deployment** (outside Jenkins):
```bash
kubectl apply -f kubernetes/base/liberty-deployment.yaml
kubectl set image deployment/liberty-app \
    liberty=docker.io/jconover/liberty-app:${VERSION}
```

---

## Troubleshooting Common Failures

### Build Fails at Security Scan

**Symptom**: "SECURITY SCAN FAILED: Critical vulnerabilities detected"

**Diagnosis**:
```bash
# View the Trivy report in Jenkins console output
# Look for "CRITICAL" severity vulnerabilities
```

**Resolution options**:

1. **Update base image**:
   ```dockerfile
   # In containers/liberty/Containerfile
   FROM icr.io/appcafe/open-liberty:kernel-slim-java17-openj9-ubi-latest
   ```

2. **Update application dependencies**:
   ```xml
   <!-- In sample-app/pom.xml, update vulnerable dependencies -->
   <dependency>
       <groupId>org.example</groupId>
       <artifactId>vulnerable-lib</artifactId>
       <version>PATCHED_VERSION</version>
   </dependency>
   ```

3. **Suppress false positives** (use with caution):
   ```yaml
   # Create .trivyignore in project root
   CVE-2024-XXXX  # Explanation for suppression
   ```

### ECR Push Fails

**Symptom**: "Access denied" or "Unable to authenticate"

**Diagnosis**:
```bash
# Test AWS credentials locally
aws sts get-caller-identity
aws ecr get-login-password --region us-east-1
```

**Resolution**:

1. **Verify Jenkins credential**:
   - Go to: Manage Jenkins > Credentials > System > Global credentials
   - Check `aws-prod` credential exists with valid keys

2. **Check IAM permissions**:
   ```json
   {
       "Version": "2012-10-17",
       "Statement": [
           {
               "Effect": "Allow",
               "Action": [
                   "ecr:GetAuthorizationToken",
                   "ecr:BatchCheckLayerAvailability",
                   "ecr:GetDownloadUrlForLayer",
                   "ecr:BatchGetImage",
                   "ecr:PutImage",
                   "ecr:InitiateLayerUpload",
                   "ecr:UploadLayerPart",
                   "ecr:CompleteLayerUpload"
               ],
               "Resource": "*"
           }
       ]
   }
   ```

3. **Verify ECR repository exists**:
   ```bash
   aws ecr describe-repositories --repository-names mw-prod-liberty
   ```

### Health Check Timeout

**Symptom**: "Readiness probe failed" after 30 retries

**Diagnosis**:
```bash
# For ECS
aws logs tail /ecs/mw-prod-liberty --follow

# For EC2
ssh ec2-user@<instance-ip> 'journalctl -u liberty -f'

# For Kubernetes
kubectl logs -f deployment/liberty-app
```

**Resolution**:

1. **Container startup too slow**:
   ```groovy
   // Increase health check configuration in Jenkinsfile
   HEALTH_CHECK_MAX_RETRIES = '60'
   HEALTH_CHECK_RETRY_DELAY = '10'
   ```

2. **Application crash**:
   - Check container logs for exceptions
   - Verify database connectivity
   - Check memory limits (OutOfMemoryError)

3. **Network issues**:
   - Verify security groups allow traffic on port 9080
   - Check ALB target group health
   - Verify DNS resolution

### Ansible Deployment Fails

**Symptom**: "Unreachable host" or "Permission denied"

**Diagnosis**:
```bash
# Test SSH connectivity
ssh -i ~/.ssh/your-key.pem ec2-user@<target-host>

# Test Ansible connectivity
ansible -i automated/ansible/inventory/prod.yml all -m ping
```

**Resolution**:

1. **SSH key issues**:
   - Verify SSH key is configured in Jenkins credentials
   - Check key permissions: `chmod 600 ~/.ssh/key.pem`

2. **Inventory file missing**:
   - Create inventory file: `automated/ansible/inventory/{env}.yml`
   - Example structure:
     ```yaml
     all:
       hosts:
         liberty-1:
           ansible_host: 10.0.1.10
       vars:
         ansible_user: ec2-user
         ansible_ssh_private_key_file: ~/.ssh/key.pem
     ```

3. **Vault password issues**:
   - Ensure `ANSIBLE_VAULT_PASSWORD` is set
   - Or use `--ask-vault-pass` in manual runs

---

## Customization

### How to Add New Stages

To add a new stage to the pipeline:

1. **Edit the Jenkinsfile**:
   ```groovy
   // Add after an existing stage
   stage('Your New Stage') {
       options {
           timeout(time: 10, unit: 'MINUTES')
       }
       when {
           // Optional: conditional execution
           expression { params.DEPLOY_TYPE == 'full' }
       }
       steps {
           container('maven') {  // or 'podman', 'ansible'
               sh '''
                   # Your commands here
                   echo "Running new stage"
               '''
           }
       }
       post {
           failure {
               echo 'Stage failed - add custom failure handling'
           }
       }
   }
   ```

2. **Common stage patterns**:

   **Integration tests**:
   ```groovy
   stage('Integration Tests') {
       when { expression { params.DEPLOY_TYPE == 'full' } }
       steps {
           container('maven') {
               dir('sample-app') {
                   sh 'mvn verify -Pintegration-tests -B'
               }
           }
       }
       post {
           always {
               junit 'sample-app/target/failsafe-reports/*.xml'
           }
       }
   }
   ```

   **Database migration**:
   ```groovy
   stage('Database Migration') {
       when { expression { params.ENVIRONMENT == 'prod-aws' } }
       steps {
           container('maven') {
               withCredentials([string(credentialsId: 'db-password', variable: 'DB_PASSWORD')]) {
                   sh 'mvn flyway:migrate -Dflyway.password=${DB_PASSWORD}'
               }
           }
       }
   }
   ```

### How to Modify Deployment Targets

#### Add a New Environment

1. **Update parameter choices**:
   ```groovy
   parameters {
       choice(name: 'ENVIRONMENT',
              choices: ['dev', 'staging', 'prod-aws', 'prod-eu'],  // Add new env
              description: 'Target environment')
   }
   ```

2. **Update parameter validation**:
   ```groovy
   stage('Validate Parameters') {
       steps {
           script {
               def allowedEnvironments = ['dev', 'staging', 'prod-aws', 'prod-eu']
               // ... validation logic
           }
       }
   }
   ```

3. **Create Ansible inventory** (for EC2 deployments):
   ```bash
   # Create automated/ansible/inventory/prod-eu.yml
   ```

4. **Update Terraform** (for ECS deployments):
   ```bash
   # Create automated/terraform/environments/prod-eu/
   ```

#### Add a New Container in Pod Template

```groovy
agent {
    kubernetes {
        yaml '''
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: maven
    image: maven:3.9-eclipse-temurin-17
    command: [cat]
    tty: true
  - name: podman
    image: quay.io/podman/stable:latest
    command: [cat]
    tty: true
    securityContext:
      privileged: true
  - name: ansible
    image: cytopia/ansible:latest
    command: [cat]
    tty: true
  # Add new container
  - name: terraform
    image: hashicorp/terraform:1.6
    command: [cat]
    tty: true
'''
    }
}
```

#### Change Health Check Endpoints

```groovy
environment {
    // Modify health check configuration
    HEALTH_CHECK_MAX_RETRIES = '60'      // Increase for slow startup
    HEALTH_CHECK_RETRY_DELAY = '15'      // Increase delay between checks
}

// In Health Check stage, modify endpoints:
if ! check_endpoint "/your/custom/health" "Custom health endpoint"; then
    HEALTH_CHECK_FAILED=1
fi
```

---

## Related Documentation

| Document | Description |
|----------|-------------|
| [CREDENTIAL_SETUP.md](CREDENTIAL_SETUP.md) | Credential configuration for all components |
| [END_TO_END_TESTING.md](END_TO_END_TESTING.md) | Testing guide for all deployment types |
| [LOCAL_KUBERNETES_DEPLOYMENT.md](LOCAL_KUBERNETES_DEPLOYMENT.md) | Local K8s cluster setup |
| [troubleshooting/terraform-aws.md](troubleshooting/terraform-aws.md) | AWS infrastructure troubleshooting |
