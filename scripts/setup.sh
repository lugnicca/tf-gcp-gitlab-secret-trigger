#!/bin/bash
# =============================================================================
# Setup Script for GCP Secret Manager to GitLab Trigger
# Interactive setup for Linux/macOS
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# =============================================================================
# Helper Functions
# =============================================================================

print_header() {
    echo ""
    echo -e "${CYAN}=============================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}=============================================${NC}"
    echo ""
}

print_step() {
    echo -e "${YELLOW}[$1]${NC} $2"
}

print_success() {
    echo -e "${GREEN}  ✓ $1${NC}"
}

print_error() {
    echo -e "${RED}  ✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}  ℹ $1${NC}"
}

# Read input with default value
read_with_default() {
    local prompt="$1"
    local default="$2"
    local result

    if [ -n "$default" ]; then
        read -p "  $prompt [$default]: " result
        echo "${result:-$default}"
    else
        read -p "  $prompt: " result
        echo "$result"
    fi
}

# Simple menu selection
select_option() {
    local prompt="$1"
    shift
    local options=("$@")

    echo -e "  ${YELLOW}$prompt${NC}"
    for i in "${!options[@]}"; do
        echo "    $((i+1)). ${options[$i]}"
    done

    local selection
    while true; do
        read -p "  Enter choice [1-${#options[@]}]: " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#options[@]}" ]; then
            echo "$((selection-1))"
            return
        fi
        echo -e "  ${RED}Invalid selection. Please try again.${NC}"
    done
}

# =============================================================================
# Start of Script
# =============================================================================

clear
print_header "GCP Secret Manager -> GitLab CI Trigger Setup"

# =============================================================================
# Step 1: Check Prerequisites
# =============================================================================

print_step "1/8" "Checking prerequisites..."

# Check gcloud
if ! command -v gcloud &> /dev/null; then
    print_error "gcloud CLI is not installed"
    echo ""
    echo "  Install from: https://cloud.google.com/sdk/docs/install"
    exit 1
fi
print_success "gcloud CLI is installed"

# Check terraform
if ! command -v terraform &> /dev/null; then
    print_error "Terraform is not installed"
    echo ""
    echo "  Install from: https://developer.hashicorp.com/terraform/downloads"
    exit 1
fi
print_success "Terraform is installed"

# Check jq (optional but helpful)
if command -v jq &> /dev/null; then
    print_success "jq is installed"
else
    print_info "jq is not installed (optional, but recommended)"
fi

# =============================================================================
# Step 2: GCP Authentication
# =============================================================================

print_step "2/8" "GCP Authentication..."

CURRENT_ACCOUNT=$(gcloud config get-value account 2>/dev/null)

if [ -n "$CURRENT_ACCOUNT" ] && [ "$CURRENT_ACCOUNT" != "(unset)" ]; then
    echo "  Current account: $CURRENT_ACCOUNT"
    echo ""
    choice=$(select_option "What would you like to do?" \
        "Continue with this account" \
        "Login with a different account")

    if [ "$choice" = "1" ]; then
        echo "  Launching authentication..."
        gcloud auth login --quiet
        gcloud auth application-default login --quiet
    fi
else
    echo "  No account logged in. Launching authentication..."
    gcloud auth login
    gcloud auth application-default login
fi
print_success "Authentication complete"

# =============================================================================
# Step 3: Project Selection
# =============================================================================

print_step "3/8" "GCP Project Configuration..."

# Get list of projects
PROJECTS=$(gcloud projects list --format="value(projectId)" 2>/dev/null)
PROJECT_ARRAY=()
while IFS= read -r line; do
    [ -n "$line" ] && PROJECT_ARRAY+=("$line")
done <<< "$PROJECTS"

