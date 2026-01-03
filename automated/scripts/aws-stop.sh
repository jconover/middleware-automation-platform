#!/usr/bin/env bash
# =============================================================================
# AWS Services Stop Script
# =============================================================================
# Stops/scales down AWS services to minimize costs when not in use.
# Run aws-start.sh to bring everything back up.
#
# Usage: ./aws-stop.sh [OPTIONS]
#
# Options:
#   -d, --dry-run  Preview operations without executing them
#   --destroy      Fully destroy infrastructure (terraform destroy)
#   -h, --help     Show this help message and exit
#
# Examples:
#   ./aws-stop.sh              # Stop all services
#   ./aws-stop.sh --dry-run    # Preview what would be stopped
#   ./aws-stop.sh --destroy    # Fully destroy infrastructure
# =============================================================================

set -euo pipefail

# Detect if stdout is a terminal for color support
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
NAME_PREFIX="mw-prod"
TERRAFORM_DIR="$(dirname "$0")/../terraform/environments/prod-aws"
DRY_RUN=false
DESTROY_MODE=false

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "\n${BLUE}▶ $1${NC}"; }
log_dry_run() { echo -e "${YELLOW}[DRY-RUN]${NC} $1"; }

usage() {
    echo "AWS Services Stop Script"
    echo ""
    echo "Stops/scales down AWS services to minimize costs when not in use."
    echo "Run aws-start.sh to bring everything back up."
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -d, --dry-run  Preview operations without executing them"
    echo "  --destroy      Fully destroy infrastructure (terraform destroy)"
    echo "  -h, --help     Show this help message and exit"
    echo ""
    echo "Examples:"
    echo "  $0              # Stop all services"
    echo "  $0 --dry-run    # Preview what would be stopped"
    echo "  $0 --destroy    # Fully destroy infrastructure"
    exit 0
}

