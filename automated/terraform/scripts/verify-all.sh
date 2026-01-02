#!/bin/bash
set -e

echo "========================================"
echo "  Middleware Platform - Full Verification"
echo "========================================"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_http() {
    local name="$1"
    local url="$2"
    local code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null || echo "000")
    if [ "$code" = "200" ]; then
        echo -e "${GREEN}[PASS]${NC} $name"
        return 0
    else
        echo -e "${RED}[FAIL]${NC} $name (HTTP $code)"
        return 1
    fi
}

echo -e "${YELLOW}=== Podman ===${NC}"
if podman ps | grep -q liberty-server; then
    check_http "Liberty (Podman)" "http://localhost:9080/health/ready"
else
    echo -e "${YELLOW}[SKIP]${NC} Podman container not running"
fi

echo ""
echo -e "${YELLOW}=== Kubernetes ===${NC}"
if kubectl get pods -n liberty 2>/dev/null | grep -q Running; then
    echo -e "${GREEN}[PASS]${NC} Liberty pods running in K8s"
else
    echo -e "${YELLOW}[SKIP]${NC} Liberty not deployed to K8s"
fi

check_http "Prometheus" "http://192.168.68.201:9090/-/ready" || true
check_http "Grafana" "http://192.168.68.202:3000/api/health" || true
check_http "Jenkins" "http://192.168.68.206:8080/login" || true
check_http "AWX" "http://192.168.68.205/api/v2/ping/" || true

echo ""
echo -e "${YELLOW}=== AWS (if deployed) ===${NC}"
if command -v terraform &>/dev/null; then
    # Get project root dynamically for portability
    PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
        echo -e "${YELLOW}[SKIP]${NC} Not in a git repository, cannot locate Terraform directory"
        exit 0
    }
    cd "${PROJECT_ROOT}/automated/terraform/environments/prod-aws"
    ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null || echo "")
    if [ -n "$ALB_DNS" ]; then
        check_http "ALB Health" "http://$ALB_DNS/health/ready" || true
    else
        echo -e "${YELLOW}[SKIP]${NC} AWS not deployed"
    fi
fi

echo ""
echo "========================================"
echo "  Verification Complete"
echo "========================================"
