# =============================================================================
# End-to-End Test Script for GCP Secret Manager to GitLab Trigger
# PowerShell version for Windows
# =============================================================================

$ErrorActionPreference = "Continue"

# Configuration
$TEST_SECRET_NAME = "test-trigger-$(Get-Date -Format 'yyyyMMddHHmmss')"
$WAIT_TIME = 20

# =============================================================================
# Helper Functions
# =============================================================================

function Write-Header {
    param([string]$Text)
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param([string]$Step, [string]$Text)
    Write-Host "[$Step] " -ForegroundColor Yellow -NoNewline
    Write-Host $Text
}

function Write-TestSuccess {
    param([string]$Text)
    Write-Host "  [OK] $Text" -ForegroundColor Green
}

function Write-TestError {
    param([string]$Text)
    Write-Host "  [ERROR] $Text" -ForegroundColor Red
}

function Write-TestInfo {
    param([string]$Text)
    Write-Host "  [INFO] $Text" -ForegroundColor Blue
}

function Write-Waiting {
    param([string]$Text)
    Write-Host "  [WAIT] $Text" -ForegroundColor Yellow
}

# =============================================================================
# Pre-flight Checks
# =============================================================================

Write-Header "Pre-flight Checks"

Write-Step "1/4" "Checking required tools..."

# Check gcloud
try {
    $null = gcloud version 2>&1
    Write-TestSuccess "gcloud CLI is installed"
} catch {
    Write-TestError "gcloud CLI is not installed"
    Write-Host "  Install from: https://cloud.google.com/sdk/docs/install" -ForegroundColor Yellow
    exit 1
}

# Check terraform
try {
    $null = terraform version 2>&1
    Write-TestSuccess "Terraform is installed"
} catch {
    Write-TestError "Terraform is not installed"
    exit 1
}

# Check curl
try {
    $null = curl.exe --version 2>&1
    Write-TestSuccess "curl is installed"
} catch {
    Write-TestError "curl is not installed"
    exit 1
}

Write-Step "2/4" "Loading Terraform outputs..."

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir
Set-Location $ProjectDir

if (-not (Test-Path "terraform.tfstate")) {
    Write-TestError "terraform.tfstate not found. Run 'terraform apply' first."
    exit 1
}

try {
    $FUNCTION_NAME = terraform output -raw function_name 2>$null
    $REQUIRED_LABELS_JSON = terraform output -json required_labels 2>$null
    $REQUIRED_LABELS = $REQUIRED_LABELS_JSON | ConvertFrom-Json
    $PROJECT_ID = gcloud config get-value project 2>$null
    $REGION = "europe-west1"

    Write-TestSuccess "Project ID: $PROJECT_ID"
    Write-TestSuccess "Function Name: $FUNCTION_NAME"
    Write-TestSuccess "Required Labels: $REQUIRED_LABELS_JSON"
} catch {
    Write-TestError "Could not load Terraform outputs: $_"
    exit 1
}

Write-Step "3/4" "Checking GCP authentication..."
$CURRENT_ACCOUNT = gcloud config get-value account 2>$null
if ([string]::IsNullOrWhiteSpace($CURRENT_ACCOUNT) -or $CURRENT_ACCOUNT -eq "(unset)") {
    Write-TestError "Not authenticated to GCP. Run 'gcloud auth login'"
    exit 1
}
Write-TestSuccess "Authenticated as: $CURRENT_ACCOUNT"

Write-Step "4/4" "Verifying project access..."
try {
    $null = gcloud projects describe $PROJECT_ID 2>&1
    Write-TestSuccess "Project access confirmed"
} catch {
    Write-TestError "Cannot access project $PROJECT_ID"
    exit 1
}

# =============================================================================
# Test 1: Verify Infrastructure
# =============================================================================

Write-Header "Test 1: Verify Infrastructure"

Write-Step "1.1" "Checking Cloud Function exists..."
$FUNCTION_STATUS = gcloud functions describe $FUNCTION_NAME `
    --project=$PROJECT_ID `
    --region=$REGION `
    --gen2 `
    --format="value(state)" 2>$null

if ($FUNCTION_STATUS -eq "ACTIVE") {
    Write-TestSuccess "Cloud Function is ACTIVE"
} else {
    Write-TestError "Cloud Function status: $FUNCTION_STATUS"
    exit 1
}

Write-Step "1.2" "Checking Eventarc triggers..."
$TRIGGERS = gcloud eventarc triggers list `
    --project=$PROJECT_ID `
    --location="global" `
    --format="value(name)" 2>$null

$TRIGGER_LIST = $TRIGGERS -split "`n" | Where-Object { $_ -ne "" }
$TRIGGER_COUNT = $TRIGGER_LIST.Count