print_banner() {
    echo -e "${YELLOW}"
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║           AWS Services Stop Script                                         ║"
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

stop_ec2_instances() {
    log_step "Stopping EC2 instances (management/monitoring)..."

    # Find all instances with our name prefix (management, monitoring servers)
    # Note: Liberty EC2 instances have been decommissioned in favor of ECS
    local instance_ids_raw
    instance_ids_raw=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --filters "Name=tag:Name,Values=${NAME_PREFIX}-*" "Name=instance-state-name,Values=running" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text)

    # Convert space/tab-separated output to array for safe handling
    local -a instance_ids=()
    if [[ -n "$instance_ids_raw" ]]; then
        read -ra instance_ids <<< "$instance_ids_raw"
    fi

    if [[ ${#instance_ids[@]} -gt 0 ]]; then
        log_info "Found running instances: ${instance_ids[*]}"

        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "Would stop EC2 instances: ${instance_ids[*]}"
            return
        fi

        aws ec2 stop-instances --region "$AWS_REGION" --instance-ids "${instance_ids[@]}"
        log_info "Stop command sent. Waiting for instances to stop..."
        aws ec2 wait instance-stopped --region "$AWS_REGION" --instance-ids "${instance_ids[@]}"
        log_info "All EC2 instances stopped."
    else
        log_info "No running EC2 instances found."
    fi
}

scale_down_ecs() {
    log_step "Scaling down ECS service to 0 tasks..."

    # Check if cluster exists
    if aws ecs describe-clusters --region "$AWS_REGION" --clusters "${NAME_PREFIX}-cluster" --query 'clusters[0].status' --output text 2>/dev/null | grep -q "ACTIVE"; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "Would scale ECS service ${NAME_PREFIX}-liberty to 0 tasks"
            return
        fi

        # Scale service to 0
        aws ecs update-service \
            --region "$AWS_REGION" \
            --cluster "${NAME_PREFIX}-cluster" \
            --service "${NAME_PREFIX}-liberty" \
            --desired-count 0 \
            --no-cli-pager || log_warn "Failed to scale ECS service"

        log_info "ECS service scaled to 0 tasks."

        # Wait for tasks to drain
        log_info "Waiting for tasks to drain..."
        aws ecs wait services-stable \
            --region "$AWS_REGION" \
            --cluster "${NAME_PREFIX}-cluster" \
            --services "${NAME_PREFIX}-liberty" 2>/dev/null || true

        log_info "ECS tasks drained."
    else
        log_info "ECS cluster not found or not active."
    fi
}

stop_rds() {
    log_step "Stopping RDS instance..."

    local db_identifier="${NAME_PREFIX}-postgres"

    # Check if RDS exists and is available
    local db_status
    db_status=$(aws rds describe-db-instances \
        --region "$AWS_REGION" \
        --db-instance-identifier "$db_identifier" \
        --query 'DBInstances[0].DBInstanceStatus' \
        --output text 2>/dev/null || echo "not-found")

    if [[ "$db_status" == "available" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "Would stop RDS instance: $db_identifier"
            return
        fi

        aws rds stop-db-instance \
            --region "$AWS_REGION" \
            --db-instance-identifier "$db_identifier" \
            --no-cli-pager
        log_info "RDS stop command sent. (Takes a few minutes)"
        log_warn "Note: RDS auto-restarts after 7 days if not manually started."
    elif [[ "$db_status" == "stopped" ]]; then
        log_info "RDS instance already stopped."
    elif [[ "$db_status" == "not-found" ]]; then
        log_info "RDS instance not found."
    else
        log_warn "RDS instance in state: $db_status (cannot stop)"
    fi
}

print_cost_summary() {
    log_step "Cost Summary"

    echo ""
    echo "Resources STOPPED (no charges):"
    echo "  ✓ EC2 instances (only EBS storage charges remain)"
    echo "  ✓ ECS Fargate tasks (scaled to 0)"
    echo "  ✓ RDS instance (stopped, auto-restarts in 7 days)"
    echo ""
    echo "Resources STILL RUNNING (charges continue):"
    echo "  • NAT Gateway (~\$0.045/hour = ~\$32/month)"
    echo "  • Application Load Balancer (~\$0.025/hour = ~\$18/month)"
    echo "  • ElastiCache Redis (~\$0.017/hour = ~\$12/month)"
    echo "  • Elastic IPs (if instances stopped, ~\$0.005/hour each)"
    echo "  • EBS volumes (~\$0.10/GB/month)"
    echo ""
    echo -e "${YELLOW}To fully stop all charges, run: ./aws-stop.sh --destroy${NC}"
    echo ""
}

terraform_destroy() {
    log_step "Running terraform destroy..."

    if [[ ! -d "$TERRAFORM_DIR" ]]; then
        log_error "Terraform directory not found: $TERRAFORM_DIR"
        exit 1
    fi

    echo -e "${RED}"
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║  WARNING: This will DESTROY all AWS infrastructure!                        ║"
    echo "║                                                                            ║"
    echo "║  - All data will be lost (database, cache, logs)                          ║"
    echo "║  - You will need to run 'terraform apply' to recreate                     ║"
    echo "║  - ECR images will be preserved                                           ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    read -p "Are you sure you want to destroy all infrastructure? (yes/no): " CONFIRM

    if [[ "$CONFIRM" == "yes" ]]; then
        cd "$TERRAFORM_DIR"
        terraform destroy -auto-approve
        log_info "Infrastructure destroyed."
    else
        log_info "Destroy cancelled."
    fi
}

print_restart_instructions() {
    echo ""
    echo -e "${GREEN}To restart services, run:${NC}"
    echo "  ./aws-start.sh"
    echo ""
    echo "Or manually:"
    echo "  # Start RDS (do this first, takes ~5-10 min)"
    echo "  aws rds start-db-instance --db-instance-identifier ${NAME_PREFIX}-postgres"
    echo ""
    echo "  # Scale up ECS (primary application)"
    echo "  aws ecs update-service --cluster ${NAME_PREFIX}-cluster --service ${NAME_PREFIX}-liberty --desired-count 2"
    echo ""
    echo "  # Start EC2 instances (management/monitoring)"
    echo "  aws ec2 start-instances --instance-ids <IDS>"
    echo ""
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --destroy)
                DESTROY_MODE=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                echo "Use --help for usage information."
                exit 1
                ;;
            *)
                log_error "Unexpected argument: $1"
                echo "Use --help for usage information."
                exit 1
                ;;
        esac
    done
}

print_dry_run_summary() {
    echo ""
    log_info "Dry run complete. No changes were made."
    echo ""
    echo "To execute the stop operations, run without --dry-run:"
    echo "  $0"
    echo ""
}

main() {
    parse_args "$@"

    print_banner

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Running in DRY-RUN mode - no changes will be made"
    fi

    check_aws_cli

    if [[ "$DESTROY_MODE" == "true" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "Would run terraform destroy in $TERRAFORM_DIR"
            print_dry_run_summary
            exit 0
        fi
        terraform_destroy
    else
        stop_ec2_instances
        scale_down_ecs
        stop_rds

        if [[ "$DRY_RUN" == "true" ]]; then
            print_dry_run_summary
        else
            print_cost_summary
            print_restart_instructions
        fi
    fi

    log_info "Done!"
}

main "$@"
