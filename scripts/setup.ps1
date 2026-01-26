# =============================================================================
# Setup Script for GCP Secret Manager to GitLab Trigger
# PowerShell version for Windows - With interactive menus
# =============================================================================

# Note: We don't use "Stop" because gcloud writes to stderr even on success
$ErrorActionPreference = "Continue"

# =============================================================================
# Interactive menu function with arrow keys
# =============================================================================
function Show-Menu {
    param(
        [string]$Title,
        [string[]]$Options,
        [string]$Message = "Use arrow keys to navigate, Enter to confirm"
    )

    $selectedIndex = 0
    $cursorTop = [Console]::CursorTop

    Write-Host ""
    Write-Host "  $Title" -ForegroundColor Yellow
    Write-Host "  $Message" -ForegroundColor Gray
    Write-Host ""

    $menuTop = [Console]::CursorTop

    while ($true) {
        [Console]::SetCursorPosition(0, $menuTop)

        for ($i = 0; $i -lt $Options.Count; $i++) {
            if ($i -eq $selectedIndex) {
                Write-Host "  > " -NoNewline -ForegroundColor Cyan
                Write-Host $Options[$i] -ForegroundColor Cyan -BackgroundColor DarkBlue
            } else {
                Write-Host "    $($Options[$i])                                        "
            }
        }

        $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

        switch ($key.VirtualKeyCode) {
            38 { # Up arrow
                if ($selectedIndex -gt 0) { $selectedIndex-- }
            }
            40 { # Down arrow
                if ($selectedIndex -lt $Options.Count - 1) { $selectedIndex++ }
            }
            13 { # Enter
                Write-Host ""
                return $selectedIndex
            }
        }
    }
}

# =============================================================================
# Input function with default value
# =============================================================================
function Read-HostWithDefault {
    param(
        [string]$Prompt,
        [string]$Default = ""
    )

    if ($Default) {
        $input = Read-Host "  $Prompt [$Default]"
        if ([string]::IsNullOrWhiteSpace($input)) { return $Default }
        return $input
    } else {
        return Read-Host "  $Prompt"
    }
}

# =============================================================================
# START OF SCRIPT
# =============================================================================

Clear-Host
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  GCP Secret Manager -> GitLab CI Trigger" -ForegroundColor Cyan
Write-Host "  Interactive Setup" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# -----------------------------------------------------------------------------
# Step 1: Verify gcloud CLI
# -----------------------------------------------------------------------------
Write-Host "[1/7] Verifying gcloud CLI..." -ForegroundColor Yellow

try {
    $gcloudVersion = gcloud version 2>&1 | Select-Object -First 1
    Write-Host "  OK: gcloud is installed" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: gcloud is not installed!" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Download: https://cloud.google.com/sdk/docs/install" -ForegroundColor Yellow
    exit 1
}

# -----------------------------------------------------------------------------
# Step 2: Authentication
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "[2/7] Google Cloud Authentication..." -ForegroundColor Yellow

$currentAccount = gcloud config get-value account 2>$null
if ($currentAccount -and $currentAccount -ne "(unset)") {
    Write-Host "  Current account: $currentAccount" -ForegroundColor White

    $authChoice = Show-Menu -Title "What would you like to do?" -Options @(
        "Continue with this account",
        "Login with a different account"
    )

    if ($authChoice -eq 1) {
        Write-Host "  Launching authentication..." -ForegroundColor White
        gcloud auth login --quiet 2>&1 | Out-Null
        gcloud auth application-default login --quiet 2>&1 | Out-Null
    }
} else {
    Write-Host "  No account logged in. Launching authentication..." -ForegroundColor White
    gcloud auth login 2>&1 | Out-Null
    gcloud auth application-default login 2>&1 | Out-Null
}
Write-Host "  OK: Authentication complete" -ForegroundColor Green

# -----------------------------------------------------------------------------
# Step 3: Project Selection/Creation
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "[3/7] GCP Project Configuration..." -ForegroundColor Yellow

# Get list of projects
$projectsRaw = gcloud projects list --format="value(projectId)" 2>$null
$projects = $projectsRaw -split "`n" | Where-Object { $_ -ne "" }

