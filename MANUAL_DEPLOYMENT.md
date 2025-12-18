# Manual Deployment Guide

> **Purpose**: Complete step-by-step manual deployment with timing checkpoints.  
> **Target**:  Senior Middleware Application Server Engineer demonstration.  
> **Estimated Total Time**: ~5 hours (301 minutes)

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
- **Maven 3.6+** (for building sample application in Phase 3)
  ```bash
  # Ubuntu/Debian
  sudo apt install maven -y

  # macOS
  brew install maven

  # Verify
  mvn -version
  ```

---

# Phase 1: Infrastructure Setup

**Expected Time: 60 minutes**

> **Choose ONE option below**: Option A for physical/VM servers, Option B for Podman demo on a single machine.

---

## Option A: Physical/VM Servers

*Skip to Option B if using Podman for demo.*

### Task 1.1: Prepare Server 1 (liberty-server-01)

**Expected: 10 minutes** | **Actual: ______** | **Start Time: ______**

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
192.168.68.82  liberty-controller-01
192.168.68.86  liberty-server-01
192.168.68.88  liberty-server-02
EOF'
```

### Task 1.2: Prepare Server 2 (liberty-server-02)

**Expected: 10 minutes** | **Actual: ______**

Repeat Task 1.1 on second server (192.168.68.88), setting hostname to `liberty-server-02`.

### Task 1.3: Prepare Controller Server (liberty-controller-01)

**Expected: 10 minutes** | **Actual: ______**

Repeat Task 1.1 on controller server (192.168.68.86), setting hostname to `liberty-controller-01`.

### Task 1.4: Create Liberty User on All Servers

**Expected: 15 minutes (7 per server)** | **Actual: ______**

Run on **each server**:

```bash
sudo useradd -m -s /bin/bash -c "Open Liberty Service Account" liberty
sudo mkdir -p /opt/ibm/wlp /var/log/liberty /var/liberty/{apps,config,shared,dropins}
sudo chown -R liberty:liberty /opt/ibm /var/log/liberty /var/liberty
```

### Task 1.5: Configure Firewall Rules

**Expected: 8 minutes** | **Actual: ______**

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

**Expected: 5 minutes** | **Actual: 3 minutes.**

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

**Expected: 10 minutes** | **Actual: ______**

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

**Expected: 10 minutes** | **Actual: ______**

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

**Expected: 10 minutes** | **Actual: ______**

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

**Expected: 2 minutes** | **Actual: ______**

```bash
# List all running containers
podman ps

# Expected output:
# CONTAINER ID  IMAGE                  COMMAND         NAMES
# xxxxxxxxxxxx  docker.io/ubuntu:22.04 sleep infinity  liberty-controller
# xxxxxxxxxxxx  docker.io/ubuntu:22.04 sleep infinity  liberty-server-01
# xxxxxxxxxxxx  docker.io/ubuntu:22.04 sleep infinity  liberty-server-02

# Test network connectivity between containers (verify DNS resolution)
podman exec liberty-server-01 getent hosts liberty-controller
podman exec liberty-server-02 getent hosts liberty-server-01
podman exec liberty-controller getent hosts liberty-server-02

# Verify Java in all containers
podman exec liberty-controller java -version
podman exec liberty-server-01 java -version
podman exec liberty-server-02 java -version
```

**Checkpoint Option B Complete:**
- [ ] 3 containers running
- [ ] All containers can resolve each other by hostname
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

**Expected Time: 60 minutes**

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

**Expected: 7 minutes per server (22 total)** | **Actual: ______**

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

**Expected: 10 minutes** | **Actual: ______**

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

**Expected: 15 minutes** | **Actual: ______**

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
    <!-- FEATURES - Using umbrella features for compatibility                -->
    <!-- Open Liberty 24.0.0.1: Jakarta EE 10 + MicroProfile 6.1             -->
    <!-- =================================================================== -->
    <featureManager>
        <!-- Jakarta EE 10 Web Profile (includes servlet-6.0, pages-3.1, etc.) -->
        <feature>webProfile-10.0</feature>

        <!-- MicroProfile 6.1 (compatible with Jakarta EE 10) -->
        <!-- Includes: mpConfig-3.1, mpHealth-4.0, mpMetrics-5.1, mpOpenAPI-3.1 -->
        <feature>microProfile-6.1</feature>
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
    <!-- HEALTH & METRICS (no authentication for demo)                       -->
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

**Expected: 10 minutes** | **Actual: ______**

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

**Expected: 12 minutes** | **Actual: ______**

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

**Expected: 5 minutes** | **Actual: ______**

```bash
# ============================================================
# PODMAN: Run from host machine
# ============================================================