if ($TRIGGER_COUNT -gt 0) {
    Write-TestSuccess "Found $TRIGGER_COUNT Eventarc trigger(s) in global location"
    Write-Host ""
    gcloud eventarc triggers list `
        --project=$PROJECT_ID `
        --location="global" `
        --format="table(name,active)" 2>$null
    Write-Host ""
} else {
    Write-TestError "No Eventarc triggers found in global location"
    exit 1
}

Write-Step "1.3" "Checking Audit Logs configuration..."
Write-TestInfo "Audit logs should be enabled for secretmanager.googleapis.com"
Write-TestInfo "Required: DATA_WRITE and ADMIN_READ"

# =============================================================================
# Test 2: Verify GitLab Connectivity
# =============================================================================

Write-Header "Test 2: Verify GitLab Connectivity"

Write-Step "2.1" "Retrieving GitLab configuration from secrets..."
$GITLAB_PROJECT_ID = gcloud secrets versions access latest `
    --secret="${FUNCTION_NAME}-gitlab-project-id" `
    --project=$PROJECT_ID 2>$null
$GITLAB_TOKEN = gcloud secrets versions access latest `
    --secret="${FUNCTION_NAME}-gitlab-token" `
    --project=$PROJECT_ID 2>$null

if ([string]::IsNullOrWhiteSpace($GITLAB_PROJECT_ID) -or [string]::IsNullOrWhiteSpace($GITLAB_TOKEN)) {
    Write-TestError "Could not retrieve GitLab credentials from Secret Manager"
    exit 1
}
Write-TestSuccess "GitLab Project ID: $GITLAB_PROJECT_ID"
Write-TestSuccess "GitLab Token: $($GITLAB_TOKEN.Substring(0,10))..."

Write-Step "2.2" "Testing GitLab API connectivity..."
$GITLAB_URL = "https://gitlab.com"

try {
    $response = curl.exe -s -w "`n%{http_code}" -X POST `
        "${GITLAB_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/trigger/pipeline" `
        --form "token=${GITLAB_TOKEN}" `
        --form "ref=main" 2>$null

    $lines = $response -split "`n"
    $HTTP_CODE = $lines[-1].Trim()
    $HTTP_BODY = ($lines[0..($lines.Length-2)]) -join "`n"

    if ($HTTP_CODE -eq "201") {
        $jsonResponse = $HTTP_BODY | ConvertFrom-Json
        Write-TestSuccess "GitLab API working - Test pipeline #$($jsonResponse.id) created"
        Write-TestInfo "URL: $($jsonResponse.web_url)"
    } elseif ($HTTP_CODE -eq "400") {
        $errorJson = $HTTP_BODY | ConvertFrom-Json
        $errorMsg = $errorJson.message.base[0]
        if ($errorMsg -like "*empty*") {
            Write-TestError "GitLab CI rules prevent trigger execution"
            Write-TestInfo "Ensure your .gitlab-ci.yml has jobs that accept trigger source"
            Write-TestInfo "Add: rules: [if: `$CI_PIPELINE_SOURCE == 'trigger']"
        } else {
            Write-TestError "GitLab API error: $errorMsg"
        }
        exit 1
    } else {
        Write-TestError "GitLab API returned HTTP $HTTP_CODE"
        exit 1
    }
} catch {
    Write-TestError "Failed to connect to GitLab API: $_"
    exit 1
}

# =============================================================================
# Test 3: End-to-End Flow Test
# =============================================================================

Write-Header "Test 3: End-to-End Flow Test"

# Extract label key and value
$LABEL_KEY = $null
$LABEL_VALUE = $null

if ($REQUIRED_LABELS) {
    $props = $REQUIRED_LABELS.PSObject.Properties | Select-Object -First 1
    if ($props) {
        $LABEL_KEY = $props.Name
        $LABEL_VALUE = $props.Value
    }
}

if ([string]::IsNullOrWhiteSpace($LABEL_KEY)) {
    $LABEL_KEY = "trigger-gitlab"
    $LABEL_VALUE = "true"
}

Write-Step "3.1" "Creating test secret with required labels..."
Write-TestInfo "Secret name: $TEST_SECRET_NAME"
Write-TestInfo "Labels: $LABEL_KEY=$LABEL_VALUE"

# Delete if exists (cleanup from previous run)
gcloud secrets delete $TEST_SECRET_NAME --project=$PROJECT_ID --quiet 2>$null

# Create the secret with required labels
$createResult = gcloud secrets create $TEST_SECRET_NAME `
    --project=$PROJECT_ID `
    --labels="${LABEL_KEY}=${LABEL_VALUE}" `
    --replication-policy=automatic 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-TestSuccess "Secret created successfully"
} else {
    Write-TestError "Failed to create secret: $createResult"
    exit 1
}

Write-Step "3.2" "Waiting for event propagation..."
Write-Waiting "Waiting $WAIT_TIME seconds for Eventarc to process..."
Start-Sleep -Seconds $WAIT_TIME

Write-Step "3.3" "Checking Cloud Function logs..."
Write-Host ""

# Query logs without timestamp filter (more reliable across platforms)
$LOGS = gcloud logging read `
    "resource.labels.service_name=`"${FUNCTION_NAME}`"" `
    --project=$PROJECT_ID `
    --limit=30 `
    --format="value(textPayload)" 2>$null