if [ ${#PROJECT_ARRAY[@]} -gt 0 ]; then
    echo "  Available projects:"
    for i in "${!PROJECT_ARRAY[@]}"; do
        echo "    $((i+1)). ${PROJECT_ARRAY[$i]}"
    done
    echo "    $((${#PROJECT_ARRAY[@]}+1)). ** Create a new project **"
    echo ""

    read -p "  Select project [1-$((${#PROJECT_ARRAY[@]}+1))]: " PROJECT_CHOICE

    if [ "$PROJECT_CHOICE" = "$((${#PROJECT_ARRAY[@]}+1))" ]; then
        PROJECT_ID=$(read_with_default "New project ID (e.g., my-project-123)" "")
        PROJECT_NAME=$(read_with_default "Project name" "$PROJECT_ID")
        echo "  Creating project $PROJECT_ID..."
        gcloud projects create "$PROJECT_ID" --name="$PROJECT_NAME" 2>/dev/null || true
    else
        PROJECT_ID="${PROJECT_ARRAY[$((PROJECT_CHOICE-1))]}"
    fi
else
    PROJECT_ID=$(read_with_default "Project ID" "")
    gcloud projects create "$PROJECT_ID" 2>/dev/null || true
fi

gcloud config set project "$PROJECT_ID" 2>/dev/null
print_success "Project configured: $PROJECT_ID"

# =============================================================================
# Step 4: Billing Configuration
# =============================================================================

print_step "4/8" "Billing Configuration..."

BILLING_ENABLED=$(gcloud billing projects describe "$PROJECT_ID" --format="value(billingAccountName)" 2>/dev/null)

if [ -n "$BILLING_ENABLED" ]; then
    print_success "Billing is already configured"
else
    BILLING_ACCOUNTS=$(gcloud billing accounts list --format="value(name,displayName)" 2>/dev/null)

    if [ -n "$BILLING_ACCOUNTS" ]; then
        echo "  Available billing accounts:"
        BILLING_ARRAY=()
        BILLING_IDS=()
        i=1
        while IFS=$'\t' read -r id name; do
            BILLING_IDS+=("$id")
            BILLING_ARRAY+=("$name ($id)")
            echo "    $i. $name ($id)"
            ((i++))
        done <<< "$BILLING_ACCOUNTS"

        read -p "  Select billing account [1-${#BILLING_ARRAY[@]}]: " BILLING_CHOICE
        SELECTED_BILLING="${BILLING_IDS[$((BILLING_CHOICE-1))]}"

        echo "  Linking billing account..."
        gcloud billing projects link "$PROJECT_ID" --billing-account="$SELECTED_BILLING" 2>/dev/null
        print_success "Billing configured"
    else
        print_error "No billing accounts found"
        echo "  Configure billing manually at:"
        echo "  https://console.cloud.google.com/billing/linkedaccount?project=$PROJECT_ID"
        read -p "  Press Enter to continue..."
    fi
fi

# =============================================================================
# Step 5: Enable APIs
# =============================================================================

print_step "5/8" "Enabling GCP APIs..."

APIS=(
    "secretmanager.googleapis.com"
    "cloudfunctions.googleapis.com"
    "cloudbuild.googleapis.com"
    "eventarc.googleapis.com"
    "run.googleapis.com"
    "logging.googleapis.com"
    "cloudresourcemanager.googleapis.com"
    "artifactregistry.googleapis.com"
)

for api in "${APIS[@]}"; do
    echo -n "  Enabling $api..."
    gcloud services enable "$api" --quiet 2>/dev/null
    echo -e " ${GREEN}OK${NC}"
done

# =============================================================================
# Step 6: Cloud Audit Logs Configuration
# =============================================================================

print_step "6/8" "Cloud Audit Logs Configuration..."

echo ""
echo -e "  ${RED}IMPORTANT:${NC} You must manually enable Audit Logs for Secret Manager"
echo ""
echo "  1. Open this URL:"
echo -e "     ${CYAN}https://console.cloud.google.com/iam-admin/audit?project=$PROJECT_ID${NC}"
echo ""
echo "  2. Find 'Secret Manager API' in the list"
echo "  3. Check 'Admin Read' and 'Data Write'"
echo "  4. Click 'Save'"
echo ""

choice=$(select_option "Open the link in browser?" \
    "Yes, open now" \
    "No, I'll do it later")

if [ "$choice" = "0" ]; then
    # Try to open browser (works on most systems)
    URL="https://console.cloud.google.com/iam-admin/audit?project=$PROJECT_ID"
    if command -v xdg-open &> /dev/null; then
        xdg-open "$URL" 2>/dev/null &
    elif command -v open &> /dev/null; then
        open "$URL" 2>/dev/null &
    else
        echo "  Could not open browser automatically."
        echo "  Please open: $URL"
    fi
fi

read -p "  Press Enter when done..."

# =============================================================================
# Step 7: GitLab Configuration
# =============================================================================

print_step "7/8" "GitLab Configuration..."

# GitLab URL
echo ""
choice=$(select_option "GitLab instance:" \
    "gitlab.com (SaaS)" \
    "Self-hosted GitLab (custom URL)")

if [ "$choice" = "0" ]; then
    GITLAB_URL="https://gitlab.com"
else
    GITLAB_URL=$(read_with_default "GitLab URL (e.g., https://gitlab.company.com)" "")
fi

# GitLab Project ID
echo ""
echo "  The GitLab Project ID can be found at:"
echo "  Settings > General > Project ID (at the top)"
GITLAB_PROJECT_ID=$(read_with_default "GitLab Project ID (e.g., 12345678)" "")

# GitLab Trigger Token
echo ""
echo "  The Pipeline Trigger Token can be found at:"
echo "  Settings > CI/CD > Pipeline trigger tokens > Add new token"
GITLAB_TRIGGER_TOKEN=$(read_with_default "Pipeline Trigger Token (glptt-...)" "")

# Branch
echo ""
choice=$(select_option "Branch to trigger:" \
    "main" \
    "master" \
    "develop" \
    "Other...")

case $choice in
    0) GITLAB_REF="main" ;;
    1) GITLAB_REF="master" ;;
    2) GITLAB_REF="develop" ;;
    3) GITLAB_REF=$(read_with_default "Branch name" "") ;;
