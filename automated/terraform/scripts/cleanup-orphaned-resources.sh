#!/usr/bin/env bash
# =============================================================================
# Cleanup Orphaned AWS Resources Script
# =============================================================================
# Removes orphaned AWS resources that may block terraform operations.
# Use this when terraform fails due to resources that still exist but are
# not tracked in the state (e.g., secrets scheduled for deletion, log groups).
#
# Usage: ./cleanup-orphaned-resources.sh [OPTIONS] [ENV_PREFIX]
#
# Arguments:
#   ENV_PREFIX     Environment prefix (default: mw-prod)
#
# Options:
#   -h, --help     Show this help message and exit
#   -d, --dry-run  Show what would be deleted without making changes
#   -y, --yes      Skip confirmation prompt
#
# Examples:
#   ./cleanup-orphaned-resources.sh                    # Clean mw-prod resources
#   ./cleanup-orphaned-resources.sh mw-staging         # Clean mw-staging resources
#   ./cleanup-orphaned-resources.sh --dry-run          # Preview deletions
#   ./cleanup-orphaned-resources.sh -y mw-prod         # Skip confirmation
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
DRY_RUN=false
SKIP_CONFIRM=false
ENV_PREFIX=""

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "\n${BLUE}>>> $1${NC}"; }

print_banner() {
    echo -e "${YELLOW}"
    echo "============================================================================="
    echo "           Cleanup Orphaned AWS Resources"
    echo "           Middleware Automation Platform"
    echo "============================================================================="
    echo -e "${NC}"
}

usage() {
    # Extract usage from header comments
    sed -n '2,/^# ====/p' "$0" | grep '^#' | sed 's/^# //' | sed 's/^#//'
    exit 0
}

validate_env_prefix() {
    local prefix="$1"

    # Check for empty prefix
    if [[ -z "$prefix" ]]; then
        log_error "Environment prefix cannot be empty."
        exit 1
    fi

    # Validate prefix format (alphanumeric with hyphens, 3-20 chars)
    if [[ ! "$prefix" =~ ^[a-z][a-z0-9-]{2,19}$ ]]; then
        log_error "Invalid environment prefix: '$prefix'"
        log_error "Prefix must start with lowercase letter, contain only lowercase letters, numbers, and hyphens, and be 3-20 characters."
        exit 1
    fi
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
    log_info "Region: $AWS_REGION"
}

confirm_cleanup() {
    if [[ "$SKIP_CONFIRM" == "true" ]]; then
        return 0
    fi

    echo ""
    echo -e "${YELLOW}This will delete orphaned resources for prefix: ${ENV_PREFIX}${NC}"
    echo ""
    read -p "Continue? (yes/no): " CONFIRM

    if [[ "$CONFIRM" != "yes" ]]; then
        log_info "Cleanup cancelled."
        exit 0
    fi
}

cleanup_secrets() {
    log_step "Checking Secrets Manager..."

    local secret_id="${ENV_PREFIX}/database/credentials"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would delete secret: $secret_id"
        return
    fi

    if aws secretsmanager delete-secret \
        --region "$AWS_REGION" \
        --secret-id "$secret_id" \
        --force-delete-without-recovery 2>/dev/null; then
        log_info "Deleted: $secret_id"
    else
        log_info "Not found or already deleted: $secret_id"
    fi
}

cleanup_log_groups() {
    log_step "Checking CloudWatch Log Groups..."

    local log_group="/aws/vpc/${ENV_PREFIX}-flow-logs"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would delete log group: $log_group"
        return
    fi

    if aws logs delete-log-group \
        --region "$AWS_REGION" \
        --log-group-name "$log_group" 2>/dev/null; then
        log_info "Deleted: $log_group"
    else
        log_info "Not found or already deleted: $log_group"
    fi
}

cleanup_ecs_log_groups() {
    log_step "Checking ECS CloudWatch Log Groups..."

    local log_group="/ecs/${ENV_PREFIX}-liberty"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would delete log group: $log_group"
        return
    fi

    if aws logs delete-log-group \
        --region "$AWS_REGION" \
        --log-group-name "$log_group" 2>/dev/null; then
        log_info "Deleted: $log_group"
    else
        log_info "Not found or already deleted: $log_group"
    fi
}

print_summary() {
    echo ""
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run complete. No changes were made."
        echo ""
        echo "To execute the cleanup, run without --dry-run:"
        echo "  $0 $ENV_PREFIX"
    else
        log_info "Cleanup complete. You can now run 'terraform apply'"
    fi
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
            -y|--yes)
                SKIP_CONFIRM=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                echo "Use --help for usage information."
                exit 1
                ;;
            *)
                if [[ -z "$ENV_PREFIX" ]]; then
                    ENV_PREFIX="$1"
                else
                    log_error "Unexpected argument: $1"
                    echo "Use --help for usage information."
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Set default if not provided
    ENV_PREFIX="${ENV_PREFIX:-mw-prod}"
}

main() {
    parse_args "$@"

    print_banner

    # Validate inputs
    validate_env_prefix "$ENV_PREFIX"

    log_info "Environment prefix: $ENV_PREFIX"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Running in DRY-RUN mode - no changes will be made"
    fi

    # Check AWS configuration
    check_aws_cli

    # Confirm before proceeding
    confirm_cleanup

    # Cleanup resources
    cleanup_secrets
    cleanup_log_groups
    cleanup_ecs_log_groups

    # Print summary
    print_summary

    log_info "Done!"
}

main "$@"