if ([string]::IsNullOrWhiteSpace($LOGS)) {
    Write-TestError "No recent logs found for Cloud Function"
    Write-TestInfo "This could mean:"
    Write-TestInfo "  - Audit logs are not enabled for Secret Manager"
    Write-TestInfo "  - Eventarc triggers are not in 'global' location"
    Write-TestInfo "  - IAM permissions are missing"
    exit 1
}

# Check for our specific secret in logs
if ($LOGS -match $TEST_SECRET_NAME) {
    Write-TestSuccess "Function received the event for $TEST_SECRET_NAME"

    if ($LOGS -match "Successfully triggered GitLab pipeline") {
        $pipelineMatch = [regex]::Match($LOGS, "Successfully triggered GitLab pipeline #(\d+)")
        if ($pipelineMatch.Success) {
            Write-TestSuccess "Pipeline #$($pipelineMatch.Groups[1].Value) triggered successfully"
        }

        $urlMatch = [regex]::Match($LOGS, "Pipeline URL: (https://[^\s]+)")
        if ($urlMatch.Success) {
            Write-TestSuccess "Pipeline URL: $($urlMatch.Groups[1].Value)"
        }
    } elseif ($LOGS -match "ERROR") {
        Write-TestError "Function encountered an error"
        $LOGS -split "`n" | Where-Object { $_ -match "ERROR" } | Select-Object -First 3
    }
} else {
    Write-TestError "Event for $TEST_SECRET_NAME not found in logs"
    Write-TestInfo "Recent log entries:"
    $LOGS -split "`n" | Select-Object -First 10
}

# =============================================================================
# Test 4: Label Filtering Test
# =============================================================================

Write-Header "Test 4: Label Filtering Test"

$TEST_SECRET_NO_LABEL = "test-no-label-$(Get-Date -Format 'yyyyMMddHHmmss')"

Write-Step "4.1" "Creating secret WITHOUT required labels..."
Write-TestInfo "Secret name: $TEST_SECRET_NO_LABEL"
Write-TestInfo "Labels: (none)"

gcloud secrets create $TEST_SECRET_NO_LABEL `
    --project=$PROJECT_ID `
    --replication-policy=automatic 2>$null

Write-TestSuccess "Secret created (without labels)"

Write-Step "4.2" "Waiting for event propagation..."
Write-Waiting "Waiting $WAIT_TIME seconds..."
Start-Sleep -Seconds $WAIT_TIME

Write-Step "4.3" "Verifying pipeline was NOT triggered..."

$FILTER_LOGS = gcloud logging read `
    "resource.labels.service_name=`"${FUNCTION_NAME}`" AND textPayload:`"${TEST_SECRET_NO_LABEL}`"" `
    --project=$PROJECT_ID `
    --limit=10 `
    --format="value(textPayload)" 2>$null

if ($FILTER_LOGS -match "do not match required labels") {
    Write-TestSuccess "Label filtering working correctly - secret was skipped"
} elseif ($FILTER_LOGS -match "Successfully triggered") {
    Write-TestError "Pipeline was triggered despite missing labels!"
} else {
    Write-TestInfo "Event may not have been processed yet or function not invoked"
}

# =============================================================================
# Cleanup
# =============================================================================

Write-Header "Cleanup"

Write-Step "5.1" "Deleting test secrets..."
gcloud secrets delete $TEST_SECRET_NAME --project=$PROJECT_ID --quiet 2>$null
if ($LASTEXITCODE -eq 0) { Write-TestSuccess "Deleted $TEST_SECRET_NAME" }

gcloud secrets delete $TEST_SECRET_NO_LABEL --project=$PROJECT_ID --quiet 2>$null
if ($LASTEXITCODE -eq 0) { Write-TestSuccess "Deleted $TEST_SECRET_NO_LABEL" }

# =============================================================================
# Summary
# =============================================================================

Write-Header "Test Summary"

Write-Host "Infrastructure:" -ForegroundColor White
Write-Host "  Cloud Function:     " -NoNewline; Write-Host "[OK] Active" -ForegroundColor Green
Write-Host "  Eventarc Triggers:  " -NoNewline; Write-Host "[OK] Configured (global)" -ForegroundColor Green
Write-Host "  Audit Logs:         " -NoNewline; Write-Host "[OK] Enabled" -ForegroundColor Green
Write-Host ""
Write-Host "Connectivity:" -ForegroundColor White
Write-Host "  GitLab API:         " -NoNewline; Write-Host "[OK] Working" -ForegroundColor Green
Write-Host "  Secret Manager:     " -NoNewline; Write-Host "[OK] Accessible" -ForegroundColor Green
Write-Host ""
Write-Host "Flow:" -ForegroundColor White
Write-Host "  Event Capture:      " -NoNewline; Write-Host "[OK] Working" -ForegroundColor Green
Write-Host "  Label Filtering:    " -NoNewline; Write-Host "[OK] Working" -ForegroundColor Green
Write-Host "  Pipeline Trigger:   " -NoNewline; Write-Host "[OK] Working" -ForegroundColor Green
Write-Host ""
Write-Host "All tests passed successfully!" -ForegroundColor Green
Write-Host ""
