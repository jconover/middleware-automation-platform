#!/bin/bash
#===============================================================================
# Beelink Kubernetes Cluster - Complete Teardown Script
#===============================================================================
# This script safely tears down the entire Kubernetes cluster in the correct
# dependency order. It preserves backups before destructive operations.
#
# Cluster Configuration:
#   - k8s-master-01: 192.168.68.93 (Control Plane + Worker)
#   - k8s-worker-01: 192.168.68.86 (Worker)
#   - k8s-worker-02: 192.168.68.88 (Worker)
#   - MetalLB Pool: 192.168.68.200-210
#
# Usage:
#   ./teardown.sh [OPTIONS]
#
# Options:
#   --skip-backup       Skip the backup phase
#   --delete-data       Delete all PVCs and persistent data
#   --reset-cluster     Also reset kubeadm on all nodes (full teardown)
#   --dry-run           Show what would be done without executing
#   -y, --yes           Skip confirmation prompts
#   -h, --help          Show this help message
#
#===============================================================================

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Configuration
BACKUP_DIR="${PROJECT_ROOT}/backups/teardown-$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${BACKUP_DIR}/teardown.log"

# Node IPs
MASTER_IP="192.168.68.93"
WORKER_IPS=("192.168.68.86" "192.168.68.88")
ALL_NODES=("${MASTER_IP}" "${WORKER_IPS[@]}")

# Namespaces to clean up
NAMESPACES=(
    "liberty"
    "jenkins"
    "awx"
    "monitoring"
    "tracing"
    "argocd"
    "ingress-nginx"
    "cert-manager"
    "external-secrets"
    "secrets-source"
    "metallb-system"
    "longhorn-system"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default options
SKIP_BACKUP=false
DELETE_DATA=false
RESET_CLUSTER=false
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
        INFO)  echo -e "${BLUE}[INFO]${NC} $message" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" ;;
        OK)    echo -e "${GREEN}[OK]${NC} $message" ;;
        STEP)  echo -e "\n${GREEN}==>${NC} ${YELLOW}$message${NC}" ;;
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
        log WARN "Command returned non-zero exit code (may be expected)"
        return 0
    fi
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
    head -40 "$0" | tail -30
    exit 0
}

check_prerequisites() {
    log STEP "Checking prerequisites"

    local missing=()

    for cmd in kubectl helm jq; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log ERROR "Missing required commands: ${missing[*]}"
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        log ERROR "Cannot connect to Kubernetes cluster. Check your kubeconfig."
        exit 1
    fi

    log OK "All prerequisites met"
}

#===============================================================================
# Phase 0: Backup
#===============================================================================

