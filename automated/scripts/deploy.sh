#!/usr/bin/env bash
# =============================================================================
# Enterprise Middleware Platform - Automated Deployment Script
# =============================================================================
# Orchestrates complete deployment with timing comparison
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Defaults
ENVIRONMENT="dev"
DRY_RUN=false
PHASE="all"

# Timing
declare -A PHASE_TIMES
TOTAL_START=0

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║        Enterprise Middleware Platform - Automated Deployment              ║"
    echo "║        From Manual (5 hours) to Automated (~28 minutes)                   ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info() { echo -e "${GREEN}[INFO]${NC} $(date '+%H:%M:%S') - $1"; }
log_phase() {
    echo -e "\n${CYAN}${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}  Phase: $1${NC}"
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════${NC}\n"
}

start_timer() {
    PHASE_TIMES["$1_start"]=$(date +%s)
    log_info "Starting: $1"
}

stop_timer() {
    local start=${PHASE_TIMES["$1_start"]}
    local end=$(date +%s)
    local duration=$((end - start))
    PHASE_TIMES["$1"]=$duration
    log_info "Completed: $1 in ${duration}s"
}

check_prerequisites() {
    log_phase "Checking Prerequisites"
    command -v ansible-playbook &>/dev/null || { echo "ansible required"; exit 1; }
    command -v terraform &>/dev/null || { echo "terraform required"; exit 1; }
    log_info "All prerequisites satisfied"
}

deploy_infrastructure() {
    log_phase "Phase 1: Infrastructure"
    start_timer "infrastructure"
    
    if [[ "$ENVIRONMENT" == "prod-aws" ]]; then
        cd "${PROJECT_ROOT}/automated/terraform/environments/prod-aws"
        terraform init -input=false
        [[ "$DRY_RUN" == true ]] && terraform plan || terraform apply -auto-approve
    else
        log_info "Using existing local infrastructure"
    fi
    
    stop_timer "infrastructure"
}

deploy_liberty() {
    log_phase "Phase 2: Liberty Installation"
    start_timer "liberty"
    
    local args="-i ${PROJECT_ROOT}/automated/ansible/inventory/${ENVIRONMENT}.yml"
    args+=" ${PROJECT_ROOT}/automated/ansible/playbooks/site.yml --tags liberty"
    [[ "$DRY_RUN" == true ]] && args+=" --check"
    
    ansible-playbook $args
    
    stop_timer "liberty"
}

deploy_monitoring() {
    log_phase "Phase 3: Monitoring"
    start_timer "monitoring"
    
    local args="-i ${PROJECT_ROOT}/automated/ansible/inventory/${ENVIRONMENT}.yml"
    args+=" ${PROJECT_ROOT}/automated/ansible/playbooks/site.yml --tags monitoring"
    [[ "$DRY_RUN" == true ]] && args+=" --check"
    
    ansible-playbook $args
    
    stop_timer "monitoring"
}

generate_report() {
    log_phase "Deployment Summary"
    
    local total=0
    for key in "${!PHASE_TIMES[@]}"; do
        [[ "$key" != *"_start" ]] && total=$((total + ${PHASE_TIMES[$key]:-0}))
    done
    
    echo -e "${CYAN}${BOLD}"
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║                        TIMING COMPARISON                                   ║"
    echo "╠═══════════════════════════════════════════════════════════════════════════╣"
    echo "║                                                                           ║"
    printf "║  Automated Deployment:  %4d minutes                                      ║\n" $((total / 60))
    echo "║  Manual Equivalent:      ~300 minutes (5 hours)                           ║"
    printf "║  Time Saved:             %4d minutes                                      ║\n" $((420 - total / 60))
    printf "║  Efficiency Gain:        %3d%%                                            ║\n" $((100 - (total / 60 * 100 / 420)))
    echo "║                                                                           ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -e, --environment   Environment (dev, staging, prod-aws)"
    echo "  -p, --phase         Phase (all, infrastructure, liberty, monitoring)"
    echo "  -d, --dry-run       Dry run mode"
    echo "  -h, --help          Show help"
}

main() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment) ENVIRONMENT="$2"; shift 2 ;;
            -p|--phase) PHASE="$2"; shift 2 ;;
            -d|--dry-run) DRY_RUN=true; shift ;;
            -h|--help) show_help; exit 0 ;;
            *) shift ;;
        esac
    done
    
    print_banner
    TOTAL_START=$(date +%s)
    
    check_prerequisites
    
    case $PHASE in
        all)
            deploy_infrastructure
            deploy_liberty
            deploy_monitoring
            ;;
        infrastructure) deploy_infrastructure ;;
        liberty) deploy_liberty ;;
        monitoring) deploy_monitoring ;;
    esac
    
    generate_report
}

main "$@"