# Install curl on all containers (if not already installed)
for container in liberty-controller liberty-server-01 liberty-server-02; do
    podman exec $container apt install -y curl
done

# Check server status (primary verification)
podman exec liberty-server-01 su - liberty -c '/opt/ibm/wlp/bin/server status appServer'
podman exec liberty-server-02 su - liberty -c '/opt/ibm/wlp/bin/server status appServer'
podman exec liberty-controller su - liberty -c '/opt/ibm/wlp/bin/server status collectiveController'

# Test endpoints from inside containers
podman exec liberty-server-01 curl -s http://localhost:9080/health
podman exec liberty-server-01 curl -s http://localhost:9080/health/ready
podman exec liberty-server-02 curl -s http://localhost:9080/health
podman exec liberty-server-01 curl -s http://localhost:9080/metrics | head -20

# Alternative: Test from host if curl is installed on host machine
# curl http://localhost:9080/health         # Server 1 (mapped port)
# curl http://localhost:9180/health         # Server 2 (mapped port)
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

**Expected Time: 35 minutes**

> **Podman Users**: Tasks 3.1-3.2 run on your **host machine** (not inside containers).
> The built WAR file is then copied into each container in Task 3.3.

### Task 3.1: Download JDBC Driver (Optional)

**Expected: 5 minutes** | **Actual: ______**

*Skip this task if not using a database. The sample app doesn't require it.*

```bash
# On physical servers only (not needed for Podman demo)
sudo su - liberty
mkdir -p /opt/ibm/wlp/usr/shared/resources/jdbc
cd /opt/ibm/wlp/usr/shared/resources/jdbc
wget https://jdbc.postgresql.org/download/postgresql-42.7.1.jar
```

---

### Task 3.2: Build Sample Application

**Expected: 7 minutes** | **Actual: ______**

> **Run on host machine** - requires Maven (see Prerequisites)

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

**Expected: 10 minutes** | **Actual: ______**

#### Option A: Physical/VM Servers

```bash
# Copy to dropins for auto-deployment
cp target/hello-liberty.war /opt/ibm/wlp/usr/servers/appServer/dropins/

# Watch logs
tail -f /opt/ibm/wlp/usr/servers/appServer/logs/messages.log
# Look for: CWWKZ0001I: Application hello-liberty started

# Test
curl http://localhost:9080/hello-liberty/api/hello
```

#### Option B: Podman Containers

```bash
# Copy WAR to both containers (run from ~/liberty-test-app directory)
podman cp target/hello-liberty.war liberty-server-01:/opt/ibm/wlp/usr/servers/appServer/dropins/
podman cp target/hello-liberty.war liberty-server-02:/opt/ibm/wlp/usr/servers/appServer/dropins/

# Fix ownership
podman exec liberty-server-01 chown liberty:liberty /opt/ibm/wlp/usr/servers/appServer/dropins/hello-liberty.war
podman exec liberty-server-02 chown liberty:liberty /opt/ibm/wlp/usr/servers/appServer/dropins/hello-liberty.war

# Watch logs (Liberty auto-deploys from dropins)
podman exec liberty-server-01 tail -f /opt/ibm/wlp/usr/servers/appServer/logs/messages.log
# Look for: CWWKZ0001I: Application hello-liberty started

# Test both servers
podman exec liberty-server-01 curl -s http://localhost:9080/hello-liberty/api/hello
podman exec liberty-server-02 curl -s http://localhost:9080/hello-liberty/api/hello
```

---

### Task 3.4: Configure Connection Pool

**Expected: 7 minutes** | **Actual: ______**

Update dataSource in server.xml with tuned pool settings.

---

### Task 3.5: Verify on Both Servers

