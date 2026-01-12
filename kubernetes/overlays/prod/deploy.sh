#!/bin/bash
# =============================================================================
# Production Overlay Deployment Script
# =============================================================================
# Resolves the AWS_ACCOUNT_ID placeholder and deploys to Kubernetes.
#
# Usage:
#   ./deploy.sh                    # Apply to cluster
#   ./deploy.sh --dry-run          # Preview without applying
#   ./deploy.sh --generate-only    # Output resolved YAML to stdout
#
# Prerequisites:
#   - AWS CLI configured with valid credentials
#   - kubectl configured with target cluster context
#   - envsubst available (usually pre-installed on Linux)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Parse arguments
DRY_RUN=false
GENERATE_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --generate-only)
            GENERATE_ONLY=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--dry-run] [--generate-only]"
            echo ""
            echo "Options:"
            echo "  --dry-run        Preview changes without applying"
            echo "  --generate-only  Output resolved YAML to stdout"
            echo "  -h, --help       Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check prerequisites
command -v aws >/dev/null 2>&1 || { log_error "AWS CLI is required but not installed."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { log_error "kubectl is required but not installed."; exit 1; }
command -v envsubst >/dev/null 2>&1 || { log_error "envsubst is required but not installed."; exit 1; }

# Get AWS Account ID
log_info "Retrieving AWS Account ID..."

# Try Terraform first (if state is available)
if [[ -d "${PROJECT_ROOT}/automated/terraform/environments/aws" ]]; then
    TERRAFORM_DIR="${PROJECT_ROOT}/automated/terraform/environments/aws"
    if terraform -chdir="${TERRAFORM_DIR}" output -raw ecr_repository_url >/dev/null 2>&1; then
        ECR_URL=$(terraform -chdir="${TERRAFORM_DIR}" output -raw ecr_repository_url 2>/dev/null || true)
        if [[ -n "${ECR_URL}" ]]; then
            # Extract account ID from ECR URL (format: ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/repo)
            export AWS_ACCOUNT_ID=$(echo "${ECR_URL}" | cut -d'.' -f1)
            log_info "Retrieved AWS Account ID from Terraform: ${AWS_ACCOUNT_ID}"
        fi
    fi
fi

# Fall back to AWS STS if Terraform didn't work
if [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    if [[ -z "${AWS_ACCOUNT_ID}" ]]; then
        log_error "Failed to retrieve AWS Account ID. Ensure AWS credentials are configured."
        exit 1
    fi
    log_info "Retrieved AWS Account ID from STS: ${AWS_ACCOUNT_ID}"
fi

# Validate account ID format (12 digits)
if ! [[ "${AWS_ACCOUNT_ID}" =~ ^[0-9]{12}$ ]]; then
    log_error "Invalid AWS Account ID format: ${AWS_ACCOUNT_ID}"
    log_error "Expected 12-digit account ID."
    exit 1
fi

# Create temporary directory for resolved files
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

# Resolve placeholders in kustomization.yaml
log_info "Resolving AWS_ACCOUNT_ID placeholder..."
envsubst '${AWS_ACCOUNT_ID}' < "${SCRIPT_DIR}/kustomization.yaml" > "${TEMP_DIR}/kustomization.yaml"

# Copy other files that kustomization.yaml references
for file in "${SCRIPT_DIR}"/*.yaml; do
    filename=$(basename "$file")
    if [[ "$filename" != "kustomization.yaml" ]]; then
        cp "$file" "${TEMP_DIR}/"
    fi
done

# Build the kustomization
log_info "Building kustomization..."
cd "${TEMP_DIR}"

if [[ "${GENERATE_ONLY}" == "true" ]]; then
    kubectl kustomize .
    exit 0
fi

# Show what will be applied
log_info "Resolved ECR image: ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/mw-prod-liberty:1.0.0"

if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "Dry run - previewing changes..."
    kubectl apply -k . --dry-run=client -o yaml | head -100
    echo "..."
    log_info "Dry run complete. Use without --dry-run to apply."
else
    log_info "Applying to cluster..."
    kubectl apply -k .
    log_info "Deployment complete!"
fi
