#!/usr/bin/env bash
# =============================================================================
# Local Development Environment Setup
# =============================================================================
# Sets up AWX, Jenkins, Prometheus, and Grafana on your Beelink homelab
# =============================================================================

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# MetalLB IPs
PROMETHEUS_IP="192.168.68.201"
GRAFANA_IP="192.168.68.202"
ALERTMANAGER_IP="192.168.68.203"
ARGOCD_IP="192.168.68.204"
AWX_IP="192.168.68.205"
JENKINS_IP="192.168.68.206"

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║           Local Development Environment Setup                             ║"
    echo "║           Middleware Platform - Beelink Homelab                           ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_step() { echo -e "\n${BLUE}${BOLD}▶ $1${NC}"; }

check_prerequisites() {
    log_step "Checking prerequisites"
    command -v kubectl &> /dev/null && log_info "✓ kubectl found"
    command -v helm &> /dev/null && log_info "✓ helm found"
    kubectl cluster-info &> /dev/null && log_info "✓ Kubernetes cluster accessible"
}

setup_namespaces() {
    log_step "Creating namespaces"
    for ns in middleware monitoring awx jenkins; do
        kubectl create namespace $ns 2>/dev/null || log_info "Namespace $ns exists"
    done
}

setup_monitoring() {
    log_step "Setting up Prometheus + Grafana"
    
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --set prometheus.service.type=LoadBalancer \
        --set prometheus.service.loadBalancerIP=${PROMETHEUS_IP} \
        --set grafana.service.type=LoadBalancer \
        --set grafana.service.loadBalancerIP=${GRAFANA_IP} \
        --set grafana.adminPassword=admin \
        --set alertmanager.service.type=LoadBalancer \
        --set alertmanager.service.loadBalancerIP=${ALERTMANAGER_IP} \
        --wait --timeout 10m
    
    log_info "Prometheus: http://${PROMETHEUS_IP}:9090"
    log_info "Grafana: http://${GRAFANA_IP}:3000 (admin/admin)"
    log_info "AlertManager: http://${ALERTMANAGER_IP}:9093"
}

setup_jenkins() {
    log_step "Setting up Jenkins"

    helm repo add jenkins https://charts.jenkins.io
    helm repo update

    # Use the comprehensive values file with pod templates and plugins
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    VALUES_FILE="${SCRIPT_DIR}/../ci-cd/jenkins/kubernetes/values.yaml"

    if [[ -f "${VALUES_FILE}" ]]; then
        log_info "Using values file: ${VALUES_FILE}"
        helm upgrade --install jenkins jenkins/jenkins \
            --namespace jenkins \
            -f "${VALUES_FILE}" \
            --wait --timeout 15m
    else
        log_info "Values file not found, using defaults"
        helm upgrade --install jenkins jenkins/jenkins \
            --namespace jenkins \
            --set controller.adminPassword="JenkinsAdmin2024!" \
            --set controller.serviceType=LoadBalancer \
            --set controller.loadBalancerIP=${JENKINS_IP} \
            --set persistence.enabled=true \
            --set persistence.storageClass=longhorn \
            --wait --timeout 10m
    fi

    log_info "Jenkins: http://${JENKINS_IP}:8080 (admin/JenkinsAdmin2024!)"
    log_info "See ci-cd/jenkins/kubernetes/README.md for post-installation setup"
}

setup_awx() {
    log_step "Setting up AWX"
    
    # Install AWX Operator
    kubectl apply -f https://raw.githubusercontent.com/ansible/awx-operator/2.10.0/deploy/awx-operator.yaml -n awx || true
    sleep 30
    
    # Deploy AWX instance
    kubectl apply -f ../awx/awx-deployment.yaml
    
    log_info "AWX: http://${AWX_IP} (admin/MiddlewareAdmin2024!)"
    log_info "Note: AWX takes 5-10 minutes to fully start"
}

print_summary() {
    echo -e "\n${CYAN}${BOLD}"
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║                     SETUP COMPLETE                                         ║"
    echo "╠═══════════════════════════════════════════════════════════════════════════╣"
    echo "║  Prometheus:    http://${PROMETHEUS_IP}:9090                              ║"
    echo "║  Grafana:       http://${GRAFANA_IP}:3000     (admin/admin)               ║"
    echo "║  AlertManager:  http://${ALERTMANAGER_IP}:9093                            ║"
    echo "║  Jenkins:       http://${JENKINS_IP}:8080     (admin/JenkinsAdmin2024!)   ║"
    echo "║  AWX:           http://${AWX_IP}              (admin/MiddlewareAdmin2024!)║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

main() {
    print_banner
    check_prerequisites
    setup_namespaces
    
    case "${1:-full}" in
        --full|full)
            setup_monitoring
            setup_jenkins
            setup_awx
            ;;
        --monitoring)
            setup_monitoring
            ;;
        --jenkins)
            setup_jenkins
            ;;
        --awx)
            setup_awx
            ;;
    esac
    
    print_summary
}

main "$@"