phase_backup() {
    if [[ "$SKIP_BACKUP" == "true" ]]; then
        log WARN "Skipping backup phase (--skip-backup specified)"
        mkdir -p "$BACKUP_DIR"
        return 0
    fi

    log STEP "Phase 0: Creating backups"
    mkdir -p "$BACKUP_DIR"/{secrets,configmaps,pvcs,rbac,helm,grafana}

    # Initialize log file
    touch "$LOG_FILE"

    # Backup secrets (all namespaces)
    log INFO "Backing up secrets..."
    for ns in "${NAMESPACES[@]}"; do
        kubectl get secrets -n "$ns" -o yaml > "$BACKUP_DIR/secrets/$ns-secrets.yaml" 2>/dev/null || true
    done

    # Backup ConfigMaps
    log INFO "Backing up ConfigMaps..."
    for ns in "${NAMESPACES[@]}"; do
        kubectl get configmaps -n "$ns" -o yaml > "$BACKUP_DIR/configmaps/$ns-configmaps.yaml" 2>/dev/null || true
    done

    # Backup PVCs
    log INFO "Backing up PVC definitions..."
    kubectl get pvc -A -o yaml > "$BACKUP_DIR/pvcs/all-pvcs.yaml" 2>/dev/null || true
    kubectl get pv -o yaml > "$BACKUP_DIR/pvcs/all-pvs.yaml" 2>/dev/null || true

    # Backup RBAC
    log INFO "Backing up RBAC resources..."
    kubectl get serviceaccounts -A -o yaml > "$BACKUP_DIR/rbac/serviceaccounts.yaml" 2>/dev/null || true
    kubectl get roles -A -o yaml > "$BACKUP_DIR/rbac/roles.yaml" 2>/dev/null || true
    kubectl get rolebindings -A -o yaml > "$BACKUP_DIR/rbac/rolebindings.yaml" 2>/dev/null || true
    kubectl get clusterroles -o yaml > "$BACKUP_DIR/rbac/clusterroles.yaml" 2>/dev/null || true
    kubectl get clusterrolebindings -o yaml > "$BACKUP_DIR/rbac/clusterrolebindings.yaml" 2>/dev/null || true

    # Backup External Secrets
    log INFO "Backing up External Secrets resources..."
    kubectl get externalsecrets -A -o yaml > "$BACKUP_DIR/secrets/externalsecrets.yaml" 2>/dev/null || true
    kubectl get clustersecretstores -o yaml > "$BACKUP_DIR/secrets/clustersecretstores.yaml" 2>/dev/null || true

    # Backup Helm releases
    log INFO "Backing up Helm release values..."
    for release in prometheus jenkins longhorn ingress-nginx; do
        ns=$(helm list -A -f "$release" -o json 2>/dev/null | jq -r '.[0].namespace // empty')
        if [[ -n "$ns" ]]; then
            helm get values "$release" -n "$ns" > "$BACKUP_DIR/helm/$release-values.yaml" 2>/dev/null || true
        fi
    done

    # Backup Grafana dashboards (if accessible)
    log INFO "Attempting Grafana dashboard backup..."
    local grafana_pass
    grafana_pass=$(kubectl get secret prometheus-grafana -n monitoring -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d || echo "")
    if [[ -n "$grafana_pass" ]]; then
        mkdir -p "$BACKUP_DIR/grafana/dashboards"
        curl -s -u "admin:${grafana_pass}" "http://192.168.68.202/api/search?type=dash-db" 2>/dev/null | \
            jq -r '.[].uid // empty' 2>/dev/null | while read -r uid; do
            if [[ -n "$uid" ]]; then
                curl -s -u "admin:${grafana_pass}" "http://192.168.68.202/api/dashboards/uid/${uid}" \
                    > "$BACKUP_DIR/grafana/dashboards/${uid}.json" 2>/dev/null || true
            fi
        done
        curl -s -u "admin:${grafana_pass}" "http://192.168.68.202/api/datasources" \
            > "$BACKUP_DIR/grafana/datasources.json" 2>/dev/null || true
    fi

    # Backup MetalLB configuration
    log INFO "Backing up MetalLB configuration..."
    kubectl get ipaddresspools -n metallb-system -o yaml > "$BACKUP_DIR/metallb-ipaddresspools.yaml" 2>/dev/null || true
    kubectl get l2advertisements -n metallb-system -o yaml > "$BACKUP_DIR/metallb-l2advertisements.yaml" 2>/dev/null || true

    # Backup LoadBalancer service IPs
    log INFO "Backing up LoadBalancer service assignments..."
    kubectl get svc -A -o wide | grep LoadBalancer > "$BACKUP_DIR/loadbalancer-services.txt" 2>/dev/null || true

    log OK "Backups saved to: $BACKUP_DIR"
}

#===============================================================================
# Phase 1: Application Workloads
#===============================================================================

phase_applications() {
    log STEP "Phase 1: Removing application workloads"

    # Remove ArgoCD Applications first (they manage other resources)
    log INFO "Removing ArgoCD applications..."
    run_cmd "Delete ArgoCD applications" \
        "kubectl delete -k '${PROJECT_ROOT}/kubernetes/argocd/' --ignore-not-found 2>/dev/null || true"

    # Remove Liberty application
    log INFO "Removing Liberty application..."
    run_cmd "Scale down Liberty" \
        "kubectl scale deployment liberty-app -n liberty --replicas=0 2>/dev/null || true"
    sleep 5

    run_cmd "Delete Liberty HPA" \
        "kubectl delete hpa liberty-hpa -n liberty --ignore-not-found 2>/dev/null || true"
    run_cmd "Delete Liberty overlay" \
        "kubectl delete -k '${PROJECT_ROOT}/kubernetes/overlays/local-homelab/' --ignore-not-found 2>/dev/null || true"

    # Remove AWX
    log INFO "Removing AWX..."
    run_cmd "Delete AWX deployment" \
        "kubectl delete awx awx -n awx --ignore-not-found 2>/dev/null || true"
    run_cmd "Uninstall AWX operator" \
        "helm uninstall awx-operator -n awx --wait 2>/dev/null || true"

    # Remove Jenkins
    log INFO "Removing Jenkins..."
    run_cmd "Uninstall Jenkins" \
        "helm uninstall jenkins -n jenkins --wait 2>/dev/null || true"

    log OK "Application workloads removed"
}

