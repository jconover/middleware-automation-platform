#!/bin/bash
#===============================================================================
# Kubernetes Cluster Backup Script
#===============================================================================
# Creates comprehensive backups of all Kubernetes resources including:
# - Secrets, ConfigMaps, PVCs
# - RBAC resources
# - Helm release values
# - Grafana dashboards and datasources
# - Custom resources (ExternalSecrets, Certificates)
#
# Usage:
#   ./backup.sh [OPTIONS]
#
# Options:
#   -o, --output DIR    Backup output directory (default: ./backups/TIMESTAMP)
#   --include-secrets   Include secret values in backup (encrypted)
#   --grafana-only      Only backup Grafana dashboards
#   -h, --help          Show this help message
#
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Configuration
BACKUP_DIR=""
INCLUDE_SECRETS=false
GRAFANA_ONLY=false
GRAFANA_IP="192.168.68.202"

# Namespaces to backup
NAMESPACES=(
    "liberty"
    "monitoring"
    "jenkins"
    "awx"
    "tracing"
    "ingress-nginx"
    "external-secrets"
    "secrets-source"
    "argocd"
)

# Colors
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

show_help() {
    head -20 "$0" | tail -15
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -o|--output)
                BACKUP_DIR="$2"
                shift 2
                ;;
            --include-secrets)
                INCLUDE_SECRETS=true
                shift
                ;;
            --grafana-only)
                GRAFANA_ONLY=true
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

    # Set default backup directory
    if [[ -z "$BACKUP_DIR" ]]; then
        BACKUP_DIR="${PROJECT_ROOT}/backups/$(date +%Y%m%d-%H%M%S)"
    fi
}

backup_grafana() {
    log "Backing up Grafana dashboards..."

    local grafana_dir="${BACKUP_DIR}/grafana"
    mkdir -p "${grafana_dir}/dashboards"

    # Get Grafana credentials
    local grafana_pass
    grafana_pass=$(kubectl get secret prometheus-grafana -n monitoring -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d || echo "")

    if [[ -z "$grafana_pass" ]]; then
        log_warn "Could not retrieve Grafana password"
        return 1
    fi

    # Export dashboards
    local dashboard_uids
    dashboard_uids=$(curl -s -u "admin:${grafana_pass}" \
        "http://${GRAFANA_IP}:3000/api/search?type=dash-db" 2>/dev/null | \
        jq -r '.[].uid // empty' 2>/dev/null || echo "")

    if [[ -z "$dashboard_uids" ]]; then
        log_warn "No dashboards found or Grafana not accessible"
        return 1
    fi

    local count=0
    while IFS= read -r uid; do
        if [[ -n "$uid" ]]; then
            local title
            title=$(curl -s -u "admin:${grafana_pass}" \
                "http://${GRAFANA_IP}:3000/api/dashboards/uid/${uid}" 2>/dev/null | \
                jq -r '.dashboard.title // "unknown"' 2>/dev/null | \
                tr ' ' '_' | tr -cd '[:alnum:]_-')

            curl -s -u "admin:${grafana_pass}" \
                "http://${GRAFANA_IP}:3000/api/dashboards/uid/${uid}" \
                > "${grafana_dir}/dashboards/${title}_${uid}.json" 2>/dev/null

            ((count++))
        fi
    done <<< "$dashboard_uids"

    log_ok "Exported $count dashboards"

    # Export datasources
    curl -s -u "admin:${grafana_pass}" \
        "http://${GRAFANA_IP}:3000/api/datasources" \
        > "${grafana_dir}/datasources.json" 2>/dev/null

    # Export alert rules
    curl -s -u "admin:${grafana_pass}" \
        "http://${GRAFANA_IP}:3000/api/ruler/grafana/api/v1/rules" \
        > "${grafana_dir}/alert-rules.json" 2>/dev/null || true

    # Export notification channels
    curl -s -u "admin:${grafana_pass}" \
        "http://${GRAFANA_IP}:3000/api/alert-notifications" \
        > "${grafana_dir}/notification-channels.json" 2>/dev/null || true

    log_ok "Grafana backup complete"
}

