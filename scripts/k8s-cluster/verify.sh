#!/bin/bash
#===============================================================================
# Kubernetes Cluster Verification Script
#===============================================================================
# Validates that all components of the Beelink cluster are healthy and
# functioning correctly.
#
# Usage:
#   ./verify.sh [OPTIONS]
#
# Options:
#   --quick         Quick check (skip detailed tests)
#   --json          Output results as JSON
#   -v, --verbose   Show detailed output
#   -h, --help      Show this help message
#
#===============================================================================

set -euo pipefail

# Configuration
MASTER_IP="192.168.68.93"
IP_INGRESS="192.168.68.200"
IP_PROMETHEUS="192.168.68.201"
IP_GRAFANA="192.168.68.202"
IP_ALERTMANAGER="192.168.68.203"
IP_LOKI="192.168.68.204"
IP_JAEGER="192.168.68.205"
IP_JENKINS="192.168.68.206"

# Options
QUICK_MODE=false
JSON_OUTPUT=false
VERBOSE=false

# Counters
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# JSON results array
JSON_RESULTS="[]"

check_pass() {
    local name="$1"
    local details="${2:-}"
    PASS_COUNT=$((PASS_COUNT + 1))

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        JSON_RESULTS=$(echo "$JSON_RESULTS" | jq --arg n "$name" --arg d "$details" '. + [{"name": $n, "status": "pass", "details": $d}]')
    else
        echo -e "${GREEN}✓${NC} $name"
        if [[ "$VERBOSE" == "true" && -n "$details" ]]; then
            echo -e "  ${CYAN}$details${NC}"
        fi
    fi
}

check_fail() {
    local name="$1"
    local details="${2:-}"
    FAIL_COUNT=$((FAIL_COUNT + 1))

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        JSON_RESULTS=$(echo "$JSON_RESULTS" | jq --arg n "$name" --arg d "$details" '. + [{"name": $n, "status": "fail", "details": $d}]')
    else
        echo -e "${RED}✗${NC} $name"
        if [[ -n "$details" ]]; then
            echo -e "  ${RED}$details${NC}"
        fi
    fi
}

check_warn() {
    local name="$1"
    local details="${2:-}"
    WARN_COUNT=$((WARN_COUNT + 1))

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        JSON_RESULTS=$(echo "$JSON_RESULTS" | jq --arg n "$name" --arg d "$details" '. + [{"name": $n, "status": "warn", "details": $d}]')
    else
        echo -e "${YELLOW}!${NC} $name"
        if [[ -n "$details" ]]; then
            echo -e "  ${YELLOW}$details${NC}"
        fi
    fi
}

section() {
    if [[ "$JSON_OUTPUT" != "true" ]]; then
        echo ""
        echo -e "${BLUE}━━━ $1 ━━━${NC}"
    fi
}

show_help() {
    head -18 "$0" | tail -13
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --quick)    QUICK_MODE=true; shift ;;
            --json)     JSON_OUTPUT=true; shift ;;
            -v|--verbose) VERBOSE=true; shift ;;
            -h|--help)  show_help ;;
            *)          echo "Unknown option: $1"; show_help ;;
        esac
    done
}

#===============================================================================
# Verification Functions
#===============================================================================

verify_cluster_connectivity() {
    section "Cluster Connectivity"

    if kubectl cluster-info &>/dev/null; then
        check_pass "Cluster accessible"
    else
        check_fail "Cluster accessible" "Cannot connect to cluster"
        return 1
    fi
}

verify_nodes() {
    section "Nodes"

    local node_count
    node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)

    if [[ "$node_count" -eq 3 ]]; then
        check_pass "Node count" "3 nodes present"
    elif [[ "$node_count" -gt 0 ]]; then
        check_warn "Node count" "$node_count nodes (expected 3)"
    else
        check_fail "Node count" "No nodes found"
        return 1
    fi

    # Check node status
    local ready_count
    ready_count=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || echo "0")

    if [[ "$ready_count" -eq "$node_count" ]]; then
        check_pass "All nodes Ready"
    else
        check_fail "All nodes Ready" "Only $ready_count of $node_count nodes are Ready"
    fi

    # Check for node conditions
    local memory_pressure
    memory_pressure=$(kubectl get nodes -o json | jq '[.items[].status.conditions[] | select(.type=="MemoryPressure" and .status=="True")] | length')
    if [[ "$memory_pressure" -eq 0 ]]; then
        check_pass "No memory pressure"
    else
        check_warn "Memory pressure" "$memory_pressure nodes under memory pressure"
    fi

    local disk_pressure
    disk_pressure=$(kubectl get nodes -o json | jq '[.items[].status.conditions[] | select(.type=="DiskPressure" and .status=="True")] | length')
    if [[ "$disk_pressure" -eq 0 ]]; then
        check_pass "No disk pressure"
    else
        check_warn "Disk pressure" "$disk_pressure nodes under disk pressure"
    fi
}