**Expected: 7 minutes** | **Actual: ______**

#### Physical/VM Servers
```bash
for server in 192.168.68.88 192.168.68.86; do
    curl http://$server:9080/hello-liberty/api/hello
done
```

#### Podman Containers
```bash
# From inside containers
podman exec liberty-server-01 curl -s http://localhost:9080/hello-liberty/api/hello
podman exec liberty-server-02 curl -s http://localhost:9080/hello-liberty/api/hello

# From host machine (using mapped ports)
curl -s http://localhost:9080/hello-liberty/api/hello   # Server 01
curl -s http://localhost:9180/hello-liberty/api/hello   # Server 02
```

**Checkpoint Phase 3:** _______ minutes

---

# Phase 4: Load Balancer (NGINX)

**Expected Time: 37 minutes**

> **Podman Users**: Skip to Option B to run NGINX as a container on the liberty-net network.

### Task 4.1: Install NGINX

**Expected: 5 minutes** | **Actual: ______**

#### Option A: Physical/VM Servers

```bash
sudo apt update && sudo apt install -y nginx
nginx -v
```

#### Option B: Podman Container

```bash
# Create NGINX config directory on host
mkdir -p ~/liberty-nginx

# Create NGINX configuration
cat > ~/liberty-nginx/nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    upstream liberty_cluster {
        least_conn;
        server liberty-server-01:9080;
        server liberty-server-02:9080;
    }

    server {
        listen 80;

        location / {
            proxy_pass http://liberty_cluster;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }

        location /health {
            proxy_pass http://liberty_cluster/health;
        }
    }
}
EOF

# Run NGINX container
podman run -d --name liberty-nginx \
    --hostname liberty-nginx \
    --network liberty-net \
    -p 8080:80 \
    -v ~/liberty-nginx/nginx.conf:/etc/nginx/nginx.conf:ro \
    docker.io/nginx:alpine

# Verify NGINX is running
podman ps | grep nginx
```

---

### Task 4.2: Configure Load Balancer

**Expected: 12 minutes** | **Actual: ______**

#### Option A: Physical/VM Servers

```bash
sudo cat > /etc/nginx/conf.d/liberty-upstream.conf << 'EOF'
upstream liberty_cluster {
    least_conn;
    server 192.168.68.88:9080 weight=1 max_fails=3 fail_timeout=30s;
    server 192.168.68.86:9080 weight=1 max_fails=3 fail_timeout=30s;
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

#### Option B: Podman Container

*Configuration was created in Task 4.1. Skip to Task 4.4 to test.*

---

### Task 4.3: SSL Certificates

**Expected: 10 minutes** | **Actual: ______**

#### Option A: Physical/VM Servers

```bash
sudo mkdir -p /etc/nginx/ssl
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/liberty.key \
    -out /etc/nginx/ssl/liberty.crt \
    -subj "/CN=liberty.local"
```

#### Option B: Podman Container

*Optional for demo - skip to Task 4.4 to test HTTP load balancing.*

---

### Task 4.4: Test Load Balancer

**Expected: 10 minutes** | **Actual: ______**

#### Option A: Physical/VM Servers

```bash
sudo nginx -t
sudo systemctl reload nginx

# Test load balancing
for i in {1..10}; do
    curl -s http://liberty.local/hello-liberty/api/hello | jq -r '.server'
done
```

#### Option B: Podman Container

```bash
# Test health endpoint through load balancer
curl -s http://localhost:8080/health

# Test load balancing - health check should succeed on both backends
for i in {1..6}; do
    curl -s http://localhost:8080/health
    echo ""
done

# If sample app is deployed (Phase 3), test the API endpoint
# The "server" field shows which Liberty server handled the request
for i in {1..6}; do
    curl -s http://localhost:8080/hello-liberty/api/hello
    echo ""
