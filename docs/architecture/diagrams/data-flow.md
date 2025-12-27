# Request Data Flow

This diagram shows how requests flow through the system from client to database.

## HTTP Request Flow

```mermaid
sequenceDiagram
    autonumber
    participant Client
    participant ALB as Application<br/>Load Balancer
    participant TG as Target Group
    participant Liberty as Liberty<br/>(ECS/EC2)
    participant Redis as ElastiCache<br/>Redis
    participant RDS as RDS<br/>PostgreSQL
    participant SM as Secrets<br/>Manager

    Client->>ALB: HTTPS Request
    ALB->>ALB: SSL Termination

    alt Default Route (ECS)
        ALB->>TG: Forward to ECS Target Group
    else X-Target: ec2 Header
        ALB->>TG: Forward to EC2 Target Group
    end

    TG->>Liberty: HTTP :9080

    Note over Liberty: MicroProfile Health Check<br/>/health/ready

    Liberty->>SM: Get DB Credentials (cached)
    SM-->>Liberty: Credentials

    Liberty->>Redis: Check Session Cache
    alt Cache Hit
        Redis-->>Liberty: Session Data
    else Cache Miss
        Liberty->>RDS: Query Database
        RDS-->>Liberty: Query Result
        Liberty->>Redis: Update Cache
    end

    Liberty-->>TG: Response
    TG-->>ALB: Response
    ALB-->>Client: HTTPS Response
```

## Health Check Flow

```mermaid
sequenceDiagram
    participant ALB as Load Balancer
    participant TG as Target Group
    participant Liberty as Liberty Container
    participant MP as MicroProfile<br/>Health

    loop Every 30 seconds
        ALB->>TG: Health Check
        TG->>Liberty: GET /health/ready :9080
        Liberty->>MP: Check Components

        MP->>MP: Database Connectivity
        MP->>MP: Redis Connectivity
        MP->>MP: Heap Memory Status

        alt All Healthy
            MP-->>Liberty: Status: UP
            Liberty-->>TG: 200 OK
            TG-->>ALB: Healthy
        else Any Unhealthy
            MP-->>Liberty: Status: DOWN
            Liberty-->>TG: 503 Service Unavailable
            TG-->>ALB: Unhealthy
            Note over ALB: Remove from rotation
        end
    end
```

## Metrics Collection Flow

```mermaid
flowchart LR
    subgraph COMPUTE["Compute Layer"]
        ECS["ECS Tasks"]
        EC2["EC2 Instances"]
    end

    subgraph METRICS["Metrics Endpoints"]
        ECS_M["/metrics :9080"]
        EC2_M["/metrics :9080"]
    end

    subgraph MONITORING["Monitoring Stack"]
        PROM["Prometheus"]
        GRAFANA["Grafana"]
    end

    ECS --> ECS_M
    EC2 --> EC2_M

    PROM -->|"Scrape every 15s"| ECS_M
    PROM -->|"Scrape every 15s"| EC2_M

    GRAFANA -->|"Query"| PROM

    style MONITORING fill:#fff3e0
```

## Data Layer Connections

| Source | Destination | Port | Protocol | Purpose |
|--------|-------------|------|----------|---------|
| ALB | Liberty | 9080 | HTTP | Application traffic |
| ALB | Liberty | 9443 | HTTPS | Admin console |
| Liberty | RDS | 5432 | PostgreSQL | Database queries |
| Liberty | Redis | 6379 | Redis | Session cache |
| Liberty | Secrets Manager | 443 | HTTPS | Credential retrieval |
| Prometheus | Liberty | 9080 | HTTP | Metrics scraping |
