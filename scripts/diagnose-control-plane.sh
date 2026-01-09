#!/bin/bash
#
# Kubernetes Control Plane Diagnostic Script
# Run this on the master node (192.168.68.93) as root
#
# Usage: sudo bash diagnose-control-plane.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo "=============================================================================="
    echo -e "${BLUE}$1${NC}"
    echo "=============================================================================="
}

print_subheader() {
    echo ""
    echo -e "${YELLOW}--- $1 ---${NC}"
}

print_status() {
    if [ "$2" == "ok" ]; then
        echo -e "${GREEN}[OK]${NC} $1"
    elif [ "$2" == "warn" ]; then
        echo -e "${YELLOW}[WARN]${NC} $1"
    else
        echo -e "${RED}[FAIL]${NC} $1"
    fi
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root (use sudo)${NC}"
    exit 1
fi

LOGFILE="/tmp/k8s-control-plane-diag-$(date +%Y%m%d-%H%M%S).log"
echo "Diagnostic output will be saved to: $LOGFILE"
exec > >(tee -a "$LOGFILE") 2>&1

print_header "KUBERNETES CONTROL PLANE DIAGNOSTIC REPORT"
echo "Timestamp: $(date)"
echo "Hostname: $(hostname)"
echo "IP Address: $(hostname -I | awk '{print $1}')"
echo "Kernel: $(uname -r)"

#------------------------------------------------------------------------------
print_header "1. STATIC POD MANIFESTS CHECK"
#------------------------------------------------------------------------------

MANIFEST_DIR="/etc/kubernetes/manifests"

print_subheader "Checking manifest directory existence"
if [ -d "$MANIFEST_DIR" ]; then
    print_status "Manifest directory exists: $MANIFEST_DIR" "ok"

    print_subheader "Listing manifest files"
    ls -la "$MANIFEST_DIR"

    echo ""
    MANIFEST_COUNT=$(ls -1 "$MANIFEST_DIR"/*.yaml 2>/dev/null | wc -l)
    if [ "$MANIFEST_COUNT" -eq 0 ]; then
        print_status "NO MANIFEST FILES FOUND - This is the likely cause!" "fail"
        echo ""
        echo "Expected files:"
        echo "  - kube-apiserver.yaml"
        echo "  - kube-controller-manager.yaml"
        echo "  - kube-scheduler.yaml"
        echo "  - etcd.yaml"
    else
        print_status "Found $MANIFEST_COUNT manifest files" "ok"

        print_subheader "Manifest file contents (first 50 lines each)"
        for manifest in "$MANIFEST_DIR"/*.yaml; do
            if [ -f "$manifest" ]; then
                echo ""
                echo "=== $(basename $manifest) ==="
                head -50 "$manifest"
                echo "... (truncated)"
            fi
        done
    fi
else
    print_status "Manifest directory DOES NOT EXIST: $MANIFEST_DIR" "fail"
    echo "This is critical - static pods cannot start without manifests!"
fi

#------------------------------------------------------------------------------
print_header "2. CONTAINER RUNTIME STATUS"
#------------------------------------------------------------------------------

print_subheader "Containerd service status"
systemctl status containerd --no-pager -l || echo "containerd status check failed"

print_subheader "Containerd socket"
if [ -S /run/containerd/containerd.sock ]; then
    print_status "Containerd socket exists" "ok"
else
    print_status "Containerd socket missing" "fail"
fi

#------------------------------------------------------------------------------
print_header "3. ALL CONTAINERS (crictl)"
#------------------------------------------------------------------------------

print_subheader "All pods (including failed)"
crictl pods -a 2>/dev/null || echo "crictl pods failed"

print_subheader "All containers (including stopped)"
crictl ps -a 2>/dev/null || echo "crictl ps failed"

print_subheader "Container images"
crictl images 2>/dev/null || echo "crictl images failed"

#------------------------------------------------------------------------------
print_header "4. KUBE-* CONTAINER LOGS"
#------------------------------------------------------------------------------

print_subheader "Looking for kube-* containers"

# Get all container IDs for kube-* containers
KUBE_CONTAINERS=$(crictl ps -a --name="kube-" -q 2>/dev/null)

if [ -z "$KUBE_CONTAINERS" ]; then
    print_status "No kube-* containers found" "warn"
    echo "This confirms static pods are not starting at all"
else
    for container_id in $KUBE_CONTAINERS; do
        container_name=$(crictl inspect "$container_id" 2>/dev/null | grep -m1 '"name"' | cut -d'"' -f4)
        echo ""
        echo "=== Container: $container_name (ID: $container_id) ==="
        crictl logs --tail=100 "$container_id" 2>&1 || echo "Could not get logs for $container_id"
    done
fi

# Also check for etcd
print_subheader "Looking for etcd containers"
ETCD_CONTAINERS=$(crictl ps -a --name="etcd" -q 2>/dev/null)

if [ -z "$ETCD_CONTAINERS" ]; then
    print_status "No etcd containers found" "warn"
else
    for container_id in $ETCD_CONTAINERS; do
        echo ""
        echo "=== etcd Container (ID: $container_id) ==="
        crictl logs --tail=100 "$container_id" 2>&1 || echo "Could not get logs for $container_id"
    done
fi

#------------------------------------------------------------------------------
print_header "5. KUBELET STATUS AND LOGS"
#------------------------------------------------------------------------------

print_subheader "Kubelet service status"
systemctl status kubelet --no-pager -l || echo "kubelet status check failed"

print_subheader "Kubelet configuration"
echo "Kubelet args from service file:"
cat /etc/systemd/system/kubelet.service.d/10-kubeadm.conf 2>/dev/null || \
cat /usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf 2>/dev/null || \
echo "Could not find kubelet drop-in config"

print_subheader "Kubelet config file"
if [ -f /var/lib/kubelet/config.yaml ]; then
    cat /var/lib/kubelet/config.yaml
else
    print_status "Kubelet config.yaml not found" "warn"
fi

print_subheader "Kubelet logs (last 200 lines, filtering for errors)"
journalctl -u kubelet --no-pager -n 200 2>/dev/null | grep -iE "(error|fail|cannot|refused|unable|fatal)" || echo "No obvious errors in recent kubelet logs"

print_subheader "Kubelet logs related to static pods"
journalctl -u kubelet --no-pager -n 500 2>/dev/null | grep -iE "(static|manifest|apiserver|controller-manager|scheduler|etcd)" || echo "No static pod related entries found"

print_subheader "Full kubelet logs (last 100 lines)"
journalctl -u kubelet --no-pager -n 100

#------------------------------------------------------------------------------
print_header "6. CONTAINERD LOGS"
#------------------------------------------------------------------------------

print_subheader "Containerd logs (last 100 lines, filtering for errors)"
journalctl -u containerd --no-pager -n 100 2>/dev/null | grep -iE "(error|fail|cannot|refused)" || echo "No obvious errors in containerd logs"

#------------------------------------------------------------------------------
print_header "7. KUBEADM CONFIGURATION"
#------------------------------------------------------------------------------

print_subheader "Kubeadm config (if exists)"
if [ -f /etc/kubernetes/kubeadm-config.yaml ]; then
    cat /etc/kubernetes/kubeadm-config.yaml
else
    echo "No kubeadm-config.yaml found in /etc/kubernetes/"
fi

print_subheader "ClusterConfiguration from configmap backup"
if [ -f /etc/kubernetes/tmp/kubeadm-backup ]; then
    cat /etc/kubernetes/tmp/kubeadm-backup
else
    echo "No kubeadm backup found"
fi

print_subheader "Kubeadm version"
kubeadm version 2>/dev/null || echo "kubeadm not found or not accessible"

print_subheader "Kubelet version"
kubelet --version 2>/dev/null || echo "kubelet not found"

#------------------------------------------------------------------------------
print_header "8. RESOURCE CONSTRAINTS"
#------------------------------------------------------------------------------

print_subheader "Disk Space"
df -h / /var /etc /run 2>/dev/null

DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 90 ]; then
    print_status "Root filesystem is ${DISK_USAGE}% full - CRITICAL" "fail"
elif [ "$DISK_USAGE" -gt 80 ]; then
    print_status "Root filesystem is ${DISK_USAGE}% full - WARNING" "warn"
else
    print_status "Root filesystem is ${DISK_USAGE}% full" "ok"
fi

print_subheader "Memory"
free -h

MEM_AVAILABLE=$(free -m | awk '/^Mem:/ {print $7}')
if [ "$MEM_AVAILABLE" -lt 1024 ]; then
    print_status "Available memory is ${MEM_AVAILABLE}MB - May be low for control plane" "warn"
else
    print_status "Available memory: ${MEM_AVAILABLE}MB" "ok"
fi

print_subheader "CPU"
nproc
uptime

print_subheader "Inode usage"
df -i / /var /etc 2>/dev/null

#------------------------------------------------------------------------------
print_header "9. CERTIFICATES CHECK"
#------------------------------------------------------------------------------

PKI_DIR="/etc/kubernetes/pki"

print_subheader "PKI directory contents"
if [ -d "$PKI_DIR" ]; then
    print_status "PKI directory exists" "ok"
    ls -la "$PKI_DIR"

    print_subheader "etcd PKI directory"
    if [ -d "$PKI_DIR/etcd" ]; then
        ls -la "$PKI_DIR/etcd"
    else
        print_status "etcd PKI directory missing" "fail"
    fi

    print_subheader "Certificate expiration check"
    for cert in "$PKI_DIR"/*.crt; do
        if [ -f "$cert" ]; then
            echo ""
            echo "=== $(basename $cert) ==="
            openssl x509 -in "$cert" -noout -dates 2>/dev/null || echo "Could not read certificate"
        fi
    done

    print_subheader "CA certificate check"
    if [ -f "$PKI_DIR/ca.crt" ]; then
        print_status "CA certificate exists" "ok"
        openssl x509 -in "$PKI_DIR/ca.crt" -noout -subject -issuer 2>/dev/null
    else
        print_status "CA certificate MISSING - Critical!" "fail"
    fi
else
    print_status "PKI directory DOES NOT EXIST: $PKI_DIR" "fail"
    echo "Certificates have not been generated!"
fi

#------------------------------------------------------------------------------
print_header "10. NETWORK AND PORTS"
#------------------------------------------------------------------------------

print_subheader "Listening ports (kubernetes-related)"
ss -tlnp | grep -E "(6443|2379|2380|10250|10259|10257)" || echo "No kubernetes ports listening"

print_subheader "Port 6443 (API server) status"
if ss -tln | grep -q ":6443 "; then
    print_status "Port 6443 is listening" "ok"
else
    print_status "Port 6443 is NOT listening - API server not running" "fail"
fi

print_subheader "Port 2379 (etcd) status"
if ss -tln | grep -q ":2379 "; then
    print_status "Port 2379 is listening" "ok"
else
    print_status "Port 2379 is NOT listening - etcd not running" "fail"
fi

#------------------------------------------------------------------------------
print_header "11. ADDITIONAL CHECKS"
#------------------------------------------------------------------------------

print_subheader "Swap status (should be disabled)"
if [ "$(swapon --show | wc -l)" -eq 0 ]; then
    print_status "Swap is disabled" "ok"
else
    print_status "Swap is ENABLED - This can cause issues" "warn"
    swapon --show
fi

print_subheader "Kernel modules for kubernetes"
for mod in br_netfilter overlay ip_vs ip_vs_rr ip_vs_wrr ip_vs_sh nf_conntrack; do
    if lsmod | grep -q "^$mod"; then
        print_status "Module $mod loaded" "ok"
    else
        print_status "Module $mod NOT loaded" "warn"
    fi
done

print_subheader "Sysctl settings"
echo "net.bridge.bridge-nf-call-iptables: $(sysctl -n net.bridge.bridge-nf-call-iptables 2>/dev/null || echo 'not set')"
echo "net.bridge.bridge-nf-call-ip6tables: $(sysctl -n net.bridge.bridge-nf-call-ip6tables 2>/dev/null || echo 'not set')"
echo "net.ipv4.ip_forward: $(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 'not set')"

print_subheader "SELinux/AppArmor status"
if command -v getenforce &> /dev/null; then
    echo "SELinux: $(getenforce)"
fi
if command -v aa-status &> /dev/null; then
    aa-status 2>/dev/null | head -5
fi

#------------------------------------------------------------------------------
print_header "12. TEARDOWN REMNANTS CHECK"
#------------------------------------------------------------------------------

print_subheader "Checking for leftover kubernetes state"

echo "Checking /var/lib/kubelet:"
ls -la /var/lib/kubelet 2>/dev/null | head -20 || echo "Directory empty or doesn't exist"

echo ""
echo "Checking /var/lib/etcd:"
ls -la /var/lib/etcd 2>/dev/null || echo "Directory doesn't exist"

echo ""
echo "Checking /etc/kubernetes:"
ls -la /etc/kubernetes 2>/dev/null || echo "Directory doesn't exist"

echo ""
echo "Checking CNI config:"
ls -la /etc/cni/net.d/ 2>/dev/null || echo "No CNI config"

#------------------------------------------------------------------------------
print_header "SUMMARY AND RECOMMENDATIONS"
#------------------------------------------------------------------------------

echo ""
echo "Based on the diagnostics above, check for these common issues:"
echo ""
echo "1. MISSING MANIFESTS: If /etc/kubernetes/manifests/ is empty, you need to"
echo "   re-run 'kubeadm init' to regenerate control plane manifests."
echo ""
echo "2. CERTIFICATE ISSUES: If /etc/kubernetes/pki/ is empty or incomplete,"
echo "   the teardown may have removed certificates. Run 'kubeadm init' again."
echo ""
echo "3. ETCD DATA: If /var/lib/etcd exists with old data, you may need to:"
echo "   rm -rf /var/lib/etcd/* before re-initializing."
echo ""
echo "4. CONTAINER RUNTIME: If containerd is not running, start it:"
echo "   systemctl start containerd"
echo ""
echo "5. KUBELET NOT CONFIGURED: If kubelet config is missing:"
echo "   The teardown may have removed kubelet configuration."
echo ""
echo "=============================================================================="
echo "TO RE-INITIALIZE THE CLUSTER:"
echo "=============================================================================="
echo ""
echo "# 1. Clean up any remnants (if needed)"
echo "kubeadm reset -f"
echo "rm -rf /var/lib/etcd/*"
echo "rm -rf /etc/cni/net.d/*"
echo ""
echo "# 2. Re-initialize the control plane"
echo "kubeadm init --kubernetes-version=1.33.1 \\"
echo "  --pod-network-cidr=10.244.0.0/16 \\"
echo "  --apiserver-advertise-address=192.168.68.93"
echo ""
echo "# 3. Configure kubectl"
echo "mkdir -p \$HOME/.kube"
echo "cp /etc/kubernetes/admin.conf \$HOME/.kube/config"
echo "chown \$(id -u):\$(id -g) \$HOME/.kube/config"
echo ""
echo "# 4. Install CNI (e.g., Flannel)"
echo "kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml"
echo ""
echo "=============================================================================="
echo ""
echo "Full diagnostic log saved to: $LOGFILE"
echo ""
