#!/bin/bash
#===============================================================================
# Kubernetes Node Preparation Script
#===============================================================================
# Prepares a node for Kubernetes installation by:
# - Installing required packages
# - Configuring kernel modules and sysctl
# - Installing containerd
# - Installing kubeadm, kubelet, kubectl
#
# This script should be run on each node (master and workers) BEFORE
# initializing the cluster.
#
# Usage:
#   ./node-prep.sh [OPTIONS]
#
# Options:
#   --k8s-version VERSION  Kubernetes version (default: 1.34)
#   --dry-run              Show what would be done
#   -h, --help             Show this help message
#
#===============================================================================

set -euo pipefail

# Configuration
K8S_VERSION="1.34"
DRY_RUN=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $*"
}

log_ok() {
    echo -e "${GREEN}[OK]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

run() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Would execute: $*"
        return 0
    fi
    "$@"
}

show_help() {
    head -22 "$0" | tail -17
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --k8s-version)
                K8S_VERSION="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                ;;
        esac
    done
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_os() {
    log "Checking operating system..."

    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        log_ok "Detected: $NAME $VERSION_ID"

        case "$ID" in
            ubuntu|debian)
                log_ok "Supported distribution"
                ;;
            *)
                log_warn "Untested distribution: $ID"
                ;;
        esac
    else
        log_error "Cannot detect OS"
        exit 1
    fi
}

disable_swap() {
    log "Disabling swap..."

    run swapoff -a

    # Comment out swap entries in fstab
    if grep -q "swap" /etc/fstab; then
        run sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
        log_ok "Swap disabled"
    else
        log_ok "No swap entries in fstab"
    fi
}

configure_kernel_modules() {
    log "Configuring kernel modules..."

    cat <<EOF | run tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

    run modprobe overlay
    run modprobe br_netfilter

    log_ok "Kernel modules configured"
}

configure_sysctl() {
    log "Configuring sysctl settings..."

    cat <<EOF | run tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

    run sysctl --system

    log_ok "Sysctl configured"
}

install_prerequisites() {
    log "Installing prerequisites..."

    run apt-get update
    run apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        software-properties-common \
        open-iscsi \
        nfs-common

    log_ok "Prerequisites installed"
}

install_containerd() {
    log "Installing containerd..."

    run apt-get install -y containerd

    # Create default config
    run mkdir -p /etc/containerd
    containerd config default | run tee /etc/containerd/config.toml > /dev/null

    # Enable systemd cgroup driver
    run sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

    run systemctl restart containerd
    run systemctl enable containerd

    log_ok "containerd installed and configured"
}

configure_crictl() {
    log "Configuring crictl..."

    cat <<EOF | run tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

    log_ok "crictl configured"
}

install_kubernetes() {
    log "Installing Kubernetes $K8S_VERSION..."

    # Add Kubernetes apt repository
    run mkdir -p /etc/apt/keyrings
    curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key" | \
        run gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" | \
        run tee /etc/apt/sources.list.d/kubernetes.list

    run apt-get update
    run apt-get install -y kubelet kubeadm kubectl
    run apt-mark hold kubelet kubeadm kubectl

    log_ok "Kubernetes $K8S_VERSION installed"
}

configure_kubelet() {
    log "Configuring kubelet..."

    # Create kubelet defaults file for any extra args
    # Note: Do NOT create 10-kubeadm.conf here - kubeadm handles that
    # The proper kubeadm drop-in file includes the kubeconfig and config
    # arguments that kubelet needs to connect to the API server
    run mkdir -p /etc/default
    cat <<EOF | run tee /etc/default/kubelet
# Extra kubelet arguments (optional)
# These are picked up by the kubeadm-generated systemd dropin
KUBELET_EXTRA_ARGS=
EOF

    run systemctl daemon-reload
    run systemctl enable kubelet

    log_ok "kubelet configured"
}

enable_iscsid() {
    log "Enabling iSCSI for Longhorn..."

    run systemctl enable --now iscsid

    log_ok "iSCSI enabled"
}

verify_installation() {
    log "Verifying installation..."

    echo ""
    echo "======================================================================"
    echo "  Installation Verification"
    echo "======================================================================"
    echo ""

    # Check containerd
    if systemctl is-active --quiet containerd; then
        log_ok "containerd is running"
    else
        log_error "containerd is not running"
    fi

    # Check kubelet (should not be running yet)
    if command -v kubeadm &> /dev/null; then
        log_ok "kubeadm installed: $(kubeadm version -o short 2>/dev/null || echo 'unknown')"
    else
        log_error "kubeadm not found"
    fi

    if command -v kubelet &> /dev/null; then
        log_ok "kubelet installed: $(kubelet --version 2>/dev/null || echo 'unknown')"
    else
        log_error "kubelet not found"
    fi

    if command -v kubectl &> /dev/null; then
        log_ok "kubectl installed: $(kubectl version --client -o json 2>/dev/null | jq -r '.clientVersion.gitVersion' || echo 'unknown')"
    else
        log_error "kubectl not found"
    fi

    # Check kernel modules
    if lsmod | grep -q br_netfilter; then
        log_ok "br_netfilter module loaded"
    else
        log_error "br_netfilter module not loaded"
    fi

    if lsmod | grep -q overlay; then
        log_ok "overlay module loaded"
    else
        log_error "overlay module not loaded"
    fi

    # Check sysctl
    if [[ $(sysctl -n net.ipv4.ip_forward) == "1" ]]; then
        log_ok "IP forwarding enabled"
    else
        log_error "IP forwarding not enabled"
    fi

    # Check swap
    if [[ $(swapon --show | wc -l) -eq 0 ]]; then
        log_ok "Swap is disabled"
    else
        log_warn "Swap is still enabled"
    fi

    echo ""
}

print_next_steps() {
    echo ""
    echo "======================================================================"
    echo "  Next Steps"
    echo "======================================================================"
    echo ""
    echo "  1. Run this script on all other nodes"
    echo ""
    echo "  2. On the MASTER node, initialize the cluster:"
    echo "     kubeadm init --pod-network-cidr=10.244.0.0/16 \\"
    echo "                  --control-plane-endpoint=${HOSTNAME}:6443"
    echo ""
    echo "  3. After init, copy kubeconfig:"
    echo "     mkdir -p \$HOME/.kube"
    echo "     sudo cp /etc/kubernetes/admin.conf \$HOME/.kube/config"
    echo "     sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config"
    echo ""
    echo "  4. Get the join command:"
    echo "     kubeadm token create --print-join-command"
    echo ""
    echo "  5. On WORKER nodes, run the join command"
    echo ""
    echo "  6. Install CNI (Calico):"
    echo "     kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml"
    echo ""
    echo "======================================================================"
}

main() {
    parse_args "$@"

    echo ""
    echo "======================================================================"
    echo "  Kubernetes Node Preparation"
    echo "======================================================================"
    echo ""
    echo "  Hostname:     $(hostname)"
    echo "  K8s Version:  $K8S_VERSION"
    echo "  Dry Run:      $DRY_RUN"
    echo ""

    if [[ "$DRY_RUN" != "true" ]]; then
        check_root
    fi

    check_os
    disable_swap
    configure_kernel_modules
    configure_sysctl
    install_prerequisites
    install_containerd
    configure_crictl
    install_kubernetes
    configure_kubelet
    enable_iscsid
    verify_installation
    print_next_steps

    log_ok "Node preparation complete!"
}

main "$@"
