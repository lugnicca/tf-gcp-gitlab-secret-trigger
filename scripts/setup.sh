#!/usr/bin/env bash
# =============================================================================
# Setup: initialize and deploy the infrastructure
#
# Usage: ./scripts/setup.sh
#
# Prerequisites:
#   - gcloud CLI authenticated
#   - terraform installed
#   - terraform.tfvars configured
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[..]${NC} $1"; }
fail()  { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

echo "============================================="
echo " Setup: secret-gitlab-trigger"
echo "============================================="
echo ""

# -----------------------------------------------
# 1. Check prerequisites
# -----------------------------------------------
warn "Checking prerequisites..."

command -v terraform >/dev/null 2>&1 || fail "terraform not found"
command -v gcloud >/dev/null 2>&1 || fail "gcloud not found"
command -v git >/dev/null 2>&1 || fail "git not found"

log "All tools available"

# -----------------------------------------------
# 2. Check GCP auth
# -----------------------------------------------
warn "Checking GCP authentication..."
ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1)
if [ -n "$ACCOUNT" ]; then
  log "Authenticated as ${ACCOUNT}"
else
  fail "Not authenticated. Run: gcloud auth application-default login"
fi

# -----------------------------------------------
# 3. Check terraform.tfvars
# -----------------------------------------------
if [ ! -f terraform.tfvars ]; then
  fail "terraform.tfvars not found. Copy terraform.tfvars.example and fill in values."
fi
log "terraform.tfvars found"

# -----------------------------------------------
# 4. Test git clone
# -----------------------------------------------
warn "Testing git source access..."
SOURCE_URL=$(grep 'source_git_url' terraform.tfvars 2>/dev/null | sed 's/.*= *"\(.*\)"/\1/' || true)
if [ -z "$SOURCE_URL" ]; then
  SOURCE_URL="https://github.com/lugnicca/secret-gitlab-trigger-test.git"
fi

TAG=$(git ls-remote --tags --sort=-v:refname "$SOURCE_URL" "v*" | head -1 | sed 's|.*refs/tags/||')
if [ -n "$TAG" ]; then
  log "Git source accessible — latest tag: ${TAG}"
else
  fail "Cannot read tags from ${SOURCE_URL}"
fi

# -----------------------------------------------
# 5. Terraform init
# -----------------------------------------------
warn "Running terraform init..."
terraform init -upgrade
log "Terraform initialized"

# -----------------------------------------------
# 6. Terraform plan
# -----------------------------------------------
warn "Running terraform plan..."
terraform plan -out=tfplan
log "Plan generated"

# -----------------------------------------------
# 7. Confirm and apply
# -----------------------------------------------
echo ""
read -p "Apply this plan? (y/N) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
  terraform apply tfplan
  rm -f tfplan
  log "Infrastructure deployed!"
  echo ""
  echo "Next step: ./scripts/test.sh"
else
  rm -f tfplan
  warn "Apply cancelled"
fi