esac

# Region
echo ""
choice=$(select_option "GCP Region:" \
    "europe-west1 (Belgium)" \
    "europe-west9 (Paris)" \
    "us-central1 (Iowa)" \
    "us-east1 (South Carolina)" \
    "Other...")

case $choice in
    0) REGION="europe-west1" ;;
    1) REGION="europe-west9" ;;
    2) REGION="us-central1" ;;
    3) REGION="us-east1" ;;
    4) REGION=$(read_with_default "Region code (e.g., asia-east1)" "") ;;
esac

# Label filtering
echo ""
echo -e "  ${YELLOW}Label filtering configuration:${NC}"
echo "  Only secrets with this label will trigger the pipeline"
LABEL_KEY=$(read_with_default "Label key" "trigger-gitlab")
LABEL_VALUE=$(read_with_default "Label value" "true")

# =============================================================================
# Step 8: Generate terraform.tfvars
# =============================================================================

print_step "8/8" "Generating terraform.tfvars..."

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TFVARS_PATH="$SCRIPT_DIR/../terraform.tfvars"

cat > "$TFVARS_PATH" << EOF
# =============================================================================
# Configuration generated by setup.sh
# Date: $(date '+%Y-%m-%d %H:%M:%S')
# =============================================================================

# GCP
project_id = "$PROJECT_ID"
region     = "$REGION"

# GitLab
gitlab_url           = "$GITLAB_URL"
gitlab_project_id    = "$GITLAB_PROJECT_ID"
gitlab_trigger_token = "$GITLAB_TRIGGER_TOKEN"
gitlab_ref           = "$GITLAB_REF"

# Label filtering
required_labels = {
  "$LABEL_KEY" = "$LABEL_VALUE"
}

# Events
trigger_on_create = true
trigger_on_update = true
trigger_on_delete = false
EOF

print_success "terraform.tfvars generated"

# =============================================================================
# Summary
# =============================================================================

clear
print_header "Setup Complete!"

echo -e "  ${YELLOW}Configuration:${NC}"
echo "  ─────────────────────────────────────────"
echo "    GCP Project:      $PROJECT_ID"
echo "    Region:           $REGION"
echo "    GitLab URL:       $GITLAB_URL"
echo "    GitLab Project:   $GITLAB_PROJECT_ID"
echo "    Branch:           $GITLAB_REF"
echo "    Label filter:     $LABEL_KEY=$LABEL_VALUE"
echo ""
echo -e "  ${YELLOW}Next steps:${NC}"
echo "  ─────────────────────────────────────────"
echo -e "    ${CYAN}1. terraform init${NC}"
echo -e "    ${CYAN}2. terraform plan${NC}"
echo -e "    ${CYAN}3. terraform apply${NC}"
echo ""
echo -e "  ${YELLOW}After deployment, test with:${NC}"
echo -e "    ${CYAN}./scripts/test.sh${NC}"
echo ""

# Offer to run terraform init
choice=$(select_option "Run 'terraform init' now?" \
    "Yes" \
    "No, I'll do it manually")

if [ "$choice" = "0" ]; then
    echo ""
    echo "  Running terraform init..."
    cd "$SCRIPT_DIR/.."
    terraform init
fi

echo ""
echo -e "${GREEN}Setup complete!${NC}"
echo ""
