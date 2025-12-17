# Manual Deployment Guide

> **Purpose**: Complete step-by-step manual deployment with timing checkpoints.  
> **Target**:  Senior Middleware Application Server Engineer demonstration.  
> **Estimated Total Time**: ~7 hours (420 minutes)

---

## Timing Protocol

Before starting each phase:
1. **Start a stopwatch/timer**
2. **Record your start time** in the checkpoint boxes
3. **Log actual completion time** at the end of each task
4. **Calculate variance** from expected time

This creates documented evidence of manual effort for ROI comparison.

---

## Prerequisites

- 3 servers (physical or VM) with Ubuntu 22.04 LTS
- Or: Single machine with Podman for containerized demo
- Internet access for package downloads
- sudo/root access

---

# Phase 1: Infrastructure Setup

**Expected Time: 135 minutes**

> **Choose ONE option below**: Option A for physical/VM servers, Option B for Podman demo on a single machine.

---

## Option A: Physical/VM Servers

*Skip to Option B if using Podman for demo.*

### Task 1.1: Prepare Server 1 (liberty-server-01)

**Expected: 25 minutes** | **Actual: ______** | **Start Time: ______**

```bash
# Connect to server
ssh ubuntu@192.168.68.88

# Update system packages
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y \
    openjdk-17-jdk \
    curl wget unzip vim net-tools htop jq

# Verify Java installation
java -version

# Set JAVA_HOME permanently
echo 'export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64' | sudo tee -a /etc/environment
source /etc/environment

# Configure hostname
sudo hostnamectl set-hostname liberty-server-01

# Configure /etc/hosts for cluster communication
sudo bash -c 'cat >> /etc/hosts << EOF
192.168.68.86  liberty-controller-01
192.168.68.88  liberty-server-01
192.168.68.83  liberty-server-02
EOF'
```

### Task 1.2: Prepare Server 2 (liberty-server-02)

**Expected: 25 minutes** | **Actual: ______**

Repeat Task 1.1 on second server (192.168.68.83), setting hostname to `liberty-server-02`.

### Task 1.3: Prepare Controller Server (liberty-controller-01)

**Expected: 25 minutes** | **Actual: ______**

Repeat Task 1.1 on controller server (192.168.68.86), setting hostname to `liberty-controller-01`.

### Task 1.4: Create Liberty User on All Servers

**Expected: 45 minutes (15 per server)** | **Actual: ______**

Run on **each server**:

```bash
sudo useradd -m -s /bin/bash -c "Open Liberty Service Account" liberty
sudo mkdir -p /opt/ibm/wlp /var/log/liberty /var/liberty/{apps,config,shared,dropins}
sudo chown -R liberty:liberty /opt/ibm /var/log/liberty /var/liberty
```

### Task 1.5: Configure Firewall Rules

**Expected: 15 minutes** | **Actual: ______**

```bash
sudo ufw enable
sudo ufw allow 22/tcp
sudo ufw allow 9080/tcp
sudo ufw allow 9443/tcp
sudo ufw allow 9060/tcp
sudo ufw status
```

**Checkpoint Option A:** _______ minutes total | **Now skip to Phase 2**

---

## Option B: Podman Demo Environment (Single Machine)

*This option lets you demo the entire setup on one machine using containers.*

### Task 1.1-P: Install Podman and Create Network

**Expected: 10 minutes** | **Actual: 3 minutes.**

```bash
# Install Podman
sudo apt update && sudo apt install -y podman

# Create network for Liberty containers
podman network create liberty-net

# Verify
podman network ls
```

---

### Task 1.2-P: Create and Configure Controller Container

**Expected: 20 minutes** | **Actual: ______**

```bash
# Create controller container
podman run -d --name liberty-controller \
    --hostname liberty-controller-01 \
    --network liberty-net \
    -p 9060:9080 -p 9443:9443 \
    ubuntu:22.04 sleep infinity

# Enter the container
podman exec -it liberty-controller bash

# === NOW INSIDE CONTAINER ===

# Update and install packages
apt update && apt install -y openjdk-17-jdk curl wget unzip vim net-tools

# Verify Java
java -version

# Set JAVA_HOME
echo 'export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64' >> /etc/environment
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

# Create liberty user and directories
useradd -m -s /bin/bash liberty
mkdir -p /opt/ibm/wlp /var/log/liberty /var/liberty/{apps,config,shared}
chown -R liberty:liberty /opt/ibm /var/log/liberty /var/liberty

# Verify setup
ls -la /opt/ibm/
id liberty

# Exit container
exit
```

