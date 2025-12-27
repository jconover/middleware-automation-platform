# Hybrid Architecture Overview

This diagram shows the two-environment deployment model: Local Kubernetes for development and AWS for production.

```mermaid
flowchart TB
    subgraph DEV["Local Development Environment"]
        subgraph HOMELAB["Beelink Homelab (192.168.68.0/24)"]
            direction TB
            K8S_MASTER["Master Node<br/>192.168.68.86"]
            K8S_WORKER1["Worker Node 1<br/>192.168.68.88"]
            K8S_WORKER2["Worker Node 2<br/>192.168.68.89"]

            K8S_MASTER --> K8S_WORKER1
            K8S_MASTER --> K8S_WORKER2

            subgraph K8S_APPS["Kubernetes Workloads"]
                LIBERTY_DEV["Liberty Pods"]
                PROMETHEUS_DEV["Prometheus"]
                GRAFANA_DEV["Grafana"]
            end
        end

        PODMAN["Podman<br/>Single Container Dev"]
    end

    subgraph PROD["AWS Production Environment"]
        subgraph VPC["VPC 10.10.0.0/16"]
            subgraph PUBLIC["Public Subnets"]
                ALB["Application<br/>Load Balancer"]
                NAT["NAT Gateway"]
                BASTION["Bastion Host"]
            end

            subgraph PRIVATE["Private Subnets"]
                subgraph COMPUTE["Compute Options"]
                    ECS["ECS Fargate<br/>(Default)"]
                    EC2["EC2 Instances<br/>(Optional)"]
                end

                subgraph DATA["Data Tier"]
                    RDS["RDS PostgreSQL"]
                    REDIS["ElastiCache Redis"]
                end

                MONITORING["Prometheus +<br/>Grafana EC2"]
            end
        end

        ECR["ECR<br/>Container Registry"]
        SECRETS["Secrets Manager"]
    end

    DEV -->|"Promote<br/>Container Image"| ECR
    ECR --> ECS
    ECR --> EC2

    ALB --> ECS
    ALB --> EC2
    ECS --> RDS
    ECS --> REDIS
    EC2 --> RDS
    EC2 --> REDIS

    MONITORING --> ECS
    MONITORING --> EC2

    style DEV fill:#e1f5fe
    style PROD fill:#fff3e0
    style ECS fill:#ff9800
    style EC2 fill:#4caf50
```

## Environment Comparison

| Aspect | Local Development | AWS Production |
|--------|------------------|----------------|
| **Compute** | Kubernetes / Podman | ECS Fargate or EC2 |
| **Networking** | 192.168.68.0/24 | VPC 10.10.0.0/16 |
| **Load Balancing** | K8s Ingress / NodePort | Application Load Balancer |
| **Database** | Local PostgreSQL | RDS PostgreSQL |
| **Cache** | Local Redis | ElastiCache Redis |
| **Monitoring** | Prometheus + Grafana | Prometheus + Grafana EC2 |
| **Cost** | Hardware only | ~$140/month |