#===============================================================================
# Phase 2: Monitoring Stack
#===============================================================================

phase_monitoring() {
    log STEP "Phase 2: Removing monitoring stack"

    # Remove custom monitoring resources first
    log INFO "Removing Liberty monitoring resources..."
    run_cmd "Delete ServiceMonitors and PrometheusRules" \
        "kubectl delete -k '${PROJECT_ROOT}/kubernetes/base/monitoring/' --ignore-not-found 2>/dev/null || true"

    # Remove Promtail
    log INFO "Removing Promtail..."
    run_cmd "Delete Promtail" \
        "kubectl delete -k '${PROJECT_ROOT}/kubernetes/base/monitoring/promtail/' --ignore-not-found 2>/dev/null || true"
    run_cmd "Delete Promtail ClusterRole" \
        "kubectl delete clusterrole promtail --ignore-not-found 2>/dev/null || true"
    run_cmd "Delete Promtail ClusterRoleBinding" \
        "kubectl delete clusterrolebinding promtail --ignore-not-found 2>/dev/null || true"

    # Remove Loki
    log INFO "Removing Loki..."
    run_cmd "Delete Loki" \
        "kubectl delete -k '${PROJECT_ROOT}/kubernetes/base/monitoring/loki/' --ignore-not-found 2>/dev/null || true"

    # Remove Jaeger
    log INFO "Removing Jaeger..."
    run_cmd "Delete Jaeger" \
        "kubectl delete -k '${PROJECT_ROOT}/kubernetes/base/monitoring/jaeger/' --ignore-not-found 2>/dev/null || true"

    # Remove OpenTelemetry Collector
    log INFO "Removing OpenTelemetry Collector..."
    run_cmd "Delete OTEL Collector" \
        "kubectl delete -k '${PROJECT_ROOT}/kubernetes/base/monitoring/otel-collector/' --ignore-not-found 2>/dev/null || true"

    # Remove Prometheus Adapter
    log INFO "Removing Prometheus Adapter..."
    run_cmd "Delete Prometheus Adapter" \
        "kubectl delete -k '${PROJECT_ROOT}/kubernetes/base/monitoring/prometheus-adapter/' --ignore-not-found 2>/dev/null || true"

    # Remove Prometheus stack
    log INFO "Removing kube-prometheus-stack..."
    run_cmd "Uninstall Prometheus stack" \
        "helm uninstall prometheus -n monitoring --wait 2>/dev/null || true"

    # Wait for pods to terminate
    log INFO "Waiting for monitoring pods to terminate..."
    kubectl wait --for=delete pod -l app.kubernetes.io/instance=prometheus -n monitoring --timeout=120s 2>/dev/null || true

    log OK "Monitoring stack removed"
}

#===============================================================================
# Phase 3: Infrastructure Services
#===============================================================================

phase_infrastructure() {
    log STEP "Phase 3: Removing infrastructure services"

    # Remove certificates
    log INFO "Removing certificate resources..."
    run_cmd "Delete certificates" \
        "kubectl delete -f '${PROJECT_ROOT}/kubernetes/base/certificates/' --ignore-not-found 2>/dev/null || true"

    # Remove External Secrets resources
    log INFO "Removing External Secrets resources..."
    run_cmd "Delete ExternalSecrets" \
        "kubectl delete externalsecrets --all -A --ignore-not-found 2>/dev/null || true"
    run_cmd "Delete ClusterSecretStores" \
        "kubectl delete clustersecretstores --all --ignore-not-found 2>/dev/null || true"
    run_cmd "Delete SecretStores" \
        "kubectl delete secretstores --all -A --ignore-not-found 2>/dev/null || true"
    run_cmd "Uninstall External Secrets Operator" \
        "helm uninstall external-secrets -n external-secrets --wait 2>/dev/null || true"

    # Remove NGINX Ingress Controller
    log INFO "Removing NGINX Ingress Controller..."
    run_cmd "Uninstall ingress-nginx" \
        "helm uninstall ingress-nginx -n ingress-nginx --wait 2>/dev/null || true"

    # Remove cert-manager
    log INFO "Removing cert-manager..."
    run_cmd "Delete cert-manager" \
        "kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml --ignore-not-found 2>/dev/null || true"

    # Remove ArgoCD
    log INFO "Removing ArgoCD..."
    run_cmd "Delete ArgoCD" \
        "kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --ignore-not-found 2>/dev/null || true"

    log OK "Infrastructure services removed"
}