**Checkpoint 1.2-P:**
- [ ] Container running
- [ ] Java installed
- [ ] liberty user created
- [ ] Directories created
- **Actual time: _______ minutes**

---

### Task 1.3-P: Create and Configure Server 1 Container

**Expected: 20 minutes** | **Actual: ______**

```bash
# Create server 1 container
podman run -d --name liberty-server-01 \
    --hostname liberty-server-01 \
    --network liberty-net \
    -p 9080:9080 -p 9444:9443 \
    ubuntu:22.04 sleep infinity

# Enter the container
podman exec -it liberty-server-01 bash

# === NOW INSIDE CONTAINER ===

# Update and install packages
apt update && apt install -y openjdk-17-jdk curl wget unzip vim net-tools

# Set JAVA_HOME
echo 'export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64' >> /etc/environment
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

# Create liberty user and directories
useradd -m -s /bin/bash liberty
mkdir -p /opt/ibm/wlp /var/log/liberty /var/liberty/{apps,config,shared}
chown -R liberty:liberty /opt/ibm /var/log/liberty /var/liberty

# Exit container
exit
```

**Checkpoint 1.3-P:**
- [ ] Container running
- [ ] Java installed
- [ ] liberty user created
- **Actual time: _______ minutes**

---

### Task 1.4-P: Create and Configure Server 2 Container

**Expected: 20 minutes** | **Actual: ______**

```bash
# Create server 2 container
podman run -d --name liberty-server-02 \
    --hostname liberty-server-02 \
    --network liberty-net \
    -p 9180:9080 -p 9543:9443 \
    ubuntu:22.04 sleep infinity

# Enter the container
podman exec -it liberty-server-02 bash

# === NOW INSIDE CONTAINER ===

# Update and install packages
apt update && apt install -y openjdk-17-jdk curl wget unzip vim net-tools

# Set JAVA_HOME
echo 'export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64' >> /etc/environment
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

# Create liberty user and directories
useradd -m -s /bin/bash liberty
mkdir -p /opt/ibm/wlp /var/log/liberty /var/liberty/{apps,config,shared}
chown -R liberty:liberty /opt/ibm /var/log/liberty /var/liberty

# Exit container
exit
```

**Checkpoint 1.4-P:**
- [ ] Container running
- [ ] Java installed  
- [ ] liberty user created
- **Actual time: _______ minutes**

---

### Task 1.5-P: Verify All Containers

**Expected: 5 minutes** | **Actual: ______**

```bash
# List all running containers
podman ps

# Expected output:
# CONTAINER ID  IMAGE                  COMMAND         NAMES
# xxxxxxxxxxxx  docker.io/ubuntu:22.04 sleep infinity  liberty-controller
# xxxxxxxxxxxx  docker.io/ubuntu:22.04 sleep infinity  liberty-server-01
# xxxxxxxxxxxx  docker.io/ubuntu:22.04 sleep infinity  liberty-server-02

# Test network connectivity between containers
podman exec liberty-server-01 ping -c 2 liberty-controller
podman exec liberty-server-02 ping -c 2 liberty-server-01

# Verify Java in all containers
podman exec liberty-controller java -version
podman exec liberty-server-01 java -version
podman exec liberty-server-02 java -version
```

**Checkpoint Option B Complete:**
- [ ] 3 containers running
- [ ] All can ping each other by hostname
- [ ] Java working in all containers
- **Total Phase 1 time: _______ minutes**

---

### Quick Reference: Podman Container Access

Throughout the rest of this guide, use these commands to access each container:

```bash
# Controller
podman exec -it liberty-controller bash

# Server 1
podman exec -it liberty-server-01 bash

# Server 2
podman exec -it liberty-server-02 bash

# Run command without entering container
podman exec liberty-server-01 /opt/ibm/wlp/bin/server status appServer
```

