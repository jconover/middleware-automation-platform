#!/bin/bash
#===============================================================================
# Beelink Kubernetes Cluster - Complete Rebuild Script
#===============================================================================
# This script rebuilds the entire Kubernetes cluster from scratch, deploying
# all components in the correct dependency order.
#
# Cluster Configuration:
#   - k8s-master-01: 192.168.68.93 (Control Plane + Worker)
#   - k8s-worker-01: 192.168.68.86 (Worker)
#   - k8s-worker-02: 192.168.68.88 (Worker)
#   - MetalLB Pool: 192.168.68.200-210
#   - Pod CIDR: 10.244.0.0/16
#   - Service CIDR: 10.96.0.0/12
#
# Prerequisites:
#   - All nodes prepared with containerd, kubeadm, kubelet
#   - SSH access to all nodes (for cluster init)
#   - kubectl, helm installed locally
#
# Usage:
#   ./rebuild.sh [OPTIONS]
#
# Options:
#   --init-cluster      Initialize kubeadm cluster (only if not exists)
#   --skip-init         Skip cluster initialization
#   --skip-monitoring   Skip monitoring stack
#   --skip-apps         Skip application deployment
#   --dry-run           Show what would be done without executing
#   -y, --yes           Skip confirmation prompts
#   -h, --help          Show this help message
#
#===============================================================================

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Cluster configuration
MASTER_IP="192.168.68.93"
WORKER_IPS=("192.168.68.86" "192.168.68.88")
POD_CIDR="10.244.0.0/16"
SERVICE_CIDR="10.96.0.0/12"
K8S_VERSION="v1.33.1"
CLUSTER_NAME="beelink-homelab"

# MetalLB IP assignments
METALLB_POOL_START="192.168.68.200"
METALLB_POOL_END="192.168.68.210"
IP_INGRESS="192.168.68.200"
IP_PROMETHEUS="192.168.68.201"
IP_GRAFANA="192.168.68.202"
IP_ALERTMANAGER="192.168.68.203"
IP_LOKI="192.168.68.204"
IP_JAEGER="192.168.68.205"
IP_JENKINS="192.168.68.206"

# Log file
LOG_DIR="${PROJECT_ROOT}/logs"
LOG_FILE="${LOG_DIR}/rebuild-$(date +%Y%m%d-%H%M%S).log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default options
INIT_CLUSTER=false
SKIP_INIT=false
SKIP_MONITORING=false
SKIP_APPS=false
DRY_RUN=false
AUTO_YES=false