verify_system_pods() {
    section "System Pods"

    # CoreDNS
    local coredns_ready
    coredns_ready=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$coredns_ready" -ge 1 ]]; then
        check_pass "CoreDNS running" "$coredns_ready pods"
    else
        check_fail "CoreDNS running"
    fi

    # kube-proxy
    local kubeproxy_ready
    kubeproxy_ready=$(kubectl get pods -n kube-system -l k8s-app=kube-proxy --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$kubeproxy_ready" -ge 3 ]]; then
        check_pass "kube-proxy running" "$kubeproxy_ready pods"
    else
        check_warn "kube-proxy running" "$kubeproxy_ready pods"
    fi

    # Calico
    local calico_ready
    calico_ready=$(kubectl get pods -n calico-system --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$calico_ready" -ge 3 ]]; then
        check_pass "Calico running" "$calico_ready pods"
    else
        check_warn "Calico running" "$calico_ready pods (may use different CNI)"
    fi
}

verify_storage() {
    section "Storage"

    # Longhorn
    if kubectl get namespace longhorn-system &>/dev/null; then
        local longhorn_ready
        longhorn_ready=$(kubectl get pods -n longhorn-system --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        if [[ "$longhorn_ready" -ge 5 ]]; then
            check_pass "Longhorn running" "$longhorn_ready pods"
        else
            check_warn "Longhorn running" "$longhorn_ready pods"
        fi

        # Check default StorageClass
        local default_sc
        default_sc=$(kubectl get storageclass -o json | jq -r '.items[] | select(.metadata.annotations["storageclass.kubernetes.io/is-default-class"]=="true") | .metadata.name' 2>/dev/null || echo "")
        if [[ -n "$default_sc" ]]; then
            check_pass "Default StorageClass" "$default_sc"
        else
            check_warn "Default StorageClass" "Not set"
        fi
    else
        check_warn "Longhorn" "Not installed"
    fi
}

verify_metallb() {
    section "MetalLB"

    if kubectl get namespace metallb-system &>/dev/null; then
        local metallb_ready
        metallb_ready=$(kubectl get pods -n metallb-system --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        if [[ "$metallb_ready" -ge 4 ]]; then
            check_pass "MetalLB running" "$metallb_ready pods"
        else
            check_fail "MetalLB running" "$metallb_ready pods"
        fi

        # Check IPAddressPool
        local pool_count
        pool_count=$(kubectl get ipaddresspools -n metallb-system --no-headers 2>/dev/null | wc -l)
        if [[ "$pool_count" -ge 1 ]]; then
            check_pass "IPAddressPool configured" "$pool_count pools"
        else
            check_fail "IPAddressPool configured"
        fi

        # Check L2Advertisement
        local l2_count
        l2_count=$(kubectl get l2advertisements -n metallb-system --no-headers 2>/dev/null | wc -l)
        if [[ "$l2_count" -ge 1 ]]; then
            check_pass "L2Advertisement configured"
        else
            check_fail "L2Advertisement configured"
        fi
    else
        check_fail "MetalLB" "Not installed"
    fi
}

verify_liberty() {
    section "Liberty Application"

    if kubectl get namespace liberty &>/dev/null; then
        # Check deployment
        local liberty_ready
        liberty_ready=$(kubectl get pods -n liberty -l app=liberty --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        if [[ "$liberty_ready" -ge 1 ]]; then
            check_pass "Liberty pods running" "$liberty_ready pods"
        else
            check_fail "Liberty pods running"
        fi

        # Check service
        if kubectl get svc liberty-service -n liberty &>/dev/null; then
            check_pass "Liberty service exists"
        else
            check_fail "Liberty service exists"
        fi

        # Health check
        if [[ "$QUICK_MODE" != "true" ]]; then
            local health_status
            health_status=$(curl -sk -o /dev/null -w "%{http_code}" -H "Host: liberty.local" "https://${IP_INGRESS}/health/ready" 2>/dev/null || echo "000")
            if [[ "$health_status" == "200" ]]; then
                check_pass "Liberty health endpoint" "HTTPS $health_status"
            elif [[ "$health_status" == "000" ]]; then
                check_warn "Liberty health endpoint" "Not accessible"
            else
                check_fail "Liberty health endpoint" "HTTPS $health_status"
            fi
        fi

        # Check HPA
        if kubectl get hpa liberty-hpa -n liberty &>/dev/null; then
            check_pass "Liberty HPA configured"
        else
            check_warn "Liberty HPA configured" "Not found"
        fi

        # Check PDB
        if kubectl get pdb liberty-pdb -n liberty &>/dev/null; then
            check_pass "Liberty PDB configured"
        else
            check_warn "Liberty PDB configured" "Not found"
        fi
    else
        check_warn "Liberty namespace" "Not found"
    fi
}

verify_monitoring() {
    section "Monitoring Stack"

    if kubectl get namespace monitoring &>/dev/null; then
        # Prometheus
        local prom_ready
        prom_ready=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        if [[ "$prom_ready" -ge 1 ]]; then
            check_pass "Prometheus running" "$prom_ready pods"
        else
            check_fail "Prometheus running"
        fi

        if [[ "$QUICK_MODE" != "true" ]]; then
            local prom_status
            prom_status=$(curl -s -o /dev/null -w "%{http_code}" "http://${IP_PROMETHEUS}:9090/-/ready" 2>/dev/null || echo "000")
            if [[ "$prom_status" == "200" ]]; then
                check_pass "Prometheus endpoint" "HTTP $prom_status"
            else
                check_warn "Prometheus endpoint" "HTTP $prom_status"
            fi
        fi

        # Grafana
        local grafana_ready
        grafana_ready=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        if [[ "$grafana_ready" -ge 1 ]]; then
            check_pass "Grafana running"
        else
            check_fail "Grafana running"
        fi

        if [[ "$QUICK_MODE" != "true" ]]; then
            local grafana_status
            grafana_status=$(curl -s -o /dev/null -w "%{http_code}" "http://${IP_GRAFANA}:80/api/health" 2>/dev/null || echo "000")
            if [[ "$grafana_status" == "200" ]]; then
                check_pass "Grafana endpoint" "HTTP $grafana_status"
            else
                check_warn "Grafana endpoint" "HTTP $grafana_status"
            fi
        fi

        # Alertmanager
        local am_ready
        am_ready=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=alertmanager --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        if [[ "$am_ready" -ge 1 ]]; then
            check_pass "Alertmanager running"
        else
            check_warn "Alertmanager running"
        fi

        # Loki
        local loki_ready
        loki_ready=$(kubectl get pods -n monitoring -l app=loki --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        if [[ "$loki_ready" -ge 1 ]]; then
            check_pass "Loki running"
        else
            check_warn "Loki running" "Not found"
        fi

        # Promtail
        local promtail_ready
        promtail_ready=$(kubectl get pods -n monitoring -l app=promtail --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        if [[ "$promtail_ready" -ge 3 ]]; then
            check_pass "Promtail running" "$promtail_ready pods (DaemonSet)"
        else
            check_warn "Promtail running" "$promtail_ready pods"
        fi

        # ServiceMonitors
        local sm_count
        sm_count=$(kubectl get servicemonitors -n monitoring --no-headers 2>/dev/null | wc -l)
        if [[ "$sm_count" -ge 1 ]]; then
            check_pass "ServiceMonitors configured" "$sm_count"
        else
            check_warn "ServiceMonitors configured" "None found"
        fi
    else
        check_warn "Monitoring namespace" "Not found"
    fi
}

verify_ingress() {
    section "Ingress Controller"

    if kubectl get namespace ingress-nginx &>/dev/null; then
        local ingress_ready
        ingress_ready=$(kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        if [[ "$ingress_ready" -ge 1 ]]; then
            check_pass "Ingress controller running"
        else
            check_fail "Ingress controller running"
        fi

        # Check LoadBalancer IP
        local lb_ip
        lb_ip=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        if [[ -n "$lb_ip" ]]; then
            check_pass "Ingress LoadBalancer IP" "$lb_ip"
        else
            check_fail "Ingress LoadBalancer IP" "Not assigned"
        fi
    else
        check_warn "Ingress controller" "Not installed"
    fi
}

verify_cicd() {
    section "CI/CD Tools"

    # Jenkins
    if kubectl get namespace jenkins &>/dev/null; then
        local jenkins_ready
        jenkins_ready=$(kubectl get pods -n jenkins -l app.kubernetes.io/name=jenkins --no-headers 2>/dev/null | { grep "Running" || true; } | wc -l)
        if [[ "$jenkins_ready" -ge 1 ]]; then
            check_pass "Jenkins running"
        else
            check_warn "Jenkins running"
        fi
    else
        check_warn "Jenkins" "Not installed"
    fi

    # AWX
    if kubectl get namespace awx &>/dev/null; then
        local awx_ready
        awx_ready=$(kubectl get pods -n awx --no-headers 2>/dev/null | { grep "Running" || true; } | wc -l)
        if [[ "$awx_ready" -ge 1 ]]; then
            check_pass "AWX running"
        else
            check_warn "AWX running" "Not found"
        fi
    else
        check_warn "AWX" "Not installed"
    fi
}

verify_network_policies() {
    section "Network Policies"

    local np_count
    np_count=$(kubectl get networkpolicies -A --no-headers 2>/dev/null | wc -l)
    if [[ "$np_count" -ge 5 ]]; then
        check_pass "Network policies" "$np_count policies"
    elif [[ "$np_count" -ge 1 ]]; then
        check_warn "Network policies" "$np_count policies"
    else
        check_warn "Network policies" "None configured"
    fi

    # Check for default-deny in liberty namespace
    if kubectl get networkpolicy default-deny-ingress -n liberty &>/dev/null; then
        check_pass "Liberty default-deny ingress"
    else
        check_warn "Liberty default-deny ingress" "Not found"
    fi
}

verify_secrets() {
    section "Secrets Management"

    # External Secrets Operator
    if kubectl get namespace external-secrets &>/dev/null; then
        local eso_ready
        eso_ready=$(kubectl get pods -n external-secrets --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        if [[ "$eso_ready" -ge 1 ]]; then
            check_pass "External Secrets Operator"
        else
            check_warn "External Secrets Operator"
        fi

        # Check ClusterSecretStores
        local css_count
        css_count=$(kubectl get clustersecretstores --no-headers 2>/dev/null | wc -l)
        if [[ "$css_count" -ge 1 ]]; then
            check_pass "ClusterSecretStores" "$css_count configured"
        else
            check_warn "ClusterSecretStores" "None configured"
        fi
    else
        check_warn "External Secrets Operator" "Not installed"
    fi

    # Check Liberty secrets
    if kubectl get secret liberty-secrets -n liberty &>/dev/null; then
        check_pass "Liberty secrets exist"
    else
        check_fail "Liberty secrets exist"
    fi
}

verify_pod_security() {
    section "Pod Security"

    # Check namespace labels for PSS
    local liberty_pss
    liberty_pss=$(kubectl get namespace liberty -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null || echo "")
    if [[ "$liberty_pss" == "restricted" ]]; then
        check_pass "Liberty PSS enforcement" "restricted"
    elif [[ -n "$liberty_pss" ]]; then
        check_warn "Liberty PSS enforcement" "$liberty_pss"
    else
        check_warn "Liberty PSS enforcement" "Not configured"
    fi
}

print_summary() {
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        jq -n \
            --argjson results "$JSON_RESULTS" \
            --arg pass "$PASS_COUNT" \
            --arg fail "$FAIL_COUNT" \
            --arg warn "$WARN_COUNT" \
            '{
                summary: {
                    passed: ($pass | tonumber),
                    failed: ($fail | tonumber),
                    warnings: ($warn | tonumber),
                    total: (($pass | tonumber) + ($fail | tonumber) + ($warn | tonumber))
                },
                results: $results
            }'
    else
        echo ""
        echo "======================================================================"
        echo "  Verification Summary"
        echo "======================================================================"
        echo ""
        echo -e "  ${GREEN}Passed:${NC}   $PASS_COUNT"
        echo -e "  ${RED}Failed:${NC}   $FAIL_COUNT"
        echo -e "  ${YELLOW}Warnings:${NC} $WARN_COUNT"
        echo ""

        if [[ "$FAIL_COUNT" -eq 0 ]]; then
            echo -e "  ${GREEN}All critical checks passed!${NC}"
        else
            echo -e "  ${RED}Some critical checks failed. Please review.${NC}"
        fi
        echo ""
    fi
}

main() {
    parse_args "$@"

    if [[ "$JSON_OUTPUT" != "true" ]]; then
        echo ""
        echo "======================================================================"
        echo "  Beelink Kubernetes Cluster Verification"
        echo "======================================================================"
    fi

    verify_cluster_connectivity
    verify_nodes
    verify_system_pods
    verify_storage
    verify_metallb
    verify_ingress
    verify_monitoring
    verify_liberty
    verify_cicd
    verify_network_policies
    verify_secrets
    verify_pod_security

    print_summary

    # Exit with error code if any critical failures
    if [[ "$FAIL_COUNT" -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