**Port Mappings (access from host machine):**
| Container | Container Port | Host Port | URL |
|-----------|---------------|-----------|-----|
| liberty-controller | 9080 | 9060 | http://localhost:9060 |
| liberty-controller | 9443 | 9443 | https://localhost:9443 |
| liberty-server-01 | 9080 | 9080 | http://localhost:9080 |
| liberty-server-01 | 9443 | 9444 | https://localhost:9444 |
| liberty-server-02 | 9080 | 9180 | http://localhost:9180 |
| liberty-server-02 | 9443 | 9543 | https://localhost:9543 |

---

# Phase 2: Open Liberty Installation

**Expected Time: 140 minutes**

> **Podman Users**: For each task below, enter the appropriate container first:
> ```bash
> podman exec -it liberty-server-01 bash   # For server tasks
> podman exec -it liberty-controller bash  # For controller tasks
> ```

## Background: WebSphere Liberty vs Traditional WebSphere

If you're familiar with traditional WebSphere Application Server (WAS), here are the key differences:

| Aspect | Traditional WAS | Open Liberty |
|--------|-----------------|--------------|
| Configuration | XML + Admin Console | server.xml (single file) |
| Startup Time | 60-120 seconds | 2-5 seconds |
| Memory Footprint | 512MB-2GB+ | 50-300MB |
| Features | All loaded | Only what you need |
| Deployment Model | Cells/Nodes/Clusters | Collectives (optional) |

Liberty uses a **feature-based model** - you only enable what you need.

---

### Task 2.1: Download Open Liberty

**Expected: 15 minutes per server (45 total)** | **Actual: ______**

**Run on: liberty-server-01, liberty-server-02, AND liberty-controller**

```bash
# ============================================================
# PODMAN: Enter container first
# podman exec -it liberty-server-01 bash
# ============================================================

# Switch to liberty user (skip 'sudo' in containers - you're already root)
su - liberty

# Navigate to install directory
cd /opt/ibm

# Download Open Liberty 24.0.0.1
wget https://public.dhe.ibm.com/ibmdl/export/pub/software/openliberty/runtime/release/24.0.0.1/openliberty-24.0.0.1.zip

# Verify download (check file size ~70MB)
ls -lh openliberty-24.0.0.1.zip

# Extract Liberty
unzip openliberty-24.0.0.1.zip

# Verify installation
/opt/ibm/wlp/bin/server version
# Expected: Open Liberty 24.0.0.1

# Exit back to root (in container) or exit container
exit
```

**Podman Shortcut** - Run on all containers without entering each one:
```bash
# Download and extract Liberty on all three containers
for container in liberty-controller liberty-server-01 liberty-server-02; do
    echo "=== Installing Liberty on $container ==="
    podman exec $container bash -c "
        su - liberty -c '
            cd /opt/ibm && \
            wget -q https://public.dhe.ibm.com/ibmdl/export/pub/software/openliberty/runtime/release/24.0.0.1/openliberty-24.0.0.1.zip && \
            unzip -q openliberty-24.0.0.1.zip && \
            /opt/ibm/wlp/bin/server version
        '
    "
done
```

**Checkpoint 2.1:**
- [ ] Liberty downloaded on all servers/containers
- [ ] Extracted to /opt/ibm/wlp
- [ ] `server version` returns 24.0.0.1
- **Actual time: _______ minutes**

---

### Task 2.2: Create Server Instance

**Expected: 20 minutes** | **Actual: ______**

**Run on: liberty-server-01 and liberty-server-02** (NOT controller yet)

```bash
# ============================================================
# PODMAN: Enter container first
# podman exec -it liberty-server-01 bash
# ============================================================

# Switch to liberty user
su - liberty

# Create a new server instance named "appServer"
/opt/ibm/wlp/bin/server create appServer

# This creates:
# /opt/ibm/wlp/usr/servers/appServer/
# ├── apps/           # Application deployments
# ├── dropins/        # Hot-deploy directory
# ├── logs/           # Server logs
# ├── server.xml      # Main configuration
# └── server.env      # Environment variables

# View the default server.xml
cat /opt/ibm/wlp/usr/servers/appServer/server.xml

exit
```

**Podman Shortcut:**
```bash
# Create appServer on both application servers
for container in liberty-server-01 liberty-server-02; do
    echo "=== Creating appServer on $container ==="
    podman exec $container su - liberty -c '/opt/ibm/wlp/bin/server create appServer'
done
```

