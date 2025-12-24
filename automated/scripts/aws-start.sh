#!/usr/bin/env bash
# =============================================================================
# AWS Services Start Script
# =============================================================================
# Starts AWS services that were stopped by aws-stop.sh
#
# Usage: ./aws-start.sh
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
NAME_PREFIX="mw-prod"
ECS_DESIRED_COUNT="${ECS_DESIRED_COUNT:-2}"

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "\n${BLUE}▶ $1${NC}"; }

print_banner() {
    echo -e "${GREEN}"
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║           AWS Services Start Script                                        ║"
    echo "║           Middleware Automation Platform                                   ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install it first."
        exit 1
    fi

    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi

    log_info "AWS CLI configured for account: $(aws sts get-caller-identity --query Account --output text)"
}

start_rds() {
    log_step "Starting RDS instance..."

    DB_IDENTIFIER="${NAME_PREFIX}-postgres"

    DB_STATUS=$(aws rds describe-db-instances \
        --region "$AWS_REGION" \
        --db-instance-identifier "$DB_IDENTIFIER" \
        --query 'DBInstances[0].DBInstanceStatus' \
        --output text 2>/dev/null || echo "not-found")

    if [[ "$DB_STATUS" == "stopped" ]]; then
        aws rds start-db-instance \
            --region "$AWS_REGION" \
            --db-instance-identifier "$DB_IDENTIFIER" \
            --no-cli-pager
        log_info "RDS start command sent. Waiting for availability..."

        # Wait for RDS to be available (can take 5-10 minutes)
        aws rds wait db-instance-available \
            --region "$AWS_REGION" \
            --db-instance-identifier "$DB_IDENTIFIER"
        log_info "RDS instance is now available."
    elif [[ "$DB_STATUS" == "available" ]]; then
        log_info "RDS instance already running."
    elif [[ "$DB_STATUS" == "not-found" ]]; then
        log_warn "RDS instance not found. May need to run terraform apply."
    else
        log_info "RDS instance in state: $DB_STATUS (waiting...)"
        aws rds wait db-instance-available \
            --region "$AWS_REGION" \
            --db-instance-identifier "$DB_IDENTIFIER" 2>/dev/null || true
    fi
}

start_ec2_instances() {
    log_step "Starting EC2 instances (management/monitoring)..."

    # Find all stopped instances with our name prefix (management, monitoring)
    # Note: Liberty EC2 instances have been decommissioned in favor of ECS
    INSTANCE_IDS=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --filters "Name=tag:Name,Values=${NAME_PREFIX}-*" "Name=instance-state-name,Values=stopped" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text)

    if [[ -n "$INSTANCE_IDS" ]]; then
        log_info "Found stopped instances: $INSTANCE_IDS"
        aws ec2 start-instances --region "$AWS_REGION" --instance-ids $INSTANCE_IDS
        log_info "Start command sent. Waiting for instances to run..."
        aws ec2 wait instance-running --region "$AWS_REGION" --instance-ids $INSTANCE_IDS
        log_info "All EC2 instances running."

        # Wait for status checks
        log_info "Waiting for instance status checks..."
        aws ec2 wait instance-status-ok --region "$AWS_REGION" --instance-ids $INSTANCE_IDS
        log_info "All EC2 instances passed status checks."
    else
        log_info "No stopped EC2 instances found."
    fi
}

scale_up_ecs() {
    log_step "Scaling up ECS service to ${ECS_DESIRED_COUNT} tasks..."

    # Check if cluster exists
    if aws ecs describe-clusters --region "$AWS_REGION" --clusters "${NAME_PREFIX}-cluster" --query 'clusters[0].status' --output text 2>/dev/null | grep -q "ACTIVE"; then
        # Scale service up
        aws ecs update-service \
            --region "$AWS_REGION" \
            --cluster "${NAME_PREFIX}-cluster" \
            --service "${NAME_PREFIX}-liberty" \
            --desired-count "$ECS_DESIRED_COUNT" \
            --no-cli-pager || log_warn "Failed to scale ECS service"

        log_info "ECS service scaling to ${ECS_DESIRED_COUNT} tasks..."

        # Wait for service to stabilize
        log_info "Waiting for ECS service to stabilize..."
        aws ecs wait services-stable \
            --region "$AWS_REGION" \
            --cluster "${NAME_PREFIX}-cluster" \
            --services "${NAME_PREFIX}-liberty"

        log_info "ECS service is stable with ${ECS_DESIRED_COUNT} tasks."
    else
        log_warn "ECS cluster not found. May need to run terraform apply."
    fi
}

check_health() {
    log_step "Checking service health..."

    # Get ALB DNS name
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --region "$AWS_REGION" \
        --names "${NAME_PREFIX}-alb" \
        --query 'LoadBalancers[0].DNSName' \
        --output text 2>/dev/null || echo "")

    if [[ -n "$ALB_DNS" && "$ALB_DNS" != "None" ]]; then
        log_info "ALB DNS: $ALB_DNS"

        # Check ECS health (default route)
        log_info "Checking ECS target health..."
        sleep 10
        if curl -sf "http://${ALB_DNS}/health/ready" > /dev/null 2>&1; then
            log_info "✓ ECS targets healthy"
        else
            log_warn "ECS targets not yet healthy (may need more time)"
        fi

        # Check ECS target group health via AWS API
        ECS_TG_ARN=$(aws elbv2 describe-target-groups \
            --region "$AWS_REGION" \
            --names "${NAME_PREFIX}-liberty-ecs-tg" \
            --query 'TargetGroups[0].TargetGroupArn' \
            --output text 2>/dev/null || echo "")

        if [[ -n "$ECS_TG_ARN" && "$ECS_TG_ARN" != "None" ]]; then
            HEALTHY_COUNT=$(aws elbv2 describe-target-health \
                --region "$AWS_REGION" \
                --target-group-arn "$ECS_TG_ARN" \
                --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' \
                --output text 2>/dev/null || echo "0")
            log_info "ECS healthy targets: $HEALTHY_COUNT"
        fi
    else
        log_warn "ALB not found. Infrastructure may need to be recreated."
    fi
}

print_summary() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                     ALL SERVICES STARTED                                  ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Get ALB DNS
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --region "$AWS_REGION" \
        --names "${NAME_PREFIX}-alb" \
        --query 'LoadBalancers[0].DNSName' \
        --output text 2>/dev/null || echo "N/A")

    # Get management server IP
    MGMT_IP=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --filters "Name=tag:Name,Values=${NAME_PREFIX}-management" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text 2>/dev/null || echo "N/A")

    # Get monitoring server IP
    MON_IP=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --filters "Name=tag:Name,Values=${NAME_PREFIX}-monitoring" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text 2>/dev/null || echo "N/A")

    echo "Application URL:  http://${ALB_DNS}"
    echo "Health Check:     curl http://${ALB_DNS}/health/ready"
    echo ""
    echo "Management SSH:   ssh -i ~/.ssh/ansible_ed25519 ubuntu@${MGMT_IP}"
    echo "Prometheus:       http://${MON_IP}:9090"
    echo "Grafana:          http://${MON_IP}:3000 (admin/admin)"
    echo ""
    echo "Note: Services may take a few more minutes to fully initialize."
    echo ""
}

main() {
    print_banner
    check_aws_cli

    # Start RDS first (takes longest)
    start_rds

    # Start EC2 instances
    start_ec2_instances

    # Scale up ECS
    scale_up_ecs

    # Health check
    check_health

    print_summary
    log_info "Done!"
}

main "$@"