done
```

**Checkpoint Phase 4:** _______ minutes

---

# Phase 5: Security Configuration

**Expected Time: 40 minutes**

> **Podman Users**: Tasks 5.1-5.3 apply to both setups. Task 5.4 (Systemd) is for physical servers only.

### Task 5.1: Liberty Security

**Expected: 15 minutes** | **Actual: ______**

Configure basic authentication and secure the admin center.

#### Option A: Physical/VM Servers

```bash
# Add to server.xml - basic registry with admin user
cat >> /opt/ibm/wlp/usr/servers/appServer/server.xml << 'EOF'

    <!-- Basic Security Registry -->
    <basicRegistry id="basic" realm="BasicRealm">
        <user name="admin" password="admin123"/>
        <user name="operator" password="operator123"/>
    </basicRegistry>

    <administrator-role>
        <user>admin</user>
    </administrator-role>

    <reader-role>
        <user>operator</user>
    </reader-role>
EOF

# Restart server
sudo systemctl restart liberty-appServer
```

#### Option B: Podman Containers

```bash
# Update server.xml in both containers
for container in liberty-server-01 liberty-server-02; do
    podman exec $container su - liberty -c 'cat >> /opt/ibm/wlp/usr/servers/appServer/server.xml << '\''EOF'\''

    <!-- Basic Security Registry -->
    <basicRegistry id="basic" realm="BasicRealm">
        <user name="admin" password="admin123"/>
    </basicRegistry>

    <administrator-role>
        <user>admin</user>
    </administrator-role>
EOF'

    # Restart server
    podman exec $container su - liberty -c '/opt/ibm/wlp/bin/server stop appServer'
    podman exec $container su - liberty -c '/opt/ibm/wlp/bin/server start appServer'
done
```

---

### Task 5.2: SSL Hardening

**Expected: 10 minutes** | **Actual: ______**

Generate proper SSL certificates and configure TLS.

> **Note**: HTTPS endpoints (ports 9443/9444/9543) will not work until this task is completed. The simplified server.xml from Phase 2 only enables HTTP.

#### Option A: Physical/VM Servers

```bash
su - liberty
cd /opt/ibm/wlp/usr/servers/appServer

# Generate keystore with proper certificate
/opt/ibm/wlp/bin/securityUtility createSSLCertificate \
    --server=appServer \
    --password=LibertySecure123 \
    --validity=365 \
    --subject="CN=$(hostname),O=MyOrg,C=US"

# Update server.xml with SSL config
cat >> /opt/ibm/wlp/usr/servers/appServer/server.xml << 'EOF'

    <!-- SSL Configuration -->
    <ssl id="defaultSSLConfig"
         keyStoreRef="defaultKeyStore"
         sslProtocol="TLSv1.2,TLSv1.3" />

    <keyStore id="defaultKeyStore"
              location="${server.config.dir}/resources/security/key.p12"
              password="LibertySecure123"
              type="PKCS12" />
EOF
```

#### Option B: Podman Containers

```bash
# Generate SSL certs in both containers
for container in liberty-server-01 liberty-server-02; do
    echo "=== Generating SSL for $container ==="
    podman exec $container su - liberty -c '
        cd /opt/ibm/wlp/usr/servers/appServer
        /opt/ibm/wlp/bin/securityUtility createSSLCertificate \
            --server=appServer \
            --password=LibertySecure123 \
            --validity=365
    '
done

# Test HTTPS endpoints
curl -k https://localhost:9444/health   # Server 01
curl -k https://localhost:9543/health   # Server 02
```

---

### Task 5.3: Audit Logging

**Expected: 7 minutes** | **Actual: ______**

Enable audit logging for security events.

#### Option A: Physical/VM Servers

```bash
# Add audit configuration to server.xml
cat >> /opt/ibm/wlp/usr/servers/appServer/server.xml << 'EOF'

    <!-- Audit Logging -->
    <auditFileHandler maxFiles="10" maxFileSize="50" />

    <audit auditRef="auditFileHandler">
        <event name="JMX_MBEAN" outcome="SUCCESS"/>
        <event name="JMX_MBEAN" outcome="FAILURE"/>
        <event name="SECURITY_AUTHN" outcome="SUCCESS"/>
        <event name="SECURITY_AUTHN" outcome="FAILURE"/>
        <event name="SECURITY_AUTHZ" outcome="FAILURE"/>
    </audit>
EOF