if ($projects.Count -gt 0) {
    $projectOptions = @($projects) + @("** Create a new project **")

    $projectChoice = Show-Menu -Title "Select a GCP project:" -Options $projectOptions

    if ($projectChoice -eq $projects.Count) {
        # Create a new project
        Write-Host ""
        $projectId = Read-HostWithDefault -Prompt "New project ID (e.g., my-test-project)"
        $projectName = Read-HostWithDefault -Prompt "Project name" -Default $projectId

        Write-Host "  Creating project $projectId..." -ForegroundColor White
        $null = gcloud projects create $projectId --name="$projectName" 2>&1
    } else {
        $projectId = $projects[$projectChoice]
    }
} else {
    Write-Host "  No projects found. Creating a new project..." -ForegroundColor White
    $projectId = Read-HostWithDefault -Prompt "New project ID"
    $null = gcloud projects create $projectId 2>&1
}

$null = gcloud config set project $projectId 2>&1
Write-Host "  OK: Project configured: $projectId" -ForegroundColor Green

# -----------------------------------------------------------------------------
# Step 4: Billing Account
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "[4/7] Billing Configuration..." -ForegroundColor Yellow

$billingInfo = gcloud billing projects describe $projectId --format="value(billingAccountName)" 2>$null
if ($billingInfo) {
    Write-Host "  OK: Billing already configured" -ForegroundColor Green
} else {
    # Get billing accounts
    $billingRaw = gcloud billing accounts list --format="value(name,displayName)" 2>$null
    $billingLines = $billingRaw -split "`n" | Where-Object { $_ -ne "" }

    if ($billingLines.Count -gt 0) {
        $billingOptions = @()
        $billingIds = @()

        foreach ($line in $billingLines) {
            $parts = $line -split "`t"
            $billingIds += $parts[0]
            $displayName = if ($parts.Count -gt 1) { $parts[1] } else { $parts[0] }
            $billingOptions += "$displayName ($($parts[0]))"
        }

        $billingChoice = Show-Menu -Title "Select a billing account:" -Options $billingOptions

        $selectedBilling = $billingIds[$billingChoice]
        Write-Host "  Linking billing account..." -ForegroundColor White
        $null = gcloud billing projects link $projectId --billing-account=$selectedBilling 2>&1
        Write-Host "  OK: Billing configured" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: No billing accounts found!" -ForegroundColor Red
        Write-Host "  Configure billing manually at:" -ForegroundColor Yellow
        Write-Host "  https://console.cloud.google.com/billing/linkedaccount?project=$projectId" -ForegroundColor Cyan
        Read-Host "  Press Enter to continue..."
    }
}

# -----------------------------------------------------------------------------
# Step 5: Enable APIs
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "[5/7] Enabling GCP APIs..." -ForegroundColor Yellow

$apis = @(
    "secretmanager.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "eventarc.googleapis.com",
    "run.googleapis.com",
    "logging.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "artifactregistry.googleapis.com"
)

