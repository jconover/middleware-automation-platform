# CI/CD Pipeline Architecture

This diagram shows the Jenkins pipeline flow for building and deploying the Liberty application.

## Pipeline Overview

```mermaid
flowchart TB
    subgraph TRIGGER["Trigger"]
        GIT["Git Push /<br/>Manual Trigger"]
    end

    subgraph JENKINS["Jenkins Pipeline (Kubernetes Pods)"]
        direction TB

        subgraph BUILD["Build Stage"]
            MAVEN["Maven Container"]
            MVN_BUILD["mvn clean package"]
            WAR["sample-app.war"]

            MAVEN --> MVN_BUILD --> WAR
        end

        subgraph CONTAINER["Container Stage"]
            PODMAN["Podman Container"]
            IMG_BUILD["Build Image"]
            ECR_PUSH["Push to ECR"]

            PODMAN --> IMG_BUILD --> ECR_PUSH
        end

        subgraph DEPLOY["Deploy Stage"]
            direction LR
            ECS_DEPLOY["ECS Update Service"]
            EC2_DEPLOY["Ansible Playbook"]
        end

        subgraph VERIFY["Verification"]
            HEALTH["Health Check"]
            SMOKE["Smoke Tests"]
        end
    end

    subgraph AWS["AWS Environment"]
        ECR["ECR Repository"]
        ECS["ECS Fargate"]
        EC2["EC2 Instances"]
    end

    GIT --> BUILD
    BUILD --> CONTAINER
    CONTAINER --> ECR
    ECR --> DEPLOY
    ECS_DEPLOY --> ECS
    EC2_DEPLOY --> EC2
    DEPLOY --> VERIFY

    style BUILD fill:#e3f2fd
    style CONTAINER fill:#fff3e0
    style DEPLOY fill:#e8f5e9
    style VERIFY fill:#fce4ec
```

## Detailed Pipeline Stages

```mermaid
flowchart LR
    subgraph S1["1. Checkout"]
        CHECKOUT["Clone Repository"]
    end

    subgraph S2["2. Build"]
        BUILD_APP["Maven Build"]
        COPY_WAR["Copy WAR to<br/>container dir"]
    end

    subgraph S3["3. Container"]
        BUILD_IMG["Podman Build"]
        TAG["Tag Image"]
        PUSH["Push to ECR"]
    end

    subgraph S4["4. Deploy"]
        DEPLOY_ECS["ECS:<br/>force-new-deployment"]
        DEPLOY_EC2["EC2:<br/>Ansible Playbook"]
    end

    subgraph S5["5. Verify"]
        WAIT["Wait for<br/>Stabilization"]
        HEALTH_CHK["Health Check<br/>/health/ready"]
    end

    S1 --> S2 --> S3 --> S4 --> S5

    style S1 fill:#e1f5fe
    style S2 fill:#e8f5e9
    style S3 fill:#fff3e0
    style S4 fill:#f3e5f5
    style S5 fill:#fce4ec
```

## Pipeline Parameters

| Parameter | Options | Default | Description |
|-----------|---------|---------|-------------|
| `ENVIRONMENT` | dev, staging, prod-aws | prod-aws | Target environment |
| `DEPLOY_TYPE` | full, application-only, infrastructure-only | full | Deployment scope |
| `DRY_RUN` | true, false | false | Skip actual deployment |

## Container Build Process

```mermaid
flowchart TB
    subgraph SOURCE["Source Files"]
        POM["pom.xml"]
        JAVA["Java Sources"]
        CFILE["Containerfile"]
        SERVER_XML["server.xml"]
    end

    subgraph BUILD_STEPS["Build Steps"]
        MVN["mvn clean package"]
        COPY["cp target/*.war<br/>containers/liberty/apps/"]
        PODMAN_BUILD["podman build -t<br/>liberty-app:BUILD_NUM"]
    end

    subgraph ECR_STEPS["ECR Push"]
        LOGIN["aws ecr get-login-password"]
        TAG_IMG["podman tag<br/>ACCOUNT.dkr.ecr.REGION.amazonaws.com"]
        PUSH_IMG["podman push"]
    end

    POM --> MVN
    JAVA --> MVN
    MVN --> COPY
    CFILE --> PODMAN_BUILD
    SERVER_XML --> PODMAN_BUILD
    COPY --> PODMAN_BUILD
    PODMAN_BUILD --> LOGIN
    LOGIN --> TAG_IMG
    TAG_IMG --> PUSH_IMG
```

## Deployment Flow by Target

### ECS Deployment
```bash
aws ecs update-service \
    --cluster mw-prod-cluster \
    --service mw-prod-liberty \
    --force-new-deployment
```

### EC2 Deployment
```bash
ansible-playbook \
    -i inventory/prod-aws-ec2.yml \
    playbooks/deploy-sample-app.yml
```

## Pipeline Artifacts

| Stage | Input | Output |
|-------|-------|--------|
| Build | Java sources, pom.xml | sample-app.war |
| Container | WAR, Containerfile, server.xml | liberty-app:BUILD_NUM image |
| Push | Local image | ECR image with tag |
| Deploy | ECR image | Running ECS tasks or EC2 deployment |