**Checkpoint 2.2:**
- [ ] appServer created on liberty-server-01
- [ ] appServer created on liberty-server-02
- **Actual time: _______ minutes**

---

### Task 2.3: Configure server.xml

**Expected: 30 minutes** | **Actual: ______**

**Run on: liberty-server-01** (then copy to liberty-server-02)

```bash
# ============================================================
# PODMAN: Enter container first
# podman exec -it liberty-server-01 bash
# ============================================================

# Switch to liberty user
su - liberty

# Backup default config
cp /opt/ibm/wlp/usr/servers/appServer/server.xml \
   /opt/ibm/wlp/usr/servers/appServer/server.xml.backup

# Create new server.xml
cat > /opt/ibm/wlp/usr/servers/appServer/server.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<server description="Enterprise Application Server">

    <!-- =================================================================== -->
    <!-- FEATURES - Only enable what you need                                -->
    <!-- =================================================================== -->
    <featureManager>
        <!-- Jakarta EE 10 Web Profile -->
        <feature>servlet-6.0</feature>
        <feature>jsp-3.1</feature>
        <feature>restfulWS-3.1</feature>
        <feature>jsonb-3.0</feature>
        <feature>jsonp-2.1</feature>
        <feature>cdi-4.0</feature>
        
        <!-- Database -->
        <feature>jdbc-4.3</feature>
        <feature>jpa-3.1</feature>
        
        <!-- MicroProfile (cloud-native) -->
        <feature>mpConfig-3.0</feature>
        <feature>mpHealth-4.0</feature>
        <feature>mpMetrics-5.0</feature>
        <feature>mpOpenAPI-3.0</feature>
        
        <!-- Security -->
        <feature>ssl-1.0</feature>
        <feature>transportSecurity-1.0</feature>
        <feature>appSecurity-5.0</feature>
        
        <!-- Monitoring -->
        <feature>monitor-1.0</feature>
    </featureManager>

    <!-- =================================================================== -->
    <!-- HTTP ENDPOINTS                                                      -->
    <!-- =================================================================== -->
    <httpEndpoint id="defaultHttpEndpoint"
                  host="*"
                  httpPort="9080"
                  httpsPort="9443">
        <accessLogging filepath="${server.output.dir}/logs/access.log"
                       logFormat='%h %u %t "%r" %s %b %D' />
    </httpEndpoint>

    <!-- =================================================================== -->
    <!-- SSL/TLS CONFIGURATION                                               -->
    <!-- =================================================================== -->
    <ssl id="defaultSSLConfig"
         keyStoreRef="defaultKeyStore"
         trustStoreRef="defaultTrustStore"
         sslProtocol="TLSv1.3" />
    
    <keyStore id="defaultKeyStore"
              location="${server.config.dir}/resources/security/key.p12"
              password="${env.KEYSTORE_PASSWORD}"
              type="PKCS12" />
    
    <keyStore id="defaultTrustStore"
              location="${server.config.dir}/resources/security/trust.p12"
              password="${env.TRUSTSTORE_PASSWORD}"
              type="PKCS12" />

    <!-- =================================================================== -->
    <!-- DATABASE CONFIGURATION                                              -->
    <!-- =================================================================== -->
    <library id="PostgreSQLLib">
        <fileset dir="${shared.resource.dir}/jdbc" includes="postgresql-*.jar"/>
    </library>

    <dataSource id="DefaultDataSource" jndiName="jdbc/appDB">
        <jdbcDriver libraryRef="PostgreSQLLib"/>
        <properties.postgresql
            serverName="${env.DB_HOST}"
            portNumber="${env.DB_PORT}"
            databaseName="${env.DB_NAME}"
            user="${env.DB_USER}"
            password="${env.DB_PASSWORD}" />
        <connectionManager minPoolSize="5" maxPoolSize="50"
                          connectionTimeout="30s" maxIdleTime="10m" />
    </dataSource>

    <!-- =================================================================== -->
    <!-- HEALTH & METRICS                                                    -->
    <!-- =================================================================== -->
    <mpHealth authentication="false" />
    <mpMetrics authentication="false" />

    <!-- =================================================================== -->
    <!-- APPLICATION                                                         -->
    <!-- =================================================================== -->
    <applicationManager autoExpand="true" />
    <applicationMonitor updateTrigger="polled" pollingRate="5s" dropinsEnabled="true" />

    <!-- =================================================================== -->
    <!-- LOGGING                                                             -->
    <!-- =================================================================== -->
    <logging consoleLogLevel="INFO" consoleFormat="DEV"
             maxFileSize="50" maxFiles="10" />

</server>
EOF
```