#===============================================================================
# Functions
#===============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        INFO)   echo -e "${BLUE}[INFO]${NC} $message" ;;
        WARN)   echo -e "${YELLOW}[WARN]${NC} $message" ;;
        ERROR)  echo -e "${RED}[ERROR]${NC} $message" ;;
        OK)     echo -e "${GREEN}[OK]${NC} $message" ;;
        STEP)   echo -e "\n${GREEN}==>${NC} ${YELLOW}$message${NC}" ;;
        PHASE)  echo -e "\n${CYAN}======================================${NC}"
                echo -e "${CYAN}  $message${NC}"
                echo -e "${CYAN}======================================${NC}" ;;
    esac

    if [[ -f "$LOG_FILE" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi
}

run_cmd() {
    local description="$1"
    shift
    local cmd="$*"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would execute: $cmd"
        return 0
    fi

    log INFO "$description"
    if eval "$cmd" 2>&1 | tee -a "$LOG_FILE"; then
        return 0
    else
        log ERROR "Command failed: $cmd"
        return 1
    fi
}

wait_for_pods() {
    local namespace="$1"
    local selector="$2"
    local timeout="${3:-300}"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would wait for pods: $selector in $namespace"
        return 0
    fi

    log INFO "Waiting for pods ($selector) in $namespace..."
    kubectl wait --for=condition=ready pod -l "$selector" -n "$namespace" --timeout="${timeout}s" 2>/dev/null || {
        log WARN "Timeout waiting for pods - continuing anyway"
        return 0
    }
}

confirm() {
    local message="$1"
    if [[ "$AUTO_YES" == "true" ]]; then
        return 0
    fi

    echo -e "${YELLOW}$message${NC}"
    read -p "Continue? [y/N] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

show_help() {
    head -45 "$0" | tail -35
    exit 0
}

check_prerequisites() {
    log STEP "Checking prerequisites"

    local missing=()

    for cmd in kubectl helm jq curl; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log ERROR "Missing required commands: ${missing[*]}"
        exit 1
    fi

    # Add Helm repos
    log INFO "Adding Helm repositories..."
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
    helm repo add longhorn https://charts.longhorn.io 2>/dev/null || true
    helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
    helm repo add jenkins https://charts.jenkins.io 2>/dev/null || true
    helm repo add external-secrets https://charts.external-secrets.io 2>/dev/null || true
    helm repo update 2>/dev/null || true

    log OK "Prerequisites check passed"
}

#===============================================================================
# CNI Installation Helper (called from phase_cluster_init)
#===============================================================================

install_cni_calico() {
    log INFO "Installing CNI (Calico)..."

    # Check if already installed
    if kubectl get namespace calico-system &>/dev/null; then
        log INFO "Calico already installed, skipping"
        return 0
    fi

    # Install Calico operator
    log INFO "Installing Calico operator..."
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml

    # Wait for operator to be ready
    log INFO "Waiting for Calico operator..."
    sleep 15
    kubectl wait --for=condition=Available deployment/tigera-operator -n tigera-operator --timeout=120s 2>/dev/null || {
        log WARN "Operator not fully ready, continuing..."
    }

    # Configure Calico with pod CIDR
    log INFO "Configuring Calico with pod CIDR: ${POD_CIDR}..."
    cat << EOF | kubectl apply -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: ${POD_CIDR}
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
  nodeMetricsPort: 9091
---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
EOF

    # Wait for Calico node pods (critical for node Ready status)
    log INFO "Waiting for Calico node pods to be ready..."
    sleep 30

    # Wait for calico-node daemonset on at least the master
    local retries=0
    local max_retries=30
    while [[ $retries -lt $max_retries ]]; do
        if kubectl get pods -n calico-system -l k8s-app=calico-node 2>/dev/null | grep -q "Running"; then
            log OK "Calico node pod is running"
            break
        fi
        log INFO "Waiting for Calico node pod... (attempt $((retries+1))/$max_retries)"
        sleep 10
        ((retries++))
    done

    if [[ $retries -eq $max_retries ]]; then
        log WARN "Calico node pod not fully ready after ${max_retries} attempts, continuing anyway..."
    fi

    log OK "CNI (Calico) installed"
}

#===============================================================================
# Phase 1: Cluster Initialization
#===============================================================================

phase_cluster_init() {
    if [[ "$SKIP_INIT" == "true" ]]; then
        log INFO "Skipping cluster initialization (--skip-init specified)"
        return 0
    fi

    # Check if cluster already exists
    if kubectl cluster-info &>/dev/null; then
        if [[ "$INIT_CLUSTER" != "true" ]]; then
            log INFO "Cluster already exists. Use --init-cluster to reinitialize."
            return 0
        fi
    fi

    if [[ "$INIT_CLUSTER" != "true" ]]; then
        log WARN "Cluster not accessible. Use --init-cluster to initialize."
        return 0
    fi

    log PHASE "Phase 1: Initializing Kubernetes Cluster"

    if ! confirm "Initialize kubeadm cluster on $MASTER_IP?"; then
        log INFO "Skipping cluster initialization"
        return 0
    fi

    # Create kubeadm config
    # MINIMAL configuration for K8s 1.33.1 - only essential settings
    # v1beta4 API is required for K8s 1.31+
    # All extraArgs, extraVolumes, timeouts removed to use tested defaults
    local kubeadm_config="/tmp/kubeadm-config.yaml"
    cat > "$kubeadm_config" << EOF
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: "${MASTER_IP}"
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
  taints: []
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: ${K8S_VERSION}
controlPlaneEndpoint: "${MASTER_IP}:6443"
clusterName: "${CLUSTER_NAME}"
networking:
  podSubnet: "${POD_CIDR}"
  serviceSubnet: "${SERVICE_CIDR}"
EOF

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would initialize cluster with config:"
        cat "$kubeadm_config"
        return 0
    fi

    # Copy config to master
    log INFO "Copying kubeadm config to $MASTER_IP..."
    scp "$kubeadm_config" "${MASTER_IP}:/tmp/kubeadm-config.yaml"

    # Pre-pull required container images (prevents silent failures during init)
    log INFO "Pre-pulling required Kubernetes images on $MASTER_IP..."
    ssh "$MASTER_IP" "sudo kubeadm config images pull --config=/tmp/kubeadm-config.yaml" || {
        log ERROR "Failed to pull required images. Checking available images..."
        ssh "$MASTER_IP" "sudo kubeadm config images list --config=/tmp/kubeadm-config.yaml"
        log ERROR "Please check network connectivity to registry.k8s.io"
        return 1
    }

    # Verify images are available
    log INFO "Verifying images on $MASTER_IP..."
    ssh "$MASTER_IP" "sudo crictl images | grep -E 'kube-apiserver|kube-controller|kube-scheduler|etcd|coredns|pause' || true"

    # CRITICAL: Stop kubelet before kubeadm init
    # The kubelet package has Restart=always, so it may have started after node-prep
    # or during image pull. kubeadm preflight checks fail if port 10250 is in use.
    log INFO "Ensuring kubelet is stopped before kubeadm init..."

    # First, unmask kubelet if it was masked during teardown
    # A masked service cannot be started by kubeadm
    ssh "$MASTER_IP" "sudo systemctl unmask kubelet 2>/dev/null || true"

    # Stop kubelet if it is running
    ssh "$MASTER_IP" "sudo systemctl stop kubelet 2>/dev/null || true"

    # Force kill any remaining kubelet processes
    ssh "$MASTER_IP" "sudo pkill -9 kubelet 2>/dev/null || true"

    # Wait a moment for the process to fully terminate
    sleep 2

    # Verify port 10250 is free
    if ssh "$MASTER_IP" "sudo ss -tlnp | grep -q ':10250 '"; then
        log ERROR "Port 10250 is still in use! Attempting to identify the process..."
        ssh "$MASTER_IP" "sudo ss -tlnp | grep ':10250 '"
        # Use fuser to forcibly kill the process holding the port
        ssh "$MASTER_IP" "sudo fuser -k 10250/tcp 2>/dev/null || true"
        sleep 2
        # Final check
        if ssh "$MASTER_IP" "sudo ss -tlnp | grep -q ':10250 '"; then
            log ERROR "Port 10250 is STILL in use after kill attempts!"
            log ERROR "Please manually check what is using port 10250 on $MASTER_IP:"
            log ERROR "  ssh $MASTER_IP 'sudo ss -tlnp | grep :10250'"
            return 1
        fi
    fi
    log OK "Port 10250 is free on $MASTER_IP"

    # Initialize control plane
    log INFO "Initializing control plane on $MASTER_IP..."
    ssh "$MASTER_IP" "sudo kubeadm init --config=/tmp/kubeadm-config.yaml --upload-certs"

    # Get kubeconfig (file is owned by root, so copy via sudo first)
    log INFO "Retrieving kubeconfig..."
    mkdir -p ~/.kube
    ssh "$MASTER_IP" "sudo cat /etc/kubernetes/admin.conf" > ~/.kube/config
    chmod 600 ~/.kube/config

    # CRITICAL: Install CNI before waiting for nodes or joining workers
    # Nodes cannot become Ready without a CNI plugin installed
    log INFO "Installing CNI before joining workers..."
    install_cni_calico

    # Wait for master node to be Ready (now possible with CNI installed)
    log INFO "Waiting for master node to be ready..."
    kubectl wait --for=condition=ready node --all --timeout=180s || {
        log WARN "Master node not fully ready, continuing with worker join..."
    }

    # Get join command
    log INFO "Getting join command..."
    local join_cmd
    join_cmd=$(ssh "$MASTER_IP" "kubeadm token create --print-join-command")

    # Join workers
    for worker in "${WORKER_IPS[@]}"; do
        log INFO "Preparing worker node: $worker"

        # Unmask and stop kubelet on worker (same as master)
        ssh "$worker" "sudo systemctl unmask kubelet 2>/dev/null || true"
        ssh "$worker" "sudo systemctl stop kubelet 2>/dev/null || true"
        ssh "$worker" "sudo pkill -9 kubelet 2>/dev/null || true"
        sleep 1

        # Verify port 10250 is free on worker
        if ssh "$worker" "sudo ss -tlnp | grep -q ':10250 '"; then
            log WARN "Port 10250 in use on $worker, attempting to free it..."
            ssh "$worker" "sudo fuser -k 10250/tcp 2>/dev/null || true"
            sleep 2
        fi

        log INFO "Joining worker node: $worker"
        ssh "$worker" "sudo $join_cmd"
    done

    # Wait for all nodes (master + workers) to be Ready
    # CNI is already installed, so nodes should become Ready quickly
    log INFO "Waiting for all nodes to be ready..."
    sleep 15
    kubectl wait --for=condition=ready node --all --timeout=300s || {
        log WARN "Some nodes not fully ready, check with 'kubectl get nodes'"
    }

    log OK "Cluster initialized successfully (with CNI)"
}

#===============================================================================
# Phase 2: CNI Verification (Calico already installed during cluster init)
#===============================================================================

phase_cni() {
    log PHASE "Phase 2: Verifying CNI (Calico)"

    # CNI should already be installed during phase_cluster_init
    # This phase verifies and repairs if needed
    if kubectl get namespace calico-system &>/dev/null; then
        log INFO "Calico CNI verified - checking pod status..."

        # Verify Calico pods are running
        if kubectl get pods -n calico-system -l k8s-app=calico-node 2>/dev/null | grep -q "Running"; then
            log OK "Calico node pods are running"
        else
            log WARN "Calico node pods not ready, waiting..."
            kubectl wait --for=condition=Available --timeout=120s deployment/calico-kube-controllers -n calico-system 2>/dev/null || true
        fi

        # Show Calico status
        log INFO "Calico pod status:"
        kubectl get pods -n calico-system 2>/dev/null || true
        return 0
    fi

    # If CNI is missing (e.g., --skip-init was used), install it now
    log WARN "CNI not found - installing Calico..."
    install_cni_calico

    log OK "Calico CNI verified"
}

#===============================================================================
# Phase 3: Storage (Longhorn)
#===============================================================================

phase_storage() {
    log PHASE "Phase 3: Installing Storage (Longhorn)"

    # Check if Longhorn is already installed
    if kubectl get namespace longhorn-system &>/dev/null; then
        log INFO "Longhorn already installed"
        return 0
    fi

    # Install Longhorn
    run_cmd "Installing Longhorn" \
        "helm upgrade --install longhorn longhorn/longhorn \
            --namespace longhorn-system \
            --create-namespace \
            --set defaultSettings.defaultDataPath='/var/lib/longhorn' \
            --set defaultSettings.defaultReplicaCount=2 \
            --set service.ui.type=NodePort \
            --set service.ui.nodePort=30001 \
            --wait --timeout 10m"

    # Set as default StorageClass
    run_cmd "Setting Longhorn as default StorageClass" \
        "kubectl patch storageclass longhorn -p '{\"metadata\": {\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"true\"}}}'"

    log OK "Longhorn storage installed"
}

#===============================================================================
# Phase 4: MetalLB
#===============================================================================

phase_metallb() {
    log PHASE "Phase 4: Installing MetalLB"

    # Check if MetalLB is already installed
    if kubectl get namespace metallb-system &>/dev/null; then
        log INFO "MetalLB namespace exists, checking configuration..."
    else
        run_cmd "Installing MetalLB" \
            "kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml"

        # Wait for MetalLB pods
        log INFO "Waiting for MetalLB pods..."
        sleep 20
        kubectl wait --namespace metallb-system \
            --for=condition=ready pod \
            --selector=app=metallb \
            --timeout=120s 2>/dev/null || true
    fi

    # Configure IP pool
    cat << EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: homelab-pool
  namespace: metallb-system
spec:
  addresses:
    - ${METALLB_POOL_START}-${METALLB_POOL_END}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: homelab-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - homelab-pool
EOF

    log OK "MetalLB installed and configured"
}

#===============================================================================
# Phase 5: Namespaces
#===============================================================================

phase_namespaces() {
    log PHASE "Phase 5: Creating Namespaces"

    # Create namespaces with labels
    for ns in liberty monitoring jenkins awx tracing secrets-source ingress-nginx argocd; do
        if ! kubectl get namespace "$ns" &>/dev/null; then
            run_cmd "Creating namespace $ns" \
                "kubectl create namespace $ns"
        fi
    done

    # Label namespaces for NetworkPolicy selectors
    kubectl label namespace liberty name=liberty --overwrite 2>/dev/null || true
    kubectl label namespace monitoring name=monitoring --overwrite 2>/dev/null || true
    kubectl label namespace jenkins name=jenkins --overwrite 2>/dev/null || true
    kubectl label namespace awx name=awx --overwrite 2>/dev/null || true
    kubectl label namespace tracing name=tracing --overwrite 2>/dev/null || true
    kubectl label namespace ingress-nginx kubernetes.io/metadata.name=ingress-nginx --overwrite 2>/dev/null || true

    # Apply Pod Security Standards
    log INFO "Applying Pod Security Standards..."
    kubectl label namespace liberty \
        pod-security.kubernetes.io/enforce=restricted \
        pod-security.kubernetes.io/warn=restricted \
        pod-security.kubernetes.io/audit=restricted \
        --overwrite 2>/dev/null || true

    kubectl label namespace monitoring \
        pod-security.kubernetes.io/enforce=baseline \
        pod-security.kubernetes.io/warn=restricted \
        --overwrite 2>/dev/null || true

    kubectl label namespace jenkins \
        pod-security.kubernetes.io/enforce=baseline \
        pod-security.kubernetes.io/warn=baseline \
        --overwrite 2>/dev/null || true

    log OK "Namespaces created and labeled"
}

#===============================================================================
# Phase 6: cert-manager
#===============================================================================

phase_cert_manager() {
    log PHASE "Phase 6: Installing cert-manager"

    if kubectl get namespace cert-manager &>/dev/null; then
        log INFO "cert-manager already installed"
        return 0
    fi

    run_cmd "Installing cert-manager" \
        "kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml"

    # Wait for cert-manager
    log INFO "Waiting for cert-manager..."
    sleep 20
    kubectl wait --for=condition=Available deployment --all -n cert-manager --timeout=300s 2>/dev/null || true

    # Apply ClusterIssuer if it exists
    if [[ -f "${PROJECT_ROOT}/kubernetes/base/certificates/cluster-issuer.yaml" ]]; then
        sleep 10  # Give webhooks time to start
        run_cmd "Applying ClusterIssuer" \
            "kubectl apply -f '${PROJECT_ROOT}/kubernetes/base/certificates/cluster-issuer.yaml'" || true
    fi

    log OK "cert-manager installed"
}

#===============================================================================
# Phase 7: NGINX Ingress Controller
#===============================================================================

phase_ingress() {
    log PHASE "Phase 7: Installing NGINX Ingress Controller"

    run_cmd "Installing ingress-nginx" \
        "helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
            --namespace ingress-nginx \
            --set controller.service.type=LoadBalancer \
            --set controller.service.loadBalancerIP=${IP_INGRESS} \
            --set controller.service.annotations.\"metallb\\.universe\\.tf/loadBalancerIPs\"=${IP_INGRESS} \
            --set controller.metrics.enabled=true \
            --set controller.metrics.serviceMonitor.enabled=true \
            --wait --timeout 5m"

    log OK "NGINX Ingress Controller installed"
}

#===============================================================================
# Phase 8: Monitoring Stack
#===============================================================================

phase_monitoring() {
    if [[ "$SKIP_MONITORING" == "true" ]]; then
        log INFO "Skipping monitoring stack (--skip-monitoring specified)"
        return 0
    fi

    log PHASE "Phase 8: Installing Monitoring Stack"

    # Install kube-prometheus-stack
    run_cmd "Installing kube-prometheus-stack" \
        "helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
            --namespace monitoring \
            --set prometheus.service.type=LoadBalancer \
            --set prometheus.service.loadBalancerIP=${IP_PROMETHEUS} \
            --set grafana.service.type=LoadBalancer \
            --set grafana.service.loadBalancerIP=${IP_GRAFANA} \
            --set alertmanager.service.type=LoadBalancer \
            --set alertmanager.service.loadBalancerIP=${IP_ALERTMANAGER} \
            --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
            --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
            --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false \
            --set prometheus.prometheusSpec.retention=15d \
            --set grafana.persistence.enabled=true \
            --set grafana.persistence.size=10Gi \
            --set grafana.sidecar.dashboards.enabled=true \
            --set grafana.sidecar.dashboards.label=grafana_dashboard \
            --set grafana.sidecar.datasources.enabled=true \
            --set grafana.sidecar.datasources.label=grafana_datasource \
            --wait --timeout 15m"

    # Wait for Prometheus stack
    wait_for_pods "monitoring" "app.kubernetes.io/instance=prometheus" 300

    # Deploy Loki
    log INFO "Deploying Loki..."
    if [[ -d "${PROJECT_ROOT}/kubernetes/base/monitoring/loki" ]]; then
        run_cmd "Deploying Loki" \
            "kubectl apply -k '${PROJECT_ROOT}/kubernetes/base/monitoring/loki/'"
        sleep 20
        wait_for_pods "monitoring" "app=loki" 120
    fi

    # Deploy Promtail
    log INFO "Deploying Promtail..."
    if [[ -d "${PROJECT_ROOT}/kubernetes/base/monitoring/promtail" ]]; then
        run_cmd "Deploying Promtail" \
            "kubectl apply -k '${PROJECT_ROOT}/kubernetes/base/monitoring/promtail/'"
        wait_for_pods "monitoring" "app=promtail" 120
    fi

    # Deploy Jaeger (optional)
    if [[ -d "${PROJECT_ROOT}/kubernetes/base/monitoring/jaeger" ]]; then
        log INFO "Deploying Jaeger..."
        run_cmd "Deploying Jaeger" \
            "kubectl apply -k '${PROJECT_ROOT}/kubernetes/base/monitoring/jaeger/'" || true
    fi

    # Deploy Liberty monitoring resources
    if [[ -f "${PROJECT_ROOT}/kubernetes/base/monitoring/kustomization.yaml" ]]; then
        log INFO "Deploying Liberty monitoring resources..."
        run_cmd "Deploying ServiceMonitors and PrometheusRules" \
            "kubectl apply -k '${PROJECT_ROOT}/kubernetes/base/monitoring/'"
    fi

    # Import Grafana dashboards
    log INFO "Importing Grafana dashboards..."
    if [[ -f "${PROJECT_ROOT}/monitoring/grafana/dashboards/k8s-liberty.json" ]]; then
        kubectl create configmap liberty-k8s-dashboard \
            --namespace monitoring \
            --from-file=liberty-k8s.json="${PROJECT_ROOT}/monitoring/grafana/dashboards/k8s-liberty.json" \
            --dry-run=client -o yaml | kubectl apply -f -
        kubectl label configmap liberty-k8s-dashboard -n monitoring grafana_dashboard=1 --overwrite 2>/dev/null || true
    fi

    log OK "Monitoring stack installed"
}

#===============================================================================
# Phase 9: External Secrets
#===============================================================================

phase_external_secrets() {
    log PHASE "Phase 9: Installing External Secrets Operator"

    # Install ESO
    run_cmd "Installing External Secrets Operator" \
        "helm upgrade --install external-secrets external-secrets/external-secrets \
            --namespace external-secrets \
            --create-namespace \
            --wait --timeout 5m"

    # Wait for ESO
    wait_for_pods "external-secrets" "app.kubernetes.io/name=external-secrets" 120

    # Apply ClusterSecretStore (local kubernetes backend)
    if [[ -f "${PROJECT_ROOT}/kubernetes/base/external-secrets/local-clustersecretstore.yaml" ]]; then
        log INFO "Creating source secrets namespace..."
        kubectl create namespace secrets-source 2>/dev/null || true

        # Create ESO service account for local store
        log INFO "Setting up ESO local backend..."

        # Apply the ClusterSecretStore
        sleep 10  # Wait for webhook
        run_cmd "Applying ClusterSecretStore" \
            "kubectl apply -k '${PROJECT_ROOT}/kubernetes/base/external-secrets/'" || true
    fi

    log OK "External Secrets Operator installed"
}

#===============================================================================
# Phase 10: Network Policies
#===============================================================================

phase_network_policies() {
    log PHASE "Phase 10: Applying Network Policies"

    if [[ -d "${PROJECT_ROOT}/kubernetes/base/network-policies" ]]; then
        run_cmd "Applying network policies" \
            "kubectl apply -k '${PROJECT_ROOT}/kubernetes/base/network-policies/'"
    else
        log WARN "Network policies directory not found"
    fi

    log OK "Network policies applied"
}

#===============================================================================
# Phase 11: Secrets Setup
#===============================================================================

phase_secrets() {
    log PHASE "Phase 11: Setting Up Secrets"

    # Check if secrets already exist
    if kubectl get secret liberty-secrets -n liberty &>/dev/null; then
        log INFO "Liberty secrets already exist"
    else
        log INFO "Creating placeholder secrets..."

        # Create placeholder Liberty secrets (manual creation for homelab)
        kubectl create secret generic liberty-secrets \
            --namespace=liberty \
            --from-literal=db.password="$(openssl rand -base64 24)" \
            --from-literal=db.username='liberty' \
            --from-literal=db.host='postgres.database.svc.cluster.local' \
            --from-literal=db.port='5432' \
            --from-literal=db.name='libertydb' \
            --from-literal=redis.auth="$(openssl rand -base64 32)" \
            --from-literal=redis.host='redis.database.svc.cluster.local' \
            --from-literal=redis.port='6379' \
            --dry-run=client -o yaml | kubectl apply -f -
    fi

    # Create TLS secret for Ingress
    if ! kubectl get secret liberty-tls-secret -n liberty &>/dev/null; then
        log INFO "Creating self-signed TLS certificate..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /tmp/liberty-tls.key \
            -out /tmp/liberty-tls.crt \
            -subj "/CN=liberty.local/O=Middleware Platform" \
            -addext "subjectAltName=DNS:liberty.local,DNS:*.liberty.local" 2>/dev/null

        kubectl create secret tls liberty-tls-secret \
            --namespace=liberty \
            --cert=/tmp/liberty-tls.crt \
            --key=/tmp/liberty-tls.key \
            --dry-run=client -o yaml | kubectl apply -f -

        rm -f /tmp/liberty-tls.key /tmp/liberty-tls.crt
    fi

    log OK "Secrets configured"
}

#===============================================================================
# Phase 12: Application Deployment
#===============================================================================

phase_applications() {
    if [[ "$SKIP_APPS" == "true" ]]; then
        log INFO "Skipping application deployment (--skip-apps specified)"
        return 0
    fi

    log PHASE "Phase 12: Deploying Applications"

    # Deploy Liberty using homelab overlay
    if [[ -d "${PROJECT_ROOT}/kubernetes/overlays/local-homelab" ]]; then
        run_cmd "Deploying Liberty application" \
            "kubectl apply -k '${PROJECT_ROOT}/kubernetes/overlays/local-homelab/'"

        # Wait for deployment
        log INFO "Waiting for Liberty deployment..."
        kubectl rollout status deployment/liberty-app -n liberty --timeout=300s 2>/dev/null || true
    else
        log WARN "Local homelab overlay not found"
    fi

    log OK "Applications deployed"
}

#===============================================================================
# Phase 13: CI/CD Tools
#===============================================================================

phase_cicd() {
    if [[ "$SKIP_APPS" == "true" ]]; then
        log INFO "Skipping CI/CD tools (--skip-apps specified)"
        return 0
    fi

    log PHASE "Phase 13: Installing CI/CD Tools"

    # Create Jenkins admin secret
    if ! kubectl get secret jenkins-admin-secret -n jenkins &>/dev/null; then
        local jenkins_pass
        jenkins_pass=$(openssl rand -base64 24)
        kubectl create secret generic jenkins-admin-secret \
            --namespace jenkins \
            --from-literal=jenkins-admin-password="$jenkins_pass"
        log INFO "Jenkins admin password: $jenkins_pass"
        echo "Jenkins admin password: $jenkins_pass" >> "${LOG_DIR}/credentials.txt"
    fi

    # Install Jenkins
    if [[ -f "${PROJECT_ROOT}/ci-cd/jenkins/kubernetes/values.yaml" ]]; then
        run_cmd "Installing Jenkins" \
            "helm upgrade --install jenkins jenkins/jenkins \
                --namespace jenkins \
                --values '${PROJECT_ROOT}/ci-cd/jenkins/kubernetes/values.yaml' \
                --set controller.serviceType=LoadBalancer \
                --set controller.loadBalancerIP=${IP_JENKINS} \
                --wait --timeout 15m" || true
    else
        log WARN "Jenkins values file not found, skipping Jenkins installation"
    fi

    log OK "CI/CD tools installed"
}

#===============================================================================
# Phase 14: GitOps (ArgoCD) - Optional
#===============================================================================

phase_gitops() {
    log PHASE "Phase 14: Installing ArgoCD (Optional)"

    if ! confirm "Install ArgoCD for GitOps?"; then
        log INFO "Skipping ArgoCD installation"
        return 0
    fi

    # Install ArgoCD
    run_cmd "Installing ArgoCD" \
        "kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"

    # Wait for ArgoCD
    sleep 30
    kubectl wait --for=condition=Available deployment --all -n argocd --timeout=300s 2>/dev/null || true

    # Expose ArgoCD with LoadBalancer (using next available IP)
    kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}' 2>/dev/null || true

    # Get initial admin password
    log INFO "ArgoCD initial admin password:"
    kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d && echo

    # Apply ArgoCD applications if they exist
    if [[ -d "${PROJECT_ROOT}/kubernetes/argocd" ]]; then
        sleep 10
        run_cmd "Applying ArgoCD applications" \
            "kubectl apply -k '${PROJECT_ROOT}/kubernetes/argocd/'" || true
    fi

    log OK "ArgoCD installed"
}

#===============================================================================
# Verification
#===============================================================================

phase_verify() {
    log PHASE "Verification"

    echo ""
    echo "======================================================================"
    echo "  Cluster Status"
    echo "======================================================================"
    kubectl get nodes -o wide
    echo ""

    echo "======================================================================"
    echo "  Pods by Namespace"
    echo "======================================================================"
    for ns in liberty monitoring jenkins ingress-nginx metallb-system; do
        echo "--- $ns ---"
        kubectl get pods -n "$ns" 2>/dev/null || echo "(namespace not found)"
        echo ""
    done

    echo "======================================================================"
    echo "  LoadBalancer Services"
    echo "======================================================================"
    kubectl get svc -A | grep LoadBalancer
    echo ""

    echo "======================================================================"
    echo "  Health Checks"
    echo "======================================================================"
    echo -n "Liberty:      "
    curl -s -o /dev/null -w "%{http_code}" "http://${IP_INGRESS}:9080/health/ready" 2>/dev/null || echo "N/A"
    echo ""
    echo -n "Prometheus:   "
    curl -s -o /dev/null -w "%{http_code}" "http://${IP_PROMETHEUS}:9090/-/ready" 2>/dev/null || echo "N/A"
    echo ""
    echo -n "Grafana:      "
    curl -s -o /dev/null -w "%{http_code}" "http://${IP_GRAFANA}:3000/api/health" 2>/dev/null || echo "N/A"
    echo ""
    echo -n "Alertmanager: "
    curl -s -o /dev/null -w "%{http_code}" "http://${IP_ALERTMANAGER}:9093/-/ready" 2>/dev/null || echo "N/A"
    echo ""
    echo -n "Loki:         "
    curl -s -o /dev/null -w "%{http_code}" "http://${IP_LOKI}:3100/ready" 2>/dev/null || echo "N/A"
    echo ""

    echo "======================================================================"
    echo "  Service URLs"
    echo "======================================================================"
    echo "  Liberty:       http://${IP_INGRESS}:9080 or https://liberty.local"
    echo "  Prometheus:    http://${IP_PROMETHEUS}:9090"
    echo "  Grafana:       http://${IP_GRAFANA}:3000"
    echo "  Alertmanager:  http://${IP_ALERTMANAGER}:9093"
    echo "  Loki:          http://${IP_LOKI}:3100"
    echo "  Jaeger:        http://${IP_JAEGER}:16686"
    echo "  Jenkins:       http://${IP_JENKINS}:8080"
    echo ""

    echo "======================================================================"
    echo "  Credentials"
    echo "======================================================================"
    echo "Grafana admin password:"
    kubectl get secret prometheus-grafana -n monitoring -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d && echo
    echo ""

    if [[ -f "${LOG_DIR}/credentials.txt" ]]; then
        echo "Additional credentials saved to: ${LOG_DIR}/credentials.txt"
    fi
}

#===============================================================================
# Main
#===============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --init-cluster)    INIT_CLUSTER=true; shift ;;
            --skip-init)       SKIP_INIT=true; shift ;;
            --skip-monitoring) SKIP_MONITORING=true; shift ;;
            --skip-apps)       SKIP_APPS=true; shift ;;
            --dry-run)         DRY_RUN=true; shift ;;
            -y|--yes)          AUTO_YES=true; shift ;;
            -h|--help)         show_help ;;
            *)                 log ERROR "Unknown option: $1"; show_help ;;
        esac
    done
}

