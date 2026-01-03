#!/usr/bin/env bash
# =============================================================================
# Enterprise Middleware Platform - Teardown Script
# =============================================================================
# Removes all deployed components for clean re-installation
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Secure temporary directory setup
TEMP_DIR=""

cleanup_temp_files() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

# Ensure cleanup on exit, error, or interrupt
trap cleanup_temp_files EXIT INT TERM

create_secure_temp_dir() {
    # Create temp directory with restrictive permissions
    TEMP_DIR="$(mktemp -d)" || {
        echo "ERROR: Failed to create secure temporary directory" >&2
        exit 1
    }
    chmod 700 "$TEMP_DIR"
}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Defaults
ENVIRONMENT="dev"
PHASE="all"
FORCE=false

print_banner() {
    echo -e "${RED}"
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║        Enterprise Middleware Platform - TEARDOWN                          ║"
    echo "║        This will remove all deployed components                           ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info() { echo -e "${GREEN}[INFO]${NC} $(date '+%H:%M:%S') - $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $(date '+%H:%M:%S') - $1"; }
log_phase() {
    echo -e "\n${RED}${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}${BOLD}  Teardown: $1${NC}"
    echo -e "${RED}${BOLD}═══════════════════════════════════════════════════════════════${NC}\n"
}

confirm_destroy() {
    if [[ "$FORCE" != true ]]; then
        echo -e "${RED}${BOLD}WARNING: This will destroy all deployed components!${NC}"
        echo ""
        read -p "Type 'yes' to confirm: " confirmation
        if [[ "$confirmation" != "yes" ]]; then
            echo "Aborted."
            exit 1
        fi
    fi
}

destroy_monitoring() {
    log_phase "Monitoring Stack"

    cd "${PROJECT_ROOT}/automated/ansible"

    local playbook_file="${TEMP_DIR}/destroy-monitoring.yml"
    cat > "$playbook_file" << 'EOF'
---
- name: Destroy Monitoring Stack
  hosts: monitoring_servers
  become: true
  tasks:
    - name: Stop and disable Grafana
      ansible.builtin.systemd:
        name: grafana-server
        state: stopped
        enabled: false
      ignore_errors: true

    - name: Stop and disable Prometheus
      ansible.builtin.systemd:
        name: prometheus
        state: stopped
        enabled: false
      ignore_errors: true

    - name: Stop and disable Node Exporter
      ansible.builtin.systemd:
        name: node_exporter
        state: stopped
        enabled: false
      ignore_errors: true

    - name: Remove Grafana package
      ansible.builtin.apt:
        name: grafana
        state: absent
        purge: true
      ignore_errors: true

    - name: Remove systemd service files
      ansible.builtin.file:
        path: "{{ item }}"
        state: absent
      loop:
        - /etc/systemd/system/prometheus.service
        - /etc/systemd/system/node_exporter.service

    - name: Remove Prometheus directories
      ansible.builtin.file:
        path: "{{ item }}"
        state: absent
      loop:
        - /opt/prometheus
        - /etc/prometheus
        - /var/lib/prometheus

    - name: Remove Node Exporter binary
      ansible.builtin.file:
        path: /usr/local/bin/node_exporter
        state: absent

    - name: Remove service users
      ansible.builtin.user:
        name: "{{ item }}"
        state: absent
      loop:
        - prometheus
        - node_exporter
      ignore_errors: true

    - name: Reload systemd
      ansible.builtin.systemd:
        daemon_reload: true
EOF

    ansible-playbook -i "inventory/${ENVIRONMENT}.yml" "$playbook_file"

    log_info "Monitoring stack removed"
}

destroy_liberty() {
    log_phase "Liberty Servers"

    cd "${PROJECT_ROOT}/automated/ansible"

    local playbook_file="${TEMP_DIR}/destroy-liberty.yml"
    cat > "$playbook_file" << 'EOF'
---
- name: Destroy Liberty Servers
  hosts: liberty_servers
  become: true
  tasks:
    - name: Get Liberty server name
      set_fact:
        liberty_server_name: "{{ liberty_server_name | default('appServer') }}"

    - name: Stop and disable Liberty service
      ansible.builtin.systemd:
        name: "liberty-{{ liberty_server_name }}"
        state: stopped
        enabled: false
      ignore_errors: true

    - name: Remove Liberty systemd service
      ansible.builtin.file:
        path: "/etc/systemd/system/liberty-{{ liberty_server_name }}.service"
        state: absent

    - name: Remove Liberty installation
      ansible.builtin.file:
        path: "{{ item }}"
        state: absent
      loop:
        - /opt/ibm/wlp
        - /var/log/liberty
        - /var/liberty

    - name: Remove Liberty user
      ansible.builtin.user:
        name: liberty
        state: absent
        remove: true
      ignore_errors: true

    - name: Reload systemd
      ansible.builtin.systemd:
        daemon_reload: true
EOF

    ansible-playbook -i "inventory/${ENVIRONMENT}.yml" "$playbook_file"

    log_info "Liberty servers removed"
}

destroy_infrastructure() {
    log_phase "Infrastructure (AWS only)"

    if [[ "$ENVIRONMENT" == "prod-aws" ]]; then
        cd "${PROJECT_ROOT}/automated/terraform/environments/prod-aws"
        terraform destroy -auto-approve
        log_info "AWS infrastructure destroyed"
    else
        log_warn "Local infrastructure - nothing to destroy (managed outside Terraform)"
    fi
}

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -e, --environment   Environment (dev, staging, prod-aws)"
    echo "  -p, --phase         Phase to destroy (all, liberty, monitoring, infrastructure)"
    echo "  -f, --force         Skip confirmation prompt"
    echo "  -h, --help          Show help"
    echo ""
    echo "Examples:"
    echo "  $0 --environment dev                    # Destroy everything in dev"
    echo "  $0 --environment dev --phase liberty    # Only destroy Liberty"
    echo "  $0 --environment dev --force            # Skip confirmation"
}

main() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment) ENVIRONMENT="$2"; shift 2 ;;
            -p|--phase) PHASE="$2"; shift 2 ;;
            -f|--force) FORCE=true; shift ;;
            -h|--help) show_help; exit 0 ;;
            -*)
                echo "ERROR: Unknown option: $1"
                echo "Use --help for usage information."
                exit 1
                ;;
            *)
                echo "ERROR: Unexpected argument: $1"
                exit 1
                ;;
        esac
    done

    print_banner
    confirm_destroy

    # Create secure temporary directory for playbook files
    create_secure_temp_dir

    case $PHASE in
        all)
            destroy_monitoring
            destroy_liberty
            destroy_infrastructure
            ;;
        monitoring) destroy_monitoring ;;
        liberty) destroy_liberty ;;
        infrastructure) destroy_infrastructure ;;
        *)
            echo "Unknown phase: $PHASE"
            exit 1
            ;;
    esac

    echo -e "\n${GREEN}${BOLD}Teardown complete!${NC}"
    echo -e "Run ${CYAN}./deploy.sh --environment ${ENVIRONMENT}${NC} to redeploy.\n"
}

main "$@"