foreach ($api in $apis) {
    Write-Host "  Enabling $api..." -ForegroundColor White -NoNewline
    $null = gcloud services enable $api --quiet 2>&1
    Write-Host " OK" -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# Step 6: Configure Cloud Audit Logs
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "[6/7] Cloud Audit Logs Configuration..." -ForegroundColor Yellow
Write-Host ""
Write-Host "  IMPORTANT: You must manually enable Audit Logs:" -ForegroundColor Red
Write-Host ""
Write-Host "  1. Open this link:" -ForegroundColor White
Write-Host "     https://console.cloud.google.com/iam-admin/audit?project=$projectId" -ForegroundColor Cyan
Write-Host ""
Write-Host "  2. Find 'Secret Manager API' in the list" -ForegroundColor White
Write-Host "  3. Check 'Admin Read' and 'Data Write'" -ForegroundColor White
Write-Host "  4. Click 'Save'" -ForegroundColor White
Write-Host ""

# Open browser automatically
$openBrowser = Show-Menu -Title "Open the link in browser?" -Options @(
    "Yes, open now",
    "No, I'll do it later"
)

if ($openBrowser -eq 0) {
    Start-Process "https://console.cloud.google.com/iam-admin/audit?project=$projectId"
}

Read-Host "  Press Enter when done..."

# -----------------------------------------------------------------------------
# Step 7: GitLab Configuration
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "[7/7] GitLab Configuration..." -ForegroundColor Yellow

# GitLab URL
$gitlabUrlChoice = Show-Menu -Title "GitLab instance:" -Options @(
    "gitlab.com (SaaS)",
    "GitLab self-hosted (custom URL)"
)

if ($gitlabUrlChoice -eq 0) {
    $gitlabUrl = "https://gitlab.com"
} else {
    $gitlabUrl = Read-HostWithDefault -Prompt "Your GitLab URL (e.g., https://gitlab.company.com)"
}

# GitLab Project ID
Write-Host ""
Write-Host "  The GitLab Project ID can be found at:" -ForegroundColor Gray
Write-Host "  Settings > General > at the top of the page" -ForegroundColor Gray
$gitlabProjectId = Read-HostWithDefault -Prompt "GitLab Project ID (e.g., 12345678)"

# GitLab Trigger Token
Write-Host ""
Write-Host "  The Pipeline Trigger Token can be found at:" -ForegroundColor Gray
Write-Host "  Settings > CI/CD > Pipeline trigger tokens" -ForegroundColor Gray
$gitlabTriggerToken = Read-HostWithDefault -Prompt "Pipeline Trigger Token (glptt-...)"

# Branch
$refChoice = Show-Menu -Title "Branch to trigger:" -Options @(
    "main",
    "master",
    "develop",
    "Other branch..."
)

switch ($refChoice) {
    0 { $gitlabRef = "main" }
    1 { $gitlabRef = "master" }
    2 { $gitlabRef = "develop" }
    3 { $gitlabRef = Read-HostWithDefault -Prompt "Branch name" }
}

# GCP Region
Write-Host ""
$regionChoice = Show-Menu -Title "GCP Region:" -Options @(
    "europe-west1 (Belgium)",
    "europe-west9 (Paris)",
    "us-central1 (Iowa)",
    "us-east1 (South Carolina)",
    "Other region..."
)

switch ($regionChoice) {
    0 { $region = "europe-west1" }
    1 { $region = "europe-west9" }
    2 { $region = "us-central1" }
    3 { $region = "us-east1" }
    4 { $region = Read-HostWithDefault -Prompt "Region code (e.g., asia-east1)" }
}

# Labels
Write-Host ""
Write-Host "  Label filtering configuration:" -ForegroundColor Yellow
Write-Host "  Only secrets with this label will trigger the pipeline" -ForegroundColor Gray
$labelKey = Read-HostWithDefault -Prompt "Label key" -Default "trigger-gitlab"
$labelValue = Read-HostWithDefault -Prompt "Label value" -Default "true"

# -----------------------------------------------------------------------------
# Generate terraform.tfvars file
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "  Generating terraform.tfvars..." -ForegroundColor White

$tfvarsPath = Join-Path $PSScriptRoot "..\terraform.tfvars"
$tfvarsContent = @"
# =============================================================================
# Configuration automatically generated by setup.ps1
# Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# =============================================================================

# GCP
project_id = "$projectId"
region     = "$region"

# GitLab
gitlab_url           = "$gitlabUrl"
gitlab_project_id    = "$gitlabProjectId"
gitlab_trigger_token = "$gitlabTriggerToken"
gitlab_ref           = "$gitlabRef"

# Label filtering
required_labels = {
  "$labelKey" = "$labelValue"
}

# Events
trigger_on_create = true
trigger_on_update = true
trigger_on_delete = false
"@

$tfvarsContent | Out-File -FilePath $tfvarsPath -Encoding UTF8
Write-Host "  OK: terraform.tfvars generated" -ForegroundColor Green

# -----------------------------------------------------------------------------
# Summary and next steps
# -----------------------------------------------------------------------------
Clear-Host
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Setup completed successfully!" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Configuration:" -ForegroundColor Yellow
Write-Host "  -------------" -ForegroundColor Yellow
Write-Host "    GCP Project:     $projectId" -ForegroundColor White
Write-Host "    Region:         $region" -ForegroundColor White
Write-Host "    GitLab URL:     $gitlabUrl" -ForegroundColor White
Write-Host "    GitLab Project:  $gitlabProjectId" -ForegroundColor White
Write-Host "    Branch:        $gitlabRef" -ForegroundColor White
Write-Host "    Label filter:   $labelKey=$labelValue" -ForegroundColor White
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Yellow
Write-Host "  ------------------" -ForegroundColor Yellow
Write-Host "    1. terraform init" -ForegroundColor Cyan
Write-Host "    2. terraform plan" -ForegroundColor Cyan
Write-Host "    3. terraform apply" -ForegroundColor Cyan
Write-Host ""
Write-Host "  After deployment, test with:" -ForegroundColor Yellow
Write-Host "    .\scripts\test.ps1" -ForegroundColor Cyan
Write-Host ""

# Offer to run terraform init
$initChoice = Show-Menu -Title "Run 'terraform init' now?" -Options @(
    "Yes",
    "No, I'll do it manually"
)

if ($initChoice -eq 0) {
    Write-Host ""
    Write-Host "  Running terraform init..." -ForegroundColor Yellow
    Set-Location (Join-Path $PSScriptRoot "..")
    terraform init
}

Write-Host ""