**Create server.env:**

```bash
cat > /opt/ibm/wlp/usr/servers/appServer/server.env << 'EOF'
DB_HOST=localhost
DB_PORT=5432
DB_NAME=appdb
DB_USER=appuser
DB_PASSWORD=changeme
KEYSTORE_PASSWORD=libertykeys
TRUSTSTORE_PASSWORD=libertytrust
EOF
```

**Create jvm.options:**

```bash
cat > /opt/ibm/wlp/usr/servers/appServer/jvm.options << 'EOF'
-Xms512m
-Xmx2g
-XX:+UseG1GC
-XX:MaxGCPauseMillis=200
-XX:+UseContainerSupport
-XX:MaxRAMPercentage=75.0
-Djava.security.egd=file:/dev/urandom
-Djava.net.preferIPv4Stack=true
EOF
```

**Create security directory:**

```bash
mkdir -p /opt/ibm/wlp/usr/servers/appServer/resources/security
```

**Checkpoint 2.3:**
- [ ] server.xml configured
- [ ] server.env created
- [ ] jvm.options created
- [ ] Replicated to server-02
- **Actual time: _______ minutes**

**Podman: Copy config to server-02:**
```bash
# Copy from server-01 to server-02
podman exec liberty-server-01 cat /opt/ibm/wlp/usr/servers/appServer/server.xml | \
    podman exec -i liberty-server-02 su - liberty -c 'cat > /opt/ibm/wlp/usr/servers/appServer/server.xml'

podman exec liberty-server-01 cat /opt/ibm/wlp/usr/servers/appServer/server.env | \
    podman exec -i liberty-server-02 su - liberty -c 'cat > /opt/ibm/wlp/usr/servers/appServer/server.env'

podman exec liberty-server-01 cat /opt/ibm/wlp/usr/servers/appServer/jvm.options | \
    podman exec -i liberty-server-02 su - liberty -c 'cat > /opt/ibm/wlp/usr/servers/appServer/jvm.options'

# Create security directory on server-02
podman exec liberty-server-02 su - liberty -c 'mkdir -p /opt/ibm/wlp/usr/servers/appServer/resources/security'
```

---

### Task 2.4: Generate SSL Certificates

**Expected: 20 minutes** | **Actual: ______**

**Run on: liberty-server-01 and liberty-server-02**

```bash
# ============================================================
# PODMAN: Enter container first
# podman exec -it liberty-server-01 bash
# ============================================================

su - liberty
cd /opt/ibm/wlp/usr/servers/appServer

# Generate keystore
/opt/ibm/wlp/bin/securityUtility createSSLCertificate \
    --server=appServer \
    --password=libertykeys \
    --validity=365 \
    --subject="CN=liberty-server-01,O=MyOrg,C=US"

# Create trust store
keytool -genkeypair -alias dummy \
    -keystore resources/security/trust.p12 \
    -storetype PKCS12 -storepass libertytrust \
    -keypass libertytrust -keyalg RSA -keysize 2048 \
    -validity 1 -dname "CN=dummy"

keytool -delete -alias dummy \
    -keystore resources/security/trust.p12 \
    -storepass libertytrust

# Verify
keytool -list -keystore resources/security/key.p12 \
    -storepass libertykeys -storetype PKCS12

exit
```

**Podman Shortcut** - Generate certs on both servers:
```bash
for container in liberty-server-01 liberty-server-02; do
    echo "=== Generating SSL certs on $container ==="
    podman exec $container su - liberty -c "
        cd /opt/ibm/wlp/usr/servers/appServer && \
        /opt/ibm/wlp/bin/securityUtility createSSLCertificate \
            --server=appServer --password=libertykeys --validity=365 \
            --subject='CN=$container,O=MyOrg,C=US' && \
        keytool -genkeypair -alias dummy \
            -keystore resources/security/trust.p12 \
            -storetype PKCS12 -storepass libertytrust \
            -keypass libertytrust -keyalg RSA -keysize 2048 \
            -validity 1 -dname 'CN=dummy' && \
        keytool -delete -alias dummy \
            -keystore resources/security/trust.p12 \
            -storepass libertytrust
    "
done
```

