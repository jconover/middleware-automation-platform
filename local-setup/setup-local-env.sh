#!/usr/bin/env bash
# =============================================================================
# Local Development Environment Setup
# =============================================================================
# Sets up AWX, Jenkins, Prometheus, and Grafana on your Beelink homelab
#
# SECURITY: Credentials are configured via environment variables.
# Set these before running:
#   export GRAFANA_ADMIN_PASSWORD="your-secure-password"
#   export JENKINS_ADMIN_PASSWORD="your-secure-password"
#   export AWX_ADMIN_PASSWORD="your-secure-password"
#
# Or use --generate-passwords to create random credentials.
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
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

# Credential file for storing generated passwords
CREDENTIALS_FILE="${HOME}/.local-env-credentials"
GENERATE_PASSWORDS=false

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║           Local Development Environment Setup                             ║"
    echo "║           Middleware Platform - Beelink Homelab                           ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "\n${BLUE}${BOLD}▶ $1${NC}"; }

generate_password() {
    # Generate a secure random password (20 chars, alphanumeric + special)
    openssl rand -base64 24 | tr -dc 'a-zA-Z0-9!@#$%' | head -c 20
}

setup_credentials() {
    log_step "Configuring credentials"

    if [[ "${GENERATE_PASSWORDS}" == "true" ]]; then
        log_info "Generating random passwords..."
        GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-$(generate_password)}"
        JENKINS_ADMIN_PASSWORD="${JENKINS_ADMIN_PASSWORD:-$(generate_password)}"
        AWX_ADMIN_PASSWORD="${AWX_ADMIN_PASSWORD:-$(generate_password)}"

        # Save credentials to file (readable only by owner)
        log_info "Saving credentials to ${CREDENTIALS_FILE}"
        cat > "${CREDENTIALS_FILE}" << EOF
# Generated credentials for local development environment
# Created: $(date -Iseconds)
# KEEP THIS FILE SECURE - DELETE WHEN NO LONGER NEEDED

export GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD}"
export JENKINS_ADMIN_PASSWORD="${JENKINS_ADMIN_PASSWORD}"
export AWX_ADMIN_PASSWORD="${AWX_ADMIN_PASSWORD}"
EOF
        chmod 600 "${CREDENTIALS_FILE}"
        log_warn "Credentials saved to ${CREDENTIALS_FILE} (chmod 600)"
    else
        # Check for required environment variables
        local missing_vars=()

        if [[ -z "${GRAFANA_ADMIN_PASSWORD:-}" ]]; then
            missing_vars+=("GRAFANA_ADMIN_PASSWORD")
        fi
        if [[ -z "${JENKINS_ADMIN_PASSWORD:-}" ]]; then
            missing_vars+=("JENKINS_ADMIN_PASSWORD")
        fi
        if [[ -z "${AWX_ADMIN_PASSWORD:-}" ]]; then
            missing_vars+=("AWX_ADMIN_PASSWORD")
        fi

        if [[ ${#missing_vars[@]} -gt 0 ]]; then
            log_error "Missing required environment variables:"
            for var in "${missing_vars[@]}"; do
                echo -e "  ${RED}✗${NC} ${var}"
            done
            echo ""
            echo "Set credentials before running:"
            echo "  export GRAFANA_ADMIN_PASSWORD=\"your-secure-password\""
            echo "  export JENKINS_ADMIN_PASSWORD=\"your-secure-password\""
            echo "  export AWX_ADMIN_PASSWORD=\"your-secure-password\""
            echo ""
            echo "Or use --generate-passwords to create random credentials."
            exit 1
        fi

        log_info "Using credentials from environment variables"
    fi

    # Validate password strength (minimum 8 characters)
    for cred_name in GRAFANA_ADMIN_PASSWORD JENKINS_ADMIN_PASSWORD AWX_ADMIN_PASSWORD; do
        local cred_value="${!cred_name}"
        if [[ ${#cred_value} -lt 8 ]]; then
            log_error "${cred_name} must be at least 8 characters"
            exit 1
        fi
    done

    log_info "✓ All credentials configured"
}

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
        --set grafana.adminPassword="${GRAFANA_ADMIN_PASSWORD}" \
        --set alertmanager.service.type=LoadBalancer \
        --set alertmanager.service.loadBalancerIP=${ALERTMANAGER_IP} \
        --wait --timeout 10m

    log_info "Prometheus: http://${PROMETHEUS_IP}:9090"
    log_info "Grafana: http://${GRAFANA_IP}:3000 (admin/<from env>)"
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
        # Override password from values file with environment variable
        helm upgrade --install jenkins jenkins/jenkins \
            --namespace jenkins \
            -f "${VALUES_FILE}" \
            --set controller.adminPassword="${JENKINS_ADMIN_PASSWORD}" \
            --wait --timeout 15m
    else
        log_info "Values file not found, using defaults"
        helm upgrade --install jenkins jenkins/jenkins \
            --namespace jenkins \
            --set controller.adminPassword="${JENKINS_ADMIN_PASSWORD}" \
            --set controller.serviceType=LoadBalancer \
            --set controller.loadBalancerIP=${JENKINS_IP} \
            --set persistence.enabled=true \
            --set persistence.storageClass=longhorn \
            --wait --timeout 10m
    fi

    log_info "Jenkins: http://${JENKINS_IP}:8080 (admin/<from env>)"
    log_info "See ci-cd/jenkins/kubernetes/README.md for post-installation setup"
}

setup_awx() {
    log_step "Setting up AWX"

    # Create AWX admin password secret
    kubectl create secret generic awx-admin-password \
        --namespace awx \
        --from-literal=password="${AWX_ADMIN_PASSWORD}" \
        --dry-run=client -o yaml | kubectl apply -f -

    # Install AWX Operator
    kubectl apply -f https://raw.githubusercontent.com/ansible/awx-operator/2.10.0/deploy/awx-operator.yaml -n awx || true
    sleep 30

    # Deploy AWX instance
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    kubectl apply -f "${SCRIPT_DIR}/../awx/awx-deployment.yaml"

    log_info "AWX: http://${AWX_IP} (admin/<from env>)"
    log_info "Note: AWX takes 5-10 minutes to fully start"
}

print_summary() {
    echo -e "\n${CYAN}${BOLD}"
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║                     SETUP COMPLETE                                         ║"
    echo "╠═══════════════════════════════════════════════════════════════════════════╣"
    echo "║  Prometheus:    http://${PROMETHEUS_IP}:9090                               ║"
    echo "║  Grafana:       http://${GRAFANA_IP}:3000     (admin/\$GRAFANA_ADMIN_PASSWORD)║"
    echo "║  AlertManager:  http://${ALERTMANAGER_IP}:9093                             ║"
    echo "║  Jenkins:       http://${JENKINS_IP}:8080     (admin/\$JENKINS_ADMIN_PASSWORD)║"
    echo "║  AWX:           http://${AWX_IP}              (admin/\$AWX_ADMIN_PASSWORD)   ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    if [[ "${GENERATE_PASSWORDS}" == "true" ]] && [[ -f "${CREDENTIALS_FILE}" ]]; then
        echo -e "${YELLOW}${BOLD}Credentials saved to: ${CREDENTIALS_FILE}${NC}"
        echo -e "${YELLOW}To view credentials: cat ${CREDENTIALS_FILE}${NC}"
        echo -e "${YELLOW}To source credentials: source ${CREDENTIALS_FILE}${NC}"
    fi
}

show_help() {
    echo "Usage: $0 [OPTIONS] [COMPONENT]"
    echo ""
    echo "Sets up local development environment on Kubernetes."
    echo ""
    echo "Components:"
    echo "  full           Install all components (default)"
    echo "  --monitoring   Install Prometheus + Grafana only"
    echo "  --jenkins      Install Jenkins only"
    echo "  --awx          Install AWX only"
    echo ""
    echo "Options:"
    echo "  --generate-passwords   Generate random passwords instead of using env vars"
    echo "  --help                 Show this help message"
    echo ""
    echo "Environment variables (required unless --generate-passwords is used):"
    echo "  GRAFANA_ADMIN_PASSWORD   Grafana admin password"
    echo "  JENKINS_ADMIN_PASSWORD   Jenkins admin password"
    echo "  AWX_ADMIN_PASSWORD       AWX admin password"
    echo ""
    echo "Examples:"
    echo "  # Set credentials and run full setup"
    echo "  export GRAFANA_ADMIN_PASSWORD='MySecurePass123!'"
    echo "  export JENKINS_ADMIN_PASSWORD='MySecurePass123!'"
    echo "  export AWX_ADMIN_PASSWORD='MySecurePass123!'"
    echo "  $0 full"
    echo ""
    echo "  # Generate random credentials and save to file"
    echo "  $0 --generate-passwords full"
    echo ""
    echo "  # Install only monitoring with generated passwords"
    echo "  $0 --generate-passwords --monitoring"
}

main() {
    local component="full"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --generate-passwords)
                GENERATE_PASSWORDS=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            --full|full)
                component="full"
                shift
                ;;
            --monitoring)
                component="monitoring"
                shift
                ;;
            --jenkins)
                component="jenkins"
                shift
                ;;
            --awx)
                component="awx"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    print_banner
    check_prerequisites
    setup_credentials
    setup_namespaces

    case "${component}" in
        full)
            setup_monitoring
            setup_jenkins
            setup_awx
            ;;
        monitoring)
            setup_monitoring
            ;;
        jenkins)
            setup_jenkins
            ;;
        awx)
            setup_awx
            ;;
    esac

    print_summary
}

main "$@"