#===============================================================================
# Phase 4: Network Policies
#===============================================================================

phase_network_policies() {
    log STEP "Phase 4: Removing network policies"

    run_cmd "Delete network policies" \
        "kubectl delete -k '${PROJECT_ROOT}/kubernetes/base/network-policies/' --ignore-not-found 2>/dev/null || true"

    # Delete any remaining network policies
    for ns in "${NAMESPACES[@]}"; do
        run_cmd "Delete remaining NetworkPolicies in $ns" \
            "kubectl delete networkpolicies --all -n '$ns' --ignore-not-found 2>/dev/null || true"
    done

    log OK "Network policies removed"
}

#===============================================================================
# Phase 5: Storage Cleanup
#===============================================================================

phase_storage() {
    log STEP "Phase 5: Storage cleanup"

    if [[ "$DELETE_DATA" == "true" ]]; then
        log WARN "DELETE_DATA is set - removing all PVCs"

        if ! confirm "This will DELETE ALL PERSISTENT DATA. Are you sure?"; then
            log INFO "Skipping PVC deletion"
            return 0
        fi

        for ns in "${NAMESPACES[@]}"; do
            run_cmd "Delete PVCs in $ns" \
                "kubectl delete pvc --all -n '$ns' --wait=false 2>/dev/null || true"
        done

        # Wait for PVCs to be deleted
        sleep 10

        # Delete orphaned PVs
        run_cmd "Delete orphaned PVs" \
            "kubectl delete pv --all --wait=false 2>/dev/null || true"
    else
        log INFO "Preserving PVCs (use --delete-data to remove)"
        kubectl get pvc -A 2>/dev/null || true
    fi

    # Remove Longhorn
    log INFO "Removing Longhorn..."
    run_cmd "Uninstall Longhorn" \
        "helm uninstall longhorn -n longhorn-system --wait 2>/dev/null || true"

    if [[ "$DELETE_DATA" == "true" ]]; then
        log WARN "Cleaning Longhorn data directories on nodes..."
        for node in "${ALL_NODES[@]}"; do
            log INFO "Cleaning Longhorn data on $node..."
            if [[ "$DRY_RUN" != "true" ]]; then
                ssh -o ConnectTimeout=5 "$node" "sudo rm -rf /var/lib/longhorn/*" 2>/dev/null || \
                    log WARN "Could not clean Longhorn data on $node (SSH may not be configured)"
            fi
        done
    fi

    log OK "Storage cleanup complete"
}

#===============================================================================
# Phase 6: MetalLB
#===============================================================================

phase_metallb() {
    log STEP "Phase 6: Removing MetalLB"

    # Delete L2Advertisement first
    run_cmd "Delete L2Advertisements" \
        "kubectl delete l2advertisement --all -n metallb-system --ignore-not-found 2>/dev/null || true"

    # Delete IPAddressPool
    run_cmd "Delete IPAddressPools" \
        "kubectl delete ipaddresspool --all -n metallb-system --ignore-not-found 2>/dev/null || true"

    # Remove MetalLB
    run_cmd "Delete MetalLB" \
        "kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml --ignore-not-found 2>/dev/null || true"

    log OK "MetalLB removed"
}

#===============================================================================
# Phase 7: Namespace Cleanup
#===============================================================================

phase_namespaces() {
    log STEP "Phase 7: Cleaning up namespaces"

    for ns in "${NAMESPACES[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            run_cmd "Delete namespace $ns" \
                "kubectl delete namespace '$ns' --wait=false 2>/dev/null || true"
        fi
    done

    # Wait for namespace termination
    log INFO "Waiting for namespaces to terminate..."
    sleep 15

    # Force-delete stuck namespaces
    for ns in "${NAMESPACES[@]}"; do
        if kubectl get namespace "$ns" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Terminating"; then
            log WARN "Force-deleting stuck namespace: $ns"
            if [[ "$DRY_RUN" != "true" ]]; then
                kubectl get namespace "$ns" -o json | \
                    jq '.spec.finalizers = []' | \
                    kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - 2>/dev/null || true
            fi
        fi
    done

    log OK "Namespace cleanup complete"
}