**Checkpoint 2.4:**
- [ ] key.p12 created
- [ ] trust.p12 created
- **Actual time: _______ minutes**

---

### Task 2.5: Configure Liberty Collective

**Expected: 25 minutes** | **Actual: ______**

A **Liberty Collective** provides centralized management (similar to WAS ND Cell but lighter).

#### Step 2.5.1: Create Collective Controller

**Run on: liberty-controller**

```bash
# ============================================================
# PODMAN: Enter container first
# podman exec -it liberty-controller bash
# ============================================================

su - liberty

# Create controller server
/opt/ibm/wlp/bin/server create collectiveController

# Configure controller
cat > /opt/ibm/wlp/usr/servers/collectiveController/server.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<server description="Liberty Collective Controller">
    
    <featureManager>
        <feature>collectiveController-1.0</feature>
        <feature>ssl-1.0</feature>
        <feature>adminCenter-1.0</feature>
        <feature>websocket-2.1</feature>
    </featureManager>

    <administrator-role>
        <user>admin</user>
    </administrator-role>
    
    <basicRegistry id="basic" realm="BasicRealm">
        <user name="admin" password="adminpassword"/>
    </basicRegistry>

    <httpEndpoint id="defaultHttpEndpoint" host="*"
                  httpPort="9080" httpsPort="9443" />

    <collectiveController>
        <serverIdentity>
            <hostName>liberty-controller-01</hostName>
        </serverIdentity>
    </collectiveController>

    <ssl id="defaultSSLConfig" keyStoreRef="defaultKeyStore" />
    
    <keyStore id="defaultKeyStore"
              location="${server.config.dir}/resources/security/key.p12"
              password="controllerkeys" type="PKCS12" />
</server>
EOF

# Create keystore
mkdir -p /opt/ibm/wlp/usr/servers/collectiveController/resources/security
/opt/ibm/wlp/bin/securityUtility createSSLCertificate \
    --server=collectiveController --password=controllerkeys --validity=365

# Create collective
/opt/ibm/wlp/bin/collective create collectiveController \
    --keystorePassword=controllerkeys

# Start controller
/opt/ibm/wlp/bin/server start collectiveController

# Verify it's running
/opt/ibm/wlp/bin/server status collectiveController

exit
```

#### Step 2.5.2: Join Members to Collective

**Run on: liberty-server-01 and liberty-server-02**

```bash
# ============================================================
# PODMAN: Enter container first
# podman exec -it liberty-server-01 bash
# ============================================================

su - liberty

# Join collective
/opt/ibm/wlp/bin/collective join appServer \
    --host=liberty-controller-01 \
    --port=9443 \
    --user=admin \
    --password=adminpassword \
    --keystorePassword=libertykeys

# Add include to server.xml
echo '    <include location="collective-member.xml"/>' >> \
    /opt/ibm/wlp/usr/servers/appServer/server.xml

# Start member
/opt/ibm/wlp/bin/server start appServer

exit

# Repeat for liberty-server-02
```

**Admin Center Access:**
- Physical servers: https://liberty-controller-01:9443/adminCenter
- Podman: https://localhost:9443/adminCenter
- Credentials: admin / adminpassword

**Checkpoint 2.5:**
- [ ] Controller created and running
- [ ] Members joined collective
- [ ] Admin Center accessible
- **Actual time: _______ minutes**

---

### Task 2.6: Verify Liberty Servers

**Expected: 10 minutes** | **Actual: ______**

```bash
# ============================================================
# PODMAN: Run from host machine
# ============================================================

# Check server status
podman exec liberty-server-01 su - liberty -c '/opt/ibm/wlp/bin/server status appServer'
podman exec liberty-server-02 su - liberty -c '/opt/ibm/wlp/bin/server status appServer'
podman exec liberty-controller su - liberty -c '/opt/ibm/wlp/bin/server status collectiveController'

# Test endpoints (from host, using mapped ports)
curl http://localhost:9080/health         # Server 1
curl http://localhost:9180/health         # Server 2
curl http://localhost:9080/health/ready
curl http://localhost:9080/metrics | head -20

# Or from inside containers
podman exec liberty-server-01 curl -s http://localhost:9080/health
```

