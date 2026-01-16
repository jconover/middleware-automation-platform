#!/usr/bin/env bash
# =============================================================================
# Enterprise Middleware Platform - Automated Deployment Script
# =============================================================================
# Orchestrates complete deployment with timing comparison
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Detect if stdout is a terminal for color support
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'
    BOLD='\033[1m'
else
    RED=''
    GREEN=''
    YELLOW=''
    CYAN=''
    NC=''
    BOLD=''
fi

# Defaults
ENVIRONMENT="dev"
DRY_RUN=false
FORCE=false
PHASE="all"
VERSION=""

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

validate_environment() {
    # Unified environment structure: dev, stage, prod
    local allowed_environments=("dev" "stage" "prod")
    local valid=false
    for env in "${allowed_environments[@]}"; do
        [[ "$ENVIRONMENT" == "$env" ]] && valid=true && break
    done
    if [[ "$valid" != true ]]; then
        echo -e "${RED}[ERROR]${NC} Invalid environment '$ENVIRONMENT'. Allowed: ${allowed_environments[*]}"
        exit 1
    fi
    # Path traversal check
    if [[ "$ENVIRONMENT" == *".."* ]] || [[ "$ENVIRONMENT" == *"/"* ]]; then
        echo -e "${RED}[ERROR]${NC} Environment contains invalid characters"
        exit 1
    fi
}

validate_version() {
    local version="$1"
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9]+)?$ ]]; then
        echo -e "${YELLOW}[WARN]${NC} Version '$version' doesn't follow semver format (x.y.z)"
    fi
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

    # Use unified environment structure: environments/aws with per-env configs
    local tf_dir="${PROJECT_ROOT}/automated/terraform/environments/aws"
    local backend_config="backends/${ENVIRONMENT}.backend.hcl"
    local var_file="envs/${ENVIRONMENT}.tfvars"

    cd "$tf_dir"
    log_info "Deploying to AWS environment: ${ENVIRONMENT}"
    log_info "Using backend config: ${backend_config}"
    log_info "Using var file: ${var_file}"

    # Initialize with environment-specific backend
    terraform init -input=false -backend-config="${backend_config}" -reconfigure

    if [[ "$DRY_RUN" == true ]]; then
        terraform plan -var-file="${var_file}"
    else
        terraform plan -var-file="${var_file}"
        if [[ "$FORCE" != true ]]; then
            echo ""
            read -p "Apply these changes? (yes/no): " confirm
            if [[ "$confirm" != "yes" ]]; then
                echo "Aborted."
                exit 1
            fi
        fi
        terraform apply -auto-approve -var-file="${var_file}"
    fi

    stop_timer "infrastructure"
}

deploy_liberty() {
    log_phase "Phase 2: Liberty Installation"
    start_timer "liberty"

    cd "${PROJECT_ROOT}/automated/ansible"
    # Run common first to ensure prerequisites, then liberty
    local args="-i inventory/${ENVIRONMENT}.yml playbooks/site.yml --tags common,liberty"
    [[ "$DRY_RUN" == true ]] && args+=" --check"

    # shellcheck disable=SC2086 # Intentional word splitting for ansible args
    ansible-playbook $args
    cd "${PROJECT_ROOT}"

    stop_timer "liberty"
}

deploy_monitoring() {
    log_phase "Phase 3: Monitoring"
    start_timer "monitoring"

    cd "${PROJECT_ROOT}/automated/ansible"
    local args="-i inventory/${ENVIRONMENT}.yml playbooks/site.yml --tags monitoring"
    [[ "$DRY_RUN" == true ]] && args+=" --check"

    # shellcheck disable=SC2086 # Intentional word splitting for ansible args
    ansible-playbook $args
    cd "${PROJECT_ROOT}"

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
    echo "  -e, --environment   Environment (dev, stage, prod) [default: dev]"
    echo "  -p, --phase         Phase (all, infrastructure, liberty, monitoring)"
    echo "  -v, --version       Liberty version to deploy (e.g., 1.0.0)"
    echo "  -d, --dry-run       Dry run mode"
    echo "  -f, --force         Skip confirmation prompts (use with caution)"
    echo "  -h, --help          Show help"
    echo ""
    echo "Examples:"
    echo "  $0 -e dev                    # Deploy to dev environment"
    echo "  $0 -e prod -f                # Deploy to prod without confirmation"
    echo "  $0 -e stage -p infrastructure # Only deploy infrastructure to stage"
    echo "  $0 -e dev -d                 # Dry run for dev environment"
    echo ""
    echo "Infrastructure:"
    echo "  Uses unified Terraform environment: environments/aws/"
    echo "  Backend configs: backends/{dev,stage,prod}.backend.hcl"
    echo "  Variable files:  envs/{dev,stage,prod}.tfvars"
    echo ""
    echo "ECS Resources (when enabled):"
    echo "  Cluster: mw-{env}-cluster"
    echo "  Service: mw-{env}-liberty"
}

main() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment) ENVIRONMENT="$2"; shift 2 ;;
            -p|--phase) PHASE="$2"; shift 2 ;;
            -v|--version) VERSION="$2"; shift 2 ;;
            -d|--dry-run) DRY_RUN=true; shift ;;
            -f|--force) FORCE=true; shift ;;
            -h|--help) show_help; exit 0 ;;
            -*)
                echo -e "${RED}[ERROR]${NC} Unknown option: $1"
                echo "Use --help for usage information."
                exit 1
                ;;
            *)
                echo -e "${RED}[ERROR]${NC} Unexpected argument: $1"
                exit 1
                ;;
        esac
    done
    
    print_banner
    TOTAL_START=$(date +%s)

    validate_environment
    if [[ -n "$VERSION" ]]; then
        validate_version "$VERSION"
    fi
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