# Restart and verify
sudo systemctl restart liberty-appServer
ls -la /opt/ibm/wlp/usr/servers/appServer/logs/audit*
```

#### Option B: Podman Containers

```bash
# Enable audit feature in both containers
for container in liberty-server-01 liberty-server-02; do
    podman exec $container su - liberty -c '
        # Add audit feature to featureManager
        sed -i "s|</featureManager>|    <feature>audit-1.0</feature>\n    </featureManager>|" \
            /opt/ibm/wlp/usr/servers/appServer/server.xml

        /opt/ibm/wlp/bin/server stop appServer
        /opt/ibm/wlp/bin/server start appServer
    '
done

# Check audit logs
podman exec liberty-server-01 ls -la /opt/ibm/wlp/usr/servers/appServer/logs/
```

---

### Task 5.4: Systemd Service

**Expected: 7 minutes** | **Actual: ______**

#### Option A: Physical/VM Servers

```bash
sudo cat > /etc/systemd/system/liberty-appServer.service << 'EOF'
[Unit]
Description=Open Liberty - appServer
After=network.target

[Service]
Type=forking
User=liberty
Group=liberty
Environment="JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64"
ExecStart=/opt/ibm/wlp/bin/server start appServer
ExecStop=/opt/ibm/wlp/bin/server stop appServer
ExecReload=/opt/ibm/wlp/bin/server stop appServer && /opt/ibm/wlp/bin/server start appServer
Restart=on-failure
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable liberty-appServer
sudo systemctl start liberty-appServer
sudo systemctl status liberty-appServer
```

#### Option B: Podman Containers

*Systemd is not used for containers. Instead, use Podman's restart policy or generate systemd units for containers:*

```bash
# Option 1: Restart policy (already running containers)
podman update --restart=always liberty-server-01
podman update --restart=always liberty-server-02
podman update --restart=always liberty-nginx

# Option 2: Generate systemd unit files for containers
mkdir -p ~/.config/systemd/user
podman generate systemd --name liberty-server-01 > ~/.config/systemd/user/liberty-server-01.service
podman generate systemd --name liberty-server-02 > ~/.config/systemd/user/liberty-server-02.service
podman generate systemd --name liberty-nginx > ~/.config/systemd/user/liberty-nginx.service

systemctl --user daemon-reload
systemctl --user enable liberty-server-01 liberty-server-02 liberty-nginx
```

**Checkpoint Phase 5:** _______ minutes

---

# Phase 6: Monitoring Setup

**Expected Time: 50 minutes**

> **Podman Users**: Skip to Option B to run Prometheus and Grafana as containers on the liberty-net network.

### Task 6.1: Install Prometheus

**Expected: 12 minutes** | **Actual: ______**

#### Option A: Physical/VM Servers

```bash
PROM_VERSION="2.48.0"
wget https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz
tar xzf prometheus-*.tar.gz
sudo cp prometheus-*/prometheus /usr/local/bin/
sudo cp prometheus-*/promtool /usr/local/bin/

# Create prometheus user and directories
sudo useradd --no-create-home --shell /bin/false prometheus
sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo chown prometheus:prometheus /etc/prometheus /var/lib/prometheus

# Create config
sudo cat > /etc/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'liberty'
    metrics_path: /metrics
    static_configs:
      - targets:
          - '192.168.68.88:9080'
          - '192.168.68.86:9080'
EOF

# Create systemd service
sudo cat > /etc/systemd/system/prometheus.service << 'EOF'
[Unit]
Description=Prometheus
After=network.target

[Service]
User=prometheus
ExecStart=/usr/local/bin/prometheus \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/var/lib/prometheus/
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now prometheus
```

#### Option B: Podman Container

```bash
# Create Prometheus config directory
mkdir -p ~/liberty-monitoring/prometheus

# Create Prometheus configuration
cat > ~/liberty-monitoring/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'liberty'
    metrics_path: /metrics
    static_configs:
      - targets:
          - 'liberty-server-01:9080'
          - 'liberty-server-02:9080'
        labels:
          environment: 'podman-demo'
EOF

# Run Prometheus container
podman run -d --name prometheus \
    --network liberty-net \
    -p 9090:9090 \
    -v ~/liberty-monitoring/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro \
    docker.io/prom/prometheus:latest