**Checkpoint Phase 2 Complete:**
- [ ] Liberty installed on all 3 containers/servers
- [ ] appServer created on server-01 and server-02
- [ ] collectiveController created on controller
- [ ] SSL certificates generated
- [ ] Collective members joined
- [ ] All servers running and healthy
- **Total Phase 2 time: _______ minutes**

---

# Phase 3: Application Deployment

**Expected Time: 75 minutes**

### Task 3.1: Download JDBC Driver

**Expected: 10 minutes** | **Actual: ______**

```bash
sudo su - liberty
mkdir -p /opt/ibm/wlp/usr/shared/resources/jdbc
cd /opt/ibm/wlp/usr/shared/resources/jdbc
wget https://jdbc.postgresql.org/download/postgresql-42.7.1.jar
```

---

### Task 3.2: Build Sample Application

**Expected: 15 minutes** | **Actual: ______**

```bash
mkdir -p ~/liberty-test-app/src/main/java/com/example
mkdir -p ~/liberty-test-app/src/main/webapp/WEB-INF

# Create REST endpoint
cat > ~/liberty-test-app/src/main/java/com/example/HelloResource.java << 'EOF'
package com.example;

import jakarta.ws.rs.*;
import jakarta.ws.rs.core.*;
import java.util.*;

@Path("/hello")
public class HelloResource {
    @GET
    @Produces(MediaType.APPLICATION_JSON)
    public Response hello() {
        Map<String, Object> r = new HashMap<>();
        r.put("message", "Hello from Open Liberty!");
        r.put("server", System.getenv("HOSTNAME"));
        return Response.ok(r).build();
    }
}
EOF

# Create JAX-RS application
cat > ~/liberty-test-app/src/main/java/com/example/RestApplication.java << 'EOF'
package com.example;
import jakarta.ws.rs.*;

@ApplicationPath("/api")
public class RestApplication extends jakarta.ws.rs.core.Application {}
EOF

# Create pom.xml
cat > ~/liberty-test-app/pom.xml << 'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>hello-liberty</artifactId>
    <version>1.0.0</version>
    <packaging>war</packaging>
    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
    </properties>
    <dependencies>
        <dependency>
            <groupId>jakarta.platform</groupId>
            <artifactId>jakarta.jakartaee-api</artifactId>
            <version>10.0.0</version>
            <scope>provided</scope>
        </dependency>
    </dependencies>
    <build><finalName>hello-liberty</finalName></build>
</project>
EOF

# Build
cd ~/liberty-test-app
mvn clean package
```

---

### Task 3.3: Deploy Application

**Expected: 20 minutes** | **Actual: ______**

```bash
# Copy to dropins for auto-deployment
cp target/hello-liberty.war /opt/ibm/wlp/usr/servers/appServer/dropins/

# Watch logs
tail -f /opt/ibm/wlp/usr/servers/appServer/logs/messages.log
# Look for: CWWKZ0001I: Application hello-liberty started

# Test
curl http://localhost:9080/hello-liberty/api/hello
```

---

### Task 3.4: Configure Connection Pool

**Expected: 15 minutes** | **Actual: ______**

Update dataSource in server.xml with tuned pool settings.

---

### Task 3.5: Verify on Both Servers

**Expected: 15 minutes** | **Actual: ______**

```bash
for server in 192.168.68.88 192.168.68.83; do
    curl http://$server:9080/hello-liberty/api/hello
done
```

**Checkpoint Phase 3:** _______ minutes

---

# Phase 4: Load Balancer (NGINX)

**Expected Time: 75 minutes**

### Task 4.1: Install NGINX

**Expected: 10 minutes** | **Actual: ______**

```bash
sudo apt update && sudo apt install -y nginx
nginx -v
```

---

### Task 4.2: Configure Load Balancer

**Expected: 25 minutes** | **Actual: ______**

```bash
sudo cat > /etc/nginx/conf.d/liberty-upstream.conf << 'EOF'
upstream liberty_cluster {
    least_conn;
    server 192.168.68.88:9080 weight=1 max_fails=3 fail_timeout=30s;
    server 192.168.68.83:9080 weight=1 max_fails=3 fail_timeout=30s;
    keepalive 32;
}
EOF

sudo cat > /etc/nginx/sites-available/liberty << 'EOF'
server {
    listen 80;
    server_name liberty.local;
    
    location / {
        proxy_pass http://liberty_cluster;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
    
    location /health {
        proxy_pass http://liberty_cluster/health;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/liberty /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
```