main() {
    parse_args "$@"

    # Create log directory
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE"

    echo ""
    echo "======================================================================"
    echo "  Beelink Kubernetes Cluster Rebuild"
    echo "======================================================================"
    echo ""
    echo "  Master:          $MASTER_IP"
    echo "  Workers:         ${WORKER_IPS[*]}"
    echo "  MetalLB Pool:    ${METALLB_POOL_START}-${METALLB_POOL_END}"
    echo "  K8s Version:     $K8S_VERSION"
    echo ""
    echo "  Options:"
    echo "    - Init cluster:     $INIT_CLUSTER"
    echo "    - Skip init:        $SKIP_INIT"
    echo "    - Skip monitoring:  $SKIP_MONITORING"
    echo "    - Skip apps:        $SKIP_APPS"
    echo "    - Dry run:          $DRY_RUN"
    echo ""
    echo "  Log file: $LOG_FILE"
    echo ""
    echo "======================================================================"
    echo ""

    if ! confirm "Proceed with cluster rebuild?"; then
        log INFO "Aborted by user"
        exit 0
    fi

    check_prerequisites

    phase_cluster_init
    phase_cni
    phase_storage
    phase_metallb
    phase_namespaces
    phase_cert_manager
    phase_ingress
    phase_monitoring
    phase_external_secrets
    phase_network_policies
    phase_secrets
    phase_applications
    phase_cicd
    phase_gitops
    phase_verify

    echo ""
    log OK "Cluster rebuild completed successfully!"
    echo ""
    echo "Log file: $LOG_FILE"
}

main "$@"