# Verify Prometheus is running
podman ps | grep prometheus
echo "Prometheus UI: http://localhost:9090"
```

---

### Task 6.2: Install Grafana

**Expected: 12 minutes** | **Actual: ______**

#### Option A: Physical/VM Servers

```bash
# Install Grafana
sudo apt-get install -y apt-transport-https software-properties-common
wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
echo "deb https://packages.grafana.com/oss/deb stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt-get update
sudo apt-get install -y grafana

sudo systemctl enable --now grafana-server
# Access: http://localhost:3000 (admin/admin)
```

#### Option B: Podman Container

```bash
# Run Grafana container
podman run -d --name grafana \
    --network liberty-net \
    -p 3000:3000 \
    -e "GF_SECURITY_ADMIN_PASSWORD=admin123" \
    docker.io/grafana/grafana:latest

# Verify Grafana is running
podman ps | grep grafana
echo "Grafana UI: http://localhost:3000 (admin/admin123)"
```

---

### Task 6.3: Create Alert Rules

**Expected: 10 minutes** | **Actual: ______**

#### Option A: Physical/VM Servers

```bash
sudo mkdir -p /etc/prometheus/rules

sudo cat > /etc/prometheus/rules/liberty-alerts.yml << 'EOF'
groups:
  - name: liberty-alerts
    rules:
      - alert: LibertyServerDown
        expr: up{job="liberty"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Liberty server {{ $labels.instance }} is down"

      - alert: LibertyHighCPU
        expr: base_cpu_processCpuLoad{job="liberty"} > 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU on {{ $labels.instance }}"

      - alert: LibertyHighHeapUsage
        expr: base_memory_usedHeap_bytes{job="liberty"} / base_memory_maxHeap_bytes{job="liberty"} > 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High heap usage on {{ $labels.instance }}"
EOF

# Update prometheus.yml to include rules
sudo sed -i '/^scrape_configs:/i rule_files:\n  - "/etc/prometheus/rules/*.yml"\n' /etc/prometheus/prometheus.yml

sudo systemctl restart prometheus
```

#### Option B: Podman Container

```bash
# Create alert rules
mkdir -p ~/liberty-monitoring/prometheus/rules

cat > ~/liberty-monitoring/prometheus/rules/liberty-alerts.yml << 'EOF'
groups:
  - name: liberty-alerts
    rules:
      - alert: LibertyServerDown
        expr: up{job="liberty"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Liberty server {{ $labels.instance }} is down"

      - alert: LibertyHighHeapUsage
        expr: base_memory_usedHeap_bytes{job="liberty"} / base_memory_maxHeap_bytes{job="liberty"} > 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High heap usage on {{ $labels.instance }}"
EOF

# Update Prometheus config to include rules
cat > ~/liberty-monitoring/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "/etc/prometheus/rules/*.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'liberty'
    metrics_path: /metrics
    static_configs:
      - targets:
          - 'liberty-server-01:9080'
          - 'liberty-server-02:9080'
EOF

# Restart Prometheus with rules volume
podman stop prometheus && podman rm prometheus

podman run -d --name prometheus \
    --network liberty-net \
    -p 9090:9090 \
    -v ~/liberty-monitoring/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro \
    -v ~/liberty-monitoring/prometheus/rules:/etc/prometheus/rules:ro \
    docker.io/prom/prometheus:latest
```

---

### Task 6.4: Node Exporter

**Expected: 7 minutes** | **Actual: ______**

Export host system metrics (CPU, memory, disk).

#### Option A: Physical/VM Servers

```bash
NODE_EXPORTER_VERSION="1.7.0"
wget https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
tar xzf node_exporter-*.tar.gz
sudo cp node_exporter-*/node_exporter /usr/local/bin/

sudo cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
ExecStart=/usr/local/bin/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter

# Add to Prometheus config
# targets: ['localhost:9100']
```

#### Option B: Podman Container

```bash
# Run Node Exporter container (exports HOST metrics)
podman run -d --name node-exporter \
    --network liberty-net \
    -p 9100:9100 \
    --pid=host \
    -v /:/host:ro,rslave \
    docker.io/prom/node-exporter:latest \
    --path.rootfs=/host

# Add node-exporter to Prometheus config
cat >> ~/liberty-monitoring/prometheus/prometheus.yml << 'EOF'

  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
EOF

# Restart Prometheus
podman restart prometheus

# Verify metrics
curl -s http://localhost:9100/metrics | head -20
```

---

### Task 6.5: Import Dashboards

**Expected: 7 minutes** | **Actual: ______**

Configure Grafana with Prometheus datasource and import dashboards.

#### Both Options (via Grafana UI)

1. **Add Prometheus Data Source:**
   - Open Grafana: http://localhost:3000
   - Login (admin/admin or admin/admin123)
   - Go to: Configuration → Data Sources → Add data source
   - Select: Prometheus
   - URL:
     - Physical: `http://localhost:9090`
     - Podman: `http://prometheus:9090`
   - Click: Save & Test

2. **Import Liberty Dashboard:**
   - Go to: Dashboards → Import
   - Dashboard ID: `14370` (Open Liberty MicroProfile Metrics)
   - Or ID: `1860` (Node Exporter Full)
   - Select Prometheus data source
   - Click: Import

3. **Verify Dashboards:**
   - Go to: Dashboards → Browse
   - Open the imported dashboard
   - Verify metrics are showing

#### Podman: Configure via API (Optional)

```bash
# Wait for Grafana to be ready
sleep 10

# Add Prometheus datasource via API
curl -X POST http://admin:admin123@localhost:3000/api/datasources \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Prometheus",
    "type": "prometheus",
    "url": "http://prometheus:9090",
    "access": "proxy",
    "isDefault": true
  }'

echo ""
echo "Grafana configured! Open http://localhost:3000"
echo "Import dashboard ID 14370 for Liberty metrics"
```

**Checkpoint Phase 6:** _______ minutes

---

# Final Summary

## Time Recording

| Phase | Expected | Actual | Variance |
|-------|----------|--------|----------|
| 1. Infrastructure | 67 min | _______ | _______ |
| 2. Liberty Install | 70 min | _______ | _______ |
| 3. Application | 37 min | _______ | _______ |
| 4. Load Balancer | 37 min | _______ | _______ |
| 5. Security | 40 min | _______ | _______ |
| 6. Monitoring | 50 min | _______ | _______ |
| **TOTAL** | **301 min** | _______ | _______ |

## Access URLs

### Physical/VM Servers

| Service | URL | Credentials |
|---------|-----|-------------|
| Liberty Server 1 | http://192.168.68.88:9080 | - |
| Liberty Server 2 | http://192.168.68.86:9080 | - |
| Admin Center | https://192.168.68.82:9443/adminCenter | admin/adminpassword |
| Load Balancer | http://192.168.68.82 | - |
| Prometheus | http://192.168.68.82:9090 | - |
| Grafana | http://192.168.68.82:3000 | admin/admin |

### Podman Demo (localhost)

| Service | URL | Credentials |
|---------|-----|-------------|
| Liberty Server 1 | http://localhost:9080 | - |
| Liberty Server 2 | http://localhost:9180 | - |
| NGINX Load Balancer | http://localhost:8080 | - |
| Health Check S1 | http://localhost:9080/health | - |
| Health Check S2 | http://localhost:9180/health | - |
| Metrics S1 | http://localhost:9080/metrics | - |
| Prometheus | http://localhost:9090 | - |
| Grafana | http://localhost:3000 | admin/admin123 |
| Node Exporter | http://localhost:9100/metrics | - |

## Podman Cleanup

When done with the demo:

```bash
# Stop all containers
podman stop liberty-server-01 liberty-server-02 liberty-nginx prometheus grafana node-exporter

# Remove containers
podman rm liberty-server-01 liberty-server-02 liberty-nginx prometheus grafana node-exporter

# Remove network
podman network rm liberty-net

# Or remove everything at once
podman rm -f liberty-server-01 liberty-server-02 liberty-nginx prometheus grafana node-exporter
podman network rm liberty-net

# Clean up config directories (optional)
rm -rf ~/liberty-nginx ~/liberty-monitoring
```

---

**Next**: Run automated deployment and compare timing!
