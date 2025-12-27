# AWS Network Topology

This diagram shows the VPC structure, subnets, and security group relationships.

## VPC Architecture

```mermaid
flowchart TB
    INTERNET["Internet"]

    subgraph VPC["VPC: 10.10.0.0/16"]
        IGW["Internet Gateway"]

        subgraph AZ1["Availability Zone 1"]
            subgraph PUB1["Public Subnet<br/>10.10.1.0/24"]
                ALB1["ALB ENI"]
                NAT1["NAT Gateway"]
                MGMT["Management EC2<br/>(AWX/Jenkins)"]
            end

            subgraph PRIV1["Private Subnet<br/>10.10.11.0/24"]
                ECS1["ECS Task 1"]
                EC2_1["Liberty EC2 #1"]
                MON["Monitoring EC2<br/>(Prometheus/Grafana)"]
            end
        end

        subgraph AZ2["Availability Zone 2"]
            subgraph PUB2["Public Subnet<br/>10.10.2.0/24"]
                ALB2["ALB ENI"]
            end

            subgraph PRIV2["Private Subnet<br/>10.10.12.0/24"]
                ECS2["ECS Task 2"]
                EC2_2["Liberty EC2 #2"]
                RDS["RDS PostgreSQL"]
                REDIS["ElastiCache Redis"]
            end
        end
    end

    INTERNET <--> IGW
    IGW <--> ALB1
    IGW <--> ALB2
    IGW <--> MGMT
    NAT1 <--> IGW

    PRIV1 --> NAT1
    PRIV2 --> NAT1

    style PUB1 fill:#e3f2fd
    style PUB2 fill:#e3f2fd
    style PRIV1 fill:#fff3e0
    style PRIV2 fill:#fff3e0
```

## Security Groups

```mermaid
flowchart LR
    subgraph EXTERNAL["External"]
        INTERNET2["Internet<br/>0.0.0.0/0"]
        ADMIN_IP["Admin IP<br/>(Allowed CIDRs)"]
    end

    subgraph SG_ALB["SG: ALB"]
        ALB_IN["Inbound:<br/>80, 443 from 0.0.0.0/0"]
    end

    subgraph SG_LIBERTY["SG: Liberty"]
        LIB_IN["Inbound:<br/>9080, 9443 from ALB SG"]
    end

    subgraph SG_DB["SG: Database"]
        DB_IN["Inbound:<br/>5432 from Liberty SG"]
    end

    subgraph SG_CACHE["SG: Cache"]
        CACHE_IN["Inbound:<br/>6379 from Liberty SG"]
    end

    subgraph SG_MGMT["SG: Management"]
        MGMT_IN["Inbound:<br/>22, 30080, 3000, 9090<br/>from Admin IPs"]
    end

    INTERNET2 -->|"HTTP/HTTPS"| SG_ALB
    SG_ALB -->|"9080/9443"| SG_LIBERTY
    SG_LIBERTY -->|"5432"| SG_DB
    SG_LIBERTY -->|"6379"| SG_CACHE
    ADMIN_IP -->|"SSH/Web"| SG_MGMT

    style SG_ALB fill:#e3f2fd
    style SG_LIBERTY fill:#e8f5e9
    style SG_DB fill:#fff3e0
    style SG_CACHE fill:#fce4ec
    style SG_MGMT fill:#f3e5f5
```

## Subnet Configuration

| Subnet Type | CIDR | Resources | Internet Access |
|-------------|------|-----------|-----------------|
| Public AZ1 | 10.10.1.0/24 | ALB, NAT, Management | Direct via IGW |
| Public AZ2 | 10.10.2.0/24 | ALB | Direct via IGW |
| Private AZ1 | 10.10.11.0/24 | ECS, EC2, Monitoring | NAT Gateway |
| Private AZ2 | 10.10.12.0/24 | ECS, EC2, RDS, Redis | NAT Gateway |

## Security Group Rules

### ALB Security Group
| Direction | Port | Source | Purpose |
|-----------|------|--------|---------|
| Inbound | 80 | 0.0.0.0/0 | HTTP (redirects to HTTPS) |
| Inbound | 443 | 0.0.0.0/0 | HTTPS traffic |
| Outbound | All | 0.0.0.0/0 | Health checks |

### Liberty Security Group
| Direction | Port | Source | Purpose |
|-----------|------|--------|---------|
| Inbound | 9080 | ALB SG | HTTP application |
| Inbound | 9443 | ALB SG | HTTPS admin console |
| Outbound | 5432 | DB SG | PostgreSQL |
| Outbound | 6379 | Cache SG | Redis |
| Outbound | 443 | 0.0.0.0/0 | Secrets Manager, ECR |

### Database Security Group
| Direction | Port | Source | Purpose |
|-----------|------|--------|---------|
| Inbound | 5432 | Liberty SG | PostgreSQL connections |

### Cache Security Group
| Direction | Port | Source | Purpose |
|-----------|------|--------|---------|
| Inbound | 6379 | Liberty SG | Redis connections |

## Network Flow Summary

```mermaid
flowchart LR
    A["Client"] -->|"HTTPS :443"| B["ALB"]
    B -->|":9080"| C["Liberty"]
    C -->|":5432"| D["RDS"]
    C -->|":6379"| E["Redis"]
    C -->|":443 via NAT"| F["AWS APIs"]

    style A fill:#e1f5fe
    style B fill:#bbdefb
    style C fill:#c8e6c9
    style D fill:#ffe0b2
    style E fill:#f8bbd9
    style F fill:#d1c4e9
```
