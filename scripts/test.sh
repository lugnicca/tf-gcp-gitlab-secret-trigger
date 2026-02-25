#!/usr/bin/env bash
# =============================================================================
# End-to-end test for secret-gitlab-trigger
#
# Usage: ./scripts/test.sh [project-id]
#
# Prerequisites:
#   - gcloud CLI authenticated
#   - terraform apply already done
#   - jq installed
# =============================================================================
set -euo pipefail

PROJECT_ID="${1:-$(terraform output -raw 2>/dev/null || gcloud config get-value project)}"
FUNCTION_NAME="secret-gitlab-trigger"
REGION="europe-west1"
SECRET_NAME="test-trigger-$$"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[..]${NC} $1"; }
fail()  { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

cleanup() {
  warn "Cleaning up secret ${SECRET_NAME}..."
  gcloud secrets delete "$SECRET_NAME" --project="$PROJECT_ID" --quiet 2>/dev/null || true
  if [ -n "${SECRET_NO_LABEL:-}" ]; then
    gcloud secrets delete "$SECRET_NO_LABEL" --project="$PROJECT_ID" --quiet 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "============================================="
echo " End-to-end test: secret-gitlab-trigger"
echo " Project: ${PROJECT_ID}"
echo "============================================="
echo ""

# -----------------------------------------------
# 1. Check Cloud Function is ACTIVE
# -----------------------------------------------
warn "Checking Cloud Function status..."
STATE=$(gcloud functions describe "$FUNCTION_NAME" \
  --region="$REGION" --gen2 --project="$PROJECT_ID" \
  --format="value(state)" 2>/dev/null)

if [ "$STATE" = "ACTIVE" ]; then
  log "Cloud Function is ACTIVE"
else
  fail "Cloud Function state: ${STATE:-NOT FOUND}"
fi

# -----------------------------------------------
# 2. Check Eventarc triggers exist
# -----------------------------------------------
warn "Checking Eventarc triggers..."
TRIGGER_COUNT=$(gcloud eventarc triggers list \
  --location="$REGION" --project="$PROJECT_ID" \
  --filter="name:${FUNCTION_NAME}-*" \
  --format="value(name)" 2>/dev/null | wc -l | tr -d ' ')

if [ "$TRIGGER_COUNT" -ge 1 ]; then
  log "Found ${TRIGGER_COUNT} Eventarc trigger(s)"
else
  fail "No Eventarc triggers found"
fi

# -----------------------------------------------
# 3. Test: secret WITH matching labels (should trigger)
# -----------------------------------------------
warn "Creating test secret with matching labels..."
gcloud secrets create "$SECRET_NAME" \
  --labels=application=n8n \
  --project="$PROJECT_ID" \
  --quiet

log "Secret ${SECRET_NAME} created"

warn "Adding a version (triggers AddSecretVersion event)..."
echo -n "test-value-$(date +%s)" | gcloud secrets versions add "$SECRET_NAME" \
  --data-file=- --project="$PROJECT_ID" --quiet

log "Secret version added"

# -----------------------------------------------
# 4. Wait for event propagation and check logs
# -----------------------------------------------
warn "Waiting 90s for Eventarc event propagation..."
sleep 90

warn "Checking function logs..."
LOGS=$(gcloud functions logs read "$FUNCTION_NAME" \
  --region="$REGION" --gen2 --project="$PROJECT_ID" \
  --limit=30 --freshness=5m 2>/dev/null)

if echo "$LOGS" | grep -q "Received event"; then
  log "Function received the event"
else
  warn "No 'Received event' in logs yet (may need more time)"
fi

if echo "$LOGS" | grep -q "Pipeline triggered successfully\|Triggering GitLab pipeline"; then
  log "GitLab pipeline was triggered!"
elif echo "$LOGS" | grep -q "does not have required labels\|skipping"; then
  fail "Function skipped the event (label mismatch)"
elif echo "$LOGS" | grep -q "Error\|ERROR"; then
  warn "Function logged an error (check logs for details)"
  echo "$LOGS" | grep -i error | head -5
else
  warn "Could not confirm pipeline trigger from logs (check manually)"
fi

# -----------------------------------------------
# 5. Test: secret WITHOUT matching labels (should NOT trigger)
# -----------------------------------------------
SECRET_NO_LABEL="test-no-trigger-$$"
warn "Creating secret WITHOUT matching labels..."
gcloud secrets create "$SECRET_NO_LABEL" \
  --project="$PROJECT_ID" --quiet

echo -n "should-not-trigger" | gcloud secrets versions add "$SECRET_NO_LABEL" \
  --data-file=- --project="$PROJECT_ID" --quiet

log "Secret without labels created"

warn "Waiting 90s for negative test..."
sleep 90

LOGS_NEG=$(gcloud functions logs read "$FUNCTION_NAME" \
  --region="$REGION" --gen2 --project="$PROJECT_ID" \
  --limit=20 --freshness=5m 2>/dev/null)

if echo "$LOGS_NEG" | grep -q "$SECRET_NO_LABEL.*does not have required labels\|$SECRET_NO_LABEL.*skipping"; then
  log "Negative test passed: secret without labels was correctly skipped"
elif echo "$LOGS_NEG" | grep -q "$SECRET_NO_LABEL"; then
  warn "Function received the event for ${SECRET_NO_LABEL} (check if it was skipped)"
else
  warn "No logs for ${SECRET_NO_LABEL} yet (may need more time)"
fi

# -----------------------------------------------
# 6. Check audit logs
# -----------------------------------------------
warn "Checking audit logs..."
AUDIT=$(gcloud logging read \
  "protoPayload.methodName=\"google.cloud.secretmanager.v1.SecretManagerService.AddSecretVersion\" \
   protoPayload.resourceName:${SECRET_NAME}" \
  --project="$PROJECT_ID" --limit=3 --freshness=10m \
  --format="table(timestamp,protoPayload.methodName)" 2>/dev/null)

if [ -n "$AUDIT" ]; then
  log "Audit log entries found"
else
  warn "No audit log entries yet (can take a few minutes)"
fi

echo ""
echo "============================================="
echo " Test complete"
echo "============================================="
echo ""
echo "Manual checks:"
echo "  - GitLab: check if a pipeline was triggered"
echo "  - Logs:   gcloud functions logs read ${FUNCTION_NAME} --region=${REGION} --gen2 --limit=30"
echo ""