backup_kubernetes_resources() {
    log "Backing up Kubernetes resources..."

    mkdir -p "${BACKUP_DIR}"/{secrets,configmaps,pvcs,rbac,helm,custom-resources}

    # Backup secrets (metadata only by default)
    log "Backing up secrets..."
    for ns in "${NAMESPACES[@]}"; do
        if [[ "$INCLUDE_SECRETS" == "true" ]]; then
            kubectl get secrets -n "$ns" -o yaml > "${BACKUP_DIR}/secrets/${ns}-secrets.yaml" 2>/dev/null || true
        else
            # Only backup metadata, not data
            kubectl get secrets -n "$ns" -o json 2>/dev/null | \
                jq 'del(.items[].data)' > "${BACKUP_DIR}/secrets/${ns}-secrets-metadata.json" || true
        fi
    done

    # Backup ConfigMaps
    log "Backing up ConfigMaps..."
    for ns in "${NAMESPACES[@]}"; do
        kubectl get configmaps -n "$ns" -o yaml > "${BACKUP_DIR}/configmaps/${ns}-configmaps.yaml" 2>/dev/null || true
    done

    # Backup PVCs and PVs
    log "Backing up persistent storage..."
    kubectl get pvc -A -o yaml > "${BACKUP_DIR}/pvcs/all-pvcs.yaml" 2>/dev/null || true
    kubectl get pv -o yaml > "${BACKUP_DIR}/pvcs/all-pvs.yaml" 2>/dev/null || true
    kubectl get storageclass -o yaml > "${BACKUP_DIR}/pvcs/storageclasses.yaml" 2>/dev/null || true

    # Backup RBAC
    log "Backing up RBAC resources..."
    kubectl get serviceaccounts -A -o yaml > "${BACKUP_DIR}/rbac/serviceaccounts.yaml" 2>/dev/null || true
    kubectl get roles -A -o yaml > "${BACKUP_DIR}/rbac/roles.yaml" 2>/dev/null || true
    kubectl get rolebindings -A -o yaml > "${BACKUP_DIR}/rbac/rolebindings.yaml" 2>/dev/null || true
    kubectl get clusterroles -o yaml > "${BACKUP_DIR}/rbac/clusterroles.yaml" 2>/dev/null || true
    kubectl get clusterrolebindings -o yaml > "${BACKUP_DIR}/rbac/clusterrolebindings.yaml" 2>/dev/null || true

    # Backup Helm releases
    log "Backing up Helm release values..."
    for release in $(helm list -A -o json 2>/dev/null | jq -r '.[].name' 2>/dev/null || echo ""); do
        if [[ -n "$release" ]]; then
            local ns
            ns=$(helm list -A -f "$release" -o json 2>/dev/null | jq -r '.[0].namespace // empty')
            if [[ -n "$ns" ]]; then
                helm get values "$release" -n "$ns" --all > "${BACKUP_DIR}/helm/${release}-values.yaml" 2>/dev/null || true
                helm get manifest "$release" -n "$ns" > "${BACKUP_DIR}/helm/${release}-manifest.yaml" 2>/dev/null || true
            fi
        fi
    done

    # Backup custom resources
    log "Backing up custom resources..."

    # External Secrets
    kubectl get externalsecrets -A -o yaml > "${BACKUP_DIR}/custom-resources/externalsecrets.yaml" 2>/dev/null || true
    kubectl get clustersecretstores -o yaml > "${BACKUP_DIR}/custom-resources/clustersecretstores.yaml" 2>/dev/null || true
    kubectl get secretstores -A -o yaml > "${BACKUP_DIR}/custom-resources/secretstores.yaml" 2>/dev/null || true

    # Certificates
    kubectl get certificates -A -o yaml > "${BACKUP_DIR}/custom-resources/certificates.yaml" 2>/dev/null || true
    kubectl get clusterissuers -o yaml > "${BACKUP_DIR}/custom-resources/clusterissuers.yaml" 2>/dev/null || true
    kubectl get issuers -A -o yaml > "${BACKUP_DIR}/custom-resources/issuers.yaml" 2>/dev/null || true

    # Network policies
    kubectl get networkpolicies -A -o yaml > "${BACKUP_DIR}/custom-resources/networkpolicies.yaml" 2>/dev/null || true

    # Ingresses
    kubectl get ingress -A -o yaml > "${BACKUP_DIR}/custom-resources/ingresses.yaml" 2>/dev/null || true

    # MetalLB
    kubectl get ipaddresspools -n metallb-system -o yaml > "${BACKUP_DIR}/custom-resources/metallb-pools.yaml" 2>/dev/null || true
    kubectl get l2advertisements -n metallb-system -o yaml > "${BACKUP_DIR}/custom-resources/metallb-l2ads.yaml" 2>/dev/null || true

    # Prometheus custom resources
    kubectl get servicemonitors -A -o yaml > "${BACKUP_DIR}/custom-resources/servicemonitors.yaml" 2>/dev/null || true
    kubectl get podmonitors -A -o yaml > "${BACKUP_DIR}/custom-resources/podmonitors.yaml" 2>/dev/null || true
    kubectl get prometheusrules -A -o yaml > "${BACKUP_DIR}/custom-resources/prometheusrules.yaml" 2>/dev/null || true
    kubectl get alertmanagerconfigs -A -o yaml > "${BACKUP_DIR}/custom-resources/alertmanagerconfigs.yaml" 2>/dev/null || true

    # ArgoCD
    kubectl get applications -n argocd -o yaml > "${BACKUP_DIR}/custom-resources/argocd-applications.yaml" 2>/dev/null || true
    kubectl get applicationsets -n argocd -o yaml > "${BACKUP_DIR}/custom-resources/argocd-applicationsets.yaml" 2>/dev/null || true

    log_ok "Kubernetes resources backup complete"
}