---

### Task 4.3: SSL Certificates

**Expected: 20 minutes** | **Actual: ______**

```bash
sudo mkdir -p /etc/nginx/ssl
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/liberty.key \
    -out /etc/nginx/ssl/liberty.crt \
    -subj "/CN=liberty.local"
```

---

### Task 4.4: Test Load Balancer

**Expected: 20 minutes** | **Actual: ______**

```bash
sudo nginx -t
sudo systemctl reload nginx

# Test load balancing
for i in {1..10}; do
    curl -s http://liberty.local/hello-liberty/api/hello | jq -r '.server'
done
```

**Checkpoint Phase 4:** _______ minutes

---

# Phase 5: Security Configuration

**Expected Time: 80 minutes**

### Task 5.1: Liberty Security (30 min)
### Task 5.2: SSL Hardening (20 min)
### Task 5.3: Audit Logging (15 min)
### Task 5.4: Systemd Service (15 min)

```bash
sudo cat > /etc/systemd/system/liberty-appServer.service << 'EOF'
[Unit]
Description=Open Liberty - appServer
After=network.target

[Service]
Type=forking
User=liberty
ExecStart=/opt/ibm/wlp/bin/server start appServer
ExecStop=/opt/ibm/wlp/bin/server stop appServer
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable liberty-appServer
```

**Checkpoint Phase 5:** _______ minutes

---

# Phase 6: Monitoring Setup

**Expected Time: 100 minutes**

### Task 6.1: Install Prometheus (25 min)

```bash
PROM_VERSION="2.48.0"
wget https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz
tar xzf prometheus-*.tar.gz
sudo cp prometheus-*/prometheus /usr/local/bin/
```

### Task 6.2: Install Grafana (25 min)

```bash
sudo apt install -y grafana
sudo systemctl enable --now grafana-server
# Access: http://localhost:3000 (admin/admin)
```

### Task 6.3: Create Alert Rules (20 min)
### Task 6.4: Node Exporter (15 min)
### Task 6.5: Import Dashboards (15 min)

**Checkpoint Phase 6:** _______ minutes

---

# Final Summary

## Time Recording

| Phase | Expected | Actual | Variance |
|-------|----------|--------|----------|
| 1. Infrastructure | 135 min | _______ | _______ |
| 2. Liberty Install | 140 min | _______ | _______ |
| 3. Application | 75 min | _______ | _______ |
| 4. Load Balancer | 75 min | _______ | _______ |
| 5. Security | 80 min | _______ | _______ |
| 6. Monitoring | 100 min | _______ | _______ |
| **TOTAL** | **605 min** | _______ | _______ |

## Access URLs

### Physical/VM Servers

| Service | URL | Credentials |
|---------|-----|-------------|
| Liberty Server 1 | http://192.168.68.88:9080 | - |
| Liberty Server 2 | http://192.168.68.83:9080 | - |
| Admin Center | https://192.168.68.86:9443/adminCenter | admin/adminpassword |
| Load Balancer | http://192.168.68.86 | - |
| Prometheus | http://192.168.68.86:9090 | - |
| Grafana | http://192.168.68.86:3000 | admin/admin |

### Podman Demo (localhost)

| Service | URL | Credentials |
|---------|-----|-------------|
| Liberty Server 1 | http://localhost:9080 | - |
| Liberty Server 2 | http://localhost:9180 | - |
| Admin Center | https://localhost:9443/adminCenter | admin/adminpassword |
| Health Check S1 | http://localhost:9080/health | - |
| Health Check S2 | http://localhost:9180/health | - |
| Metrics S1 | http://localhost:9080/metrics | - |

## Podman Cleanup

When done with the demo:

```bash
# Stop all containers
podman stop liberty-controller liberty-server-01 liberty-server-02

# Remove containers
podman rm liberty-controller liberty-server-01 liberty-server-02

# Remove network
podman network rm liberty-net

# Or remove everything at once
podman rm -f liberty-controller liberty-server-01 liberty-server-02
podman network rm liberty-net
```

---

**Next**: Run automated deployment and compare timing!
