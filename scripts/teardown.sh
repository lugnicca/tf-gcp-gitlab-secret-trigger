#!/usr/bin/env bash
# =============================================================================
# Teardown: destroy all infrastructure
#
# Usage: ./scripts/teardown.sh
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[..]${NC} $1"; }

echo "============================================="
echo " Teardown: secret-gitlab-trigger"
echo "============================================="
echo ""
echo "This will DESTROY all resources created by Terraform."
echo ""
read -p "Are you sure? (y/N) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  warn "Cancelled"
  exit 0
fi

warn "Destroying infrastructure..."
terraform destroy -auto-approve

log "All resources destroyed"