#===============================================================================
# Phase 8: Cluster Reset (Optional)
#===============================================================================

phase_cluster_reset() {
    if [[ "$RESET_CLUSTER" != "true" ]]; then
        log INFO "Skipping cluster reset (use --reset-cluster to include)"
        return 0
    fi

    log STEP "Phase 8: Resetting kubeadm cluster"

    if ! confirm "This will RESET THE ENTIRE CLUSTER. Are you absolutely sure?"; then
        log INFO "Skipping cluster reset"
        return 0
    fi

    # Reset workers first
    for worker in "${WORKER_IPS[@]}"; do
        log INFO "Resetting worker node: $worker"
        if [[ "$DRY_RUN" != "true" ]]; then
            ssh -o ConnectTimeout=10 "$worker" "sudo kubeadm reset -f && \
                sudo rm -rf /etc/cni/net.d && \
                sudo rm -rf /var/lib/kubelet/* && \
                sudo rm -rf /var/lib/etcd/* && \
                sudo rm -rf ~/.kube && \
                sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X && \
                sudo systemctl restart containerd" 2>/dev/null || \
                log WARN "Could not reset worker $worker"
        fi
    done

    # Reset master last
    log INFO "Resetting master node: $MASTER_IP"
    if [[ "$DRY_RUN" != "true" ]]; then
        ssh -o ConnectTimeout=10 "$MASTER_IP" "sudo kubeadm reset -f && \
            sudo rm -rf /etc/cni/net.d && \
            sudo rm -rf /var/lib/kubelet/* && \
            sudo rm -rf /var/lib/etcd/* && \
            sudo rm -rf ~/.kube && \
            sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X && \
            sudo systemctl restart containerd" 2>/dev/null || \
            log WARN "Could not reset master $MASTER_IP"
    fi

    # Clean up local kubeconfig
    log INFO "Cleaning local kubeconfig..."
    if [[ "$DRY_RUN" != "true" ]]; then
        rm -f ~/.kube/config 2>/dev/null || true
    fi

    log OK "Cluster reset complete"
}

#===============================================================================
# Main
#===============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip-backup)   SKIP_BACKUP=true; shift ;;
            --delete-data)   DELETE_DATA=true; shift ;;
            --reset-cluster) RESET_CLUSTER=true; shift ;;
            --dry-run)       DRY_RUN=true; shift ;;
            -y|--yes)        AUTO_YES=true; shift ;;
            -h|--help)       show_help ;;
            *)               log ERROR "Unknown option: $1"; show_help ;;
        esac
    done
}

main() {
    parse_args "$@"

    echo ""
    echo "======================================================================"
    echo "  Beelink Kubernetes Cluster Teardown"
    echo "======================================================================"
    echo ""
    echo "  Cluster: k8s-master-01 (192.168.68.93) + 2 workers"
    echo "  Options:"
    echo "    - Skip backup:    $SKIP_BACKUP"
    echo "    - Delete data:    $DELETE_DATA"
    echo "    - Reset cluster:  $RESET_CLUSTER"
    echo "    - Dry run:        $DRY_RUN"
    echo ""
    echo "======================================================================"
    echo ""

    if ! confirm "This will tear down the Kubernetes cluster. Continue?"; then
        log INFO "Aborted by user"
        exit 0
    fi

    check_prerequisites

    phase_backup
    phase_applications
    phase_monitoring
    phase_infrastructure
    phase_network_policies
    phase_storage
    phase_metallb
    phase_namespaces
    phase_cluster_reset

    echo ""
    log STEP "Teardown Complete"
    echo ""
    echo "Backup location: $BACKUP_DIR"
    echo ""

    if [[ "$RESET_CLUSTER" == "true" ]]; then
        echo "The cluster has been fully reset."
        echo "Run the rebuild script to create a new cluster."
    else
        echo "Remaining resources:"
        kubectl get nodes 2>/dev/null || echo "  (cluster not accessible)"
        kubectl get namespaces 2>/dev/null || true
    fi

    echo ""
    log OK "Teardown script completed successfully"
}

main "$@"