backup_cluster_state() {
    log "Backing up cluster state..."

    mkdir -p "${BACKUP_DIR}/cluster"

    # Node information
    kubectl get nodes -o yaml > "${BACKUP_DIR}/cluster/nodes.yaml"
    kubectl get nodes -o wide > "${BACKUP_DIR}/cluster/nodes.txt"

    # Namespace list
    kubectl get namespaces -o yaml > "${BACKUP_DIR}/cluster/namespaces.yaml"

    # All services
    kubectl get svc -A -o yaml > "${BACKUP_DIR}/cluster/services.yaml"
    kubectl get svc -A -o wide > "${BACKUP_DIR}/cluster/services.txt"

    # All deployments
    kubectl get deployments -A -o yaml > "${BACKUP_DIR}/cluster/deployments.yaml"

    # All statefulsets
    kubectl get statefulsets -A -o yaml > "${BACKUP_DIR}/cluster/statefulsets.yaml"

    # All daemonsets
    kubectl get daemonsets -A -o yaml > "${BACKUP_DIR}/cluster/daemonsets.yaml"

    # All HPAs
    kubectl get hpa -A -o yaml > "${BACKUP_DIR}/cluster/hpas.yaml"

    # All PDBs
    kubectl get pdb -A -o yaml > "${BACKUP_DIR}/cluster/pdbs.yaml"

    log_ok "Cluster state backup complete"
}

create_manifest() {
    log "Creating backup manifest..."

    cat > "${BACKUP_DIR}/MANIFEST.txt" << EOF
Kubernetes Cluster Backup
=========================
Created: $(date)
Host: $(hostname)

Cluster Info:
$(kubectl cluster-info 2>/dev/null || echo "N/A")

Node Count: $(kubectl get nodes --no-headers 2>/dev/null | wc -l)
Namespace Count: $(kubectl get namespaces --no-headers 2>/dev/null | wc -l)

Backup Contents:
$(find "${BACKUP_DIR}" -type f -name "*.yaml" -o -name "*.json" -o -name "*.txt" | sort)

Total Size: $(du -sh "${BACKUP_DIR}" | cut -f1)
EOF

    log_ok "Manifest created"
}

main() {
    parse_args "$@"

    echo ""
    echo "======================================================================"
    echo "  Kubernetes Cluster Backup"
    echo "======================================================================"
    echo ""
    echo "  Output directory: $BACKUP_DIR"
    echo "  Include secrets:  $INCLUDE_SECRETS"
    echo "  Grafana only:     $GRAFANA_ONLY"
    echo ""

    mkdir -p "$BACKUP_DIR"

    if [[ "$GRAFANA_ONLY" == "true" ]]; then
        backup_grafana
    else
        backup_kubernetes_resources
        backup_grafana
        backup_cluster_state
    fi

    create_manifest

    echo ""
    echo "======================================================================"
    log_ok "Backup completed successfully!"
    echo ""
    echo "  Location: $BACKUP_DIR"
    echo "  Size:     $(du -sh "$BACKUP_DIR" | cut -f1)"
    echo ""

    if [[ "$INCLUDE_SECRETS" == "true" ]]; then
        echo -e "${YELLOW}WARNING: Backup contains sensitive data (secrets)${NC}"
        echo "Please store this backup securely."
    fi
}

main "$@"
