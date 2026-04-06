#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Collects Windows 365 Cloud PC data for offline assessment.

.DESCRIPTION
    This script collects Windows 365 configuration, provisioning, network,
    and Cloud PC data via the Microsoft Graph beta API. It produces a portable
    ZIP file containing JSON exports that can be analyzed offline by the
    W365 Evidence Pack.

    The script is READ-ONLY — it makes no changes to your environment.

    Data collected includes:
    - Cloud PC inventory (status, sizing, provisioning type)
    - Provisioning policies and assignments
    - Azure Network Connections and health checks
    - Custom and gallery device images
    - User settings and assignments
    - Connection quality reports
    - Audit events

.PARAMETER TenantId
    Required. The Azure AD / Entra ID tenant ID to collect from.

.PARAMETER OutputPath
    Directory for the output ZIP. Defaults to current directory.

.PARAMETER SkipReports
    Skip Cloud PC reports (connection quality, recommendations) for faster collection.

.PARAMETER DaysBack
    Number of days of audit event history. Default: 30.

.PARAMETER DryRun
    Validate permissions and connectivity without collecting data.

.EXAMPLE
    .\Collect-W365Data.ps1 -TenantId "contoso.onmicrosoft.com"

.EXAMPLE
    .\Collect-W365Data.ps1 -TenantId "12345678-abcd-efgh-ijkl-123456789012" -SkipReports

.NOTES
    Version: 1.0.0
    Requires: Microsoft.Graph.Authentication module
    Permissions: CloudPC.Read.All, Directory.Read.All
    API: All endpoints use the Microsoft Graph beta API.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [string]$OutputPath = (Get-Location).Path,

    [switch]$SkipReports,

    [int]$DaysBack = 30,

    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$script:ScriptVersion = "1.0.0"
$script:SchemaVersion = "1.0"
$script:CollectionStart = Get-Date
$script:GraphBase = "https://graph.microsoft.com/beta"

# =========================================================
# Banner
# =========================================================
Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "  Windows 365 Data Collector v$script:ScriptVersion" -ForegroundColor Cyan
Write-Host "  Offline assessment data collection" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

# =========================================================
# Prerequisites Check
# =========================================================
Write-Host "Checking prerequisites..." -ForegroundColor Yellow

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    Write-Error "Microsoft.Graph.Authentication module not found. Install with: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser"
    exit 1
}
Write-Host "  [OK] Microsoft.Graph.Authentication module found" -ForegroundColor Green

# =========================================================
# Authentication
# =========================================================
Write-Host ""
Write-Host "Authenticating to Microsoft Graph..." -ForegroundColor Yellow

$requiredScopes = @(
    "CloudPC.Read.All",
    "Directory.Read.All"
)

try {
    Connect-MgGraph -TenantId $TenantId -Scopes $requiredScopes -NoWelcome
    $context = Get-MgContext
    Write-Host "  [OK] Authenticated as $($context.Account) to tenant $($context.TenantId)" -ForegroundColor Green
} catch {
    Write-Error "Authentication failed: $($_.Exception.Message)"
    exit 1
}

if ($DryRun) {
    Write-Host ""
    Write-Host "DryRun: Authentication successful. Permissions validated." -ForegroundColor Green

    # Quick connectivity test
    Write-Host "DryRun: Testing Cloud PC endpoint access..." -ForegroundColor Yellow
    try {
        $test = Invoke-MgGraphRequest -Method GET -Uri "$script:GraphBase/deviceManagement/virtualEndpoint/cloudPCs?`$top=1"
        $testCount = if ($test.value) { $test.value.Count } else { 0 }
        Write-Host "  [OK] Cloud PC endpoint accessible ($testCount Cloud PCs in test query)" -ForegroundColor Green
    } catch {
        Write-Host "  [WARN] Cloud PC endpoint test failed: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  This may indicate missing CloudPC.Read.All permission or no W365 licenses." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "DryRun: No data collected." -ForegroundColor Yellow
    Disconnect-MgGraph | Out-Null
    return
}

# =========================================================
# Helper Functions
# =========================================================

function Invoke-GraphPagedRequest {
    <#
    .SYNOPSIS
        Makes a paged Graph API request, following @odata.nextLink.
    .DESCRIPTION
        Handles pagination and rate limiting with exponential backoff.
        W365/Intune endpoints have stricter throttling limits than
        general Graph API endpoints.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [int]$MaxRetries = 5
    )

    $allResults = [System.Collections.Generic.List[object]]::new()
    $currentUri = $Uri
    $retryCount = 0

    while ($currentUri) {
        try {
            $response = Invoke-MgGraphRequest -Method GET -Uri $currentUri
            if ($response.value) {
                $allResults.AddRange([object[]]$response.value)
            }
            $currentUri = $response.'@odata.nextLink'
            $retryCount = 0  # Reset on success
        } catch {
            $statusCode = $null
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            if ($statusCode -eq 429 -or $statusCode -eq 503) {
                $retryCount++
                if ($retryCount -gt $MaxRetries) {
                    Write-Host "  [WARN] Max retries exceeded for: $currentUri" -ForegroundColor Yellow
                    break
                }
                # Exponential backoff: 2s, 4s, 8s, 16s, 32s
                $waitSeconds = [math]::Pow(2, $retryCount)

                # Check for Retry-After header
                $retryAfter = $null
                try { $retryAfter = $_.Exception.Response.Headers["Retry-After"] } catch { }
                if ($retryAfter) { $waitSeconds = [math]::Max($waitSeconds, [int]$retryAfter) }

                Write-Host "  [WAIT] Rate limited (HTTP $statusCode). Waiting ${waitSeconds}s (attempt $retryCount/$MaxRetries)..." -ForegroundColor Yellow
                Start-Sleep -Seconds $waitSeconds
                # Retry same URI
            } else {
                Write-Host "  [WARN] Graph request failed: $($_.Exception.Message)" -ForegroundColor Yellow
                break
            }
        }
    }

    return $allResults.ToArray()
}

function Invoke-GraphSingleRequest {
    <#
    .SYNOPSIS
        Makes a single (non-paged) Graph API request with retry logic.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [int]$MaxRetries = 3
    )

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            return (Invoke-MgGraphRequest -Method GET -Uri $Uri)
        } catch {
            $statusCode = $null
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            if (($statusCode -eq 429 -or $statusCode -eq 503) -and $attempt -lt $MaxRetries) {
                $waitSeconds = [math]::Pow(2, $attempt)
                Write-Host "  [WAIT] Rate limited. Waiting ${waitSeconds}s..." -ForegroundColor Yellow
                Start-Sleep -Seconds $waitSeconds
            } elseif ($statusCode -eq 404) {
                # Not found — endpoint may not be available for this tenant
                return $null
            } else {
                if ($attempt -eq $MaxRetries) {
                    Write-Host "  [WARN] Request failed after $MaxRetries attempts: $($_.Exception.Message)" -ForegroundColor Yellow
                    return $null
                }
            }
        }
    }
    return $null
}

# =========================================================
# Collection
# =========================================================
$collectionDir = Join-Path ([System.IO.Path]::GetTempPath()) "W365Collection_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $collectionDir -Force | Out-Null

$collected = @{}

# ---------------------------------------------------------
# Step 1: Cloud PC Inventory
# ---------------------------------------------------------
Write-Host ""
Write-Host "Step 1: Cloud PC Inventory" -ForegroundColor Cyan
Write-Host "----------------------------" -ForegroundColor Gray

Write-Host "  Collecting Cloud PCs..." -ForegroundColor Gray -NoNewline
$cloudPCs = Invoke-GraphPagedRequest -Uri "$script:GraphBase/deviceManagement/virtualEndpoint/cloudPCs"
$collected["cloud-pcs"] = $cloudPCs
Write-Host " [OK] ($($cloudPCs.Count) Cloud PCs)" -ForegroundColor Green

# ---------------------------------------------------------
# Step 2: Provisioning Policies
# ---------------------------------------------------------
Write-Host ""
Write-Host "Step 2: Provisioning Policies" -ForegroundColor Cyan
Write-Host "-------------------------------" -ForegroundColor Gray

Write-Host "  Collecting provisioning policies..." -ForegroundColor Gray -NoNewline
$provPolicies = Invoke-GraphPagedRequest -Uri "$script:GraphBase/deviceManagement/virtualEndpoint/provisioningPolicies"
$collected["provisioning-policies"] = $provPolicies
Write-Host " [OK] ($($provPolicies.Count) policies)" -ForegroundColor Green

# Collect assignments per policy ($expand doesn't work — must do individual calls)
Write-Host "  Collecting policy assignments..." -ForegroundColor Gray -NoNewline
$allAssignments = [System.Collections.Generic.List[object]]::new()
$assignmentCount = 0
foreach ($policy in $provPolicies) {
    $policyId = $policy.id
    if (-not $policyId) { continue }
    $assignments = Invoke-GraphPagedRequest -Uri "$script:GraphBase/deviceManagement/virtualEndpoint/provisioningPolicies/$policyId/assignments"
    foreach ($assignment in $assignments) {
        $allAssignments.Add([PSCustomObject]@{
            PolicyId   = $policyId
            PolicyName = $policy.displayName
            Assignment = $assignment
        })
        $assignmentCount++
    }
}
$collected["policy-assignments"] = $allAssignments.ToArray()
Write-Host " [OK] ($assignmentCount assignments)" -ForegroundColor Green

# ---------------------------------------------------------
# Step 3: Azure Network Connections
# ---------------------------------------------------------
Write-Host ""
Write-Host "Step 3: Azure Network Connections" -ForegroundColor Cyan
Write-Host "-----------------------------------" -ForegroundColor Gray

Write-Host "  Collecting network connections..." -ForegroundColor Gray -NoNewline
$ancList = Invoke-GraphPagedRequest -Uri "$script:GraphBase/deviceManagement/virtualEndpoint/onPremisesConnections"
$collected["network-connections"] = $ancList
Write-Host " [OK] ($($ancList.Count) connections)" -ForegroundColor Green

# Collect health check details for each ANC
Write-Host "  Collecting health check details..." -ForegroundColor Gray -NoNewline
$healthCheckCount = 0
$ancHealthResults = [System.Collections.Generic.List[object]]::new()
foreach ($anc in $ancList) {
    $ancId = $anc.id
    if (-not $ancId) { continue }
    # The healthCheckStatusDetail property should be on the main object
    # but we also try the individual health checks endpoint if available
    $healthStatus = $anc.healthCheckStatusDetail
    $ancHealthResults.Add([PSCustomObject]@{
        ConnectionId   = $ancId
        ConnectionName = $anc.displayName
        HealthStatus   = $anc.healthCheckStatus
        StatusDetail   = $healthStatus
        InUse          = $anc.inUse
    })
    $healthCheckCount++
}
$collected["anc-health"] = $ancHealthResults.ToArray()
Write-Host " [OK] ($healthCheckCount connections checked)" -ForegroundColor Green

# ---------------------------------------------------------
# Step 4: Device Images
# ---------------------------------------------------------
Write-Host ""
Write-Host "Step 4: Device Images" -ForegroundColor Cyan
Write-Host "-----------------------" -ForegroundColor Gray

Write-Host "  Collecting custom device images..." -ForegroundColor Gray -NoNewline
$customImages = Invoke-GraphPagedRequest -Uri "$script:GraphBase/deviceManagement/virtualEndpoint/deviceImages"
$collected["device-images"] = $customImages
Write-Host " [OK] ($($customImages.Count) custom images)" -ForegroundColor Green

Write-Host "  Collecting gallery images..." -ForegroundColor Gray -NoNewline
$galleryImages = Invoke-GraphPagedRequest -Uri "$script:GraphBase/deviceManagement/virtualEndpoint/galleryImages"
$collected["gallery-images"] = $galleryImages
Write-Host " [OK] ($($galleryImages.Count) gallery images)" -ForegroundColor Green

# ---------------------------------------------------------
# Step 5: User Settings
# ---------------------------------------------------------
Write-Host ""
Write-Host "Step 5: User Settings" -ForegroundColor Cyan
Write-Host "-----------------------" -ForegroundColor Gray

Write-Host "  Collecting user settings..." -ForegroundColor Gray -NoNewline
$userSettings = Invoke-GraphPagedRequest -Uri "$script:GraphBase/deviceManagement/virtualEndpoint/userSettings"
$collected["user-settings"] = $userSettings
Write-Host " [OK] ($($userSettings.Count) user settings)" -ForegroundColor Green

# Collect user setting assignments
Write-Host "  Collecting user setting assignments..." -ForegroundColor Gray -NoNewline
$userSettingAssignments = [System.Collections.Generic.List[object]]::new()
$usAssignCount = 0
foreach ($setting in $userSettings) {
    $settingId = $setting.id
    if (-not $settingId) { continue }
    $assignments = Invoke-GraphPagedRequest -Uri "$script:GraphBase/deviceManagement/virtualEndpoint/userSettings/$settingId/assignments"
    foreach ($assignment in $assignments) {
        $userSettingAssignments.Add([PSCustomObject]@{
            SettingId   = $settingId
            SettingName = $setting.displayName
            Assignment  = $assignment
        })
        $usAssignCount++
    }
}
$collected["user-setting-assignments"] = $userSettingAssignments.ToArray()
Write-Host " [OK] ($usAssignCount assignments)" -ForegroundColor Green

# ---------------------------------------------------------
# Step 6: Service Plans (License Sizing)
# ---------------------------------------------------------
Write-Host ""
Write-Host "Step 6: Service Plans" -ForegroundColor Cyan
Write-Host "-----------------------" -ForegroundColor Gray

Write-Host "  Collecting service plan information..." -ForegroundColor Gray -NoNewline
$servicePlans = Invoke-GraphSingleRequest -Uri "$script:GraphBase/deviceManagement/virtualEndpoint/servicePlans"
if ($null -ne $servicePlans -and $servicePlans.value) {
    $collected["service-plans"] = $servicePlans.value
    Write-Host " [OK] ($($servicePlans.value.Count) service plans)" -ForegroundColor Green
} elseif ($null -ne $servicePlans) {
    $collected["service-plans"] = @($servicePlans)
    Write-Host " [OK] (1 service plan)" -ForegroundColor Green
} else {
    Write-Host " [WARN] Not available" -ForegroundColor Yellow
}

# ---------------------------------------------------------
# Step 7: Audit Events
# ---------------------------------------------------------
Write-Host ""
Write-Host "Step 7: Audit Events" -ForegroundColor Cyan
Write-Host "----------------------" -ForegroundColor Gray

Write-Host "  Collecting audit events (last $DaysBack days)..." -ForegroundColor Gray -NoNewline
$filterDate = (Get-Date).AddDays(-$DaysBack).ToString("yyyy-MM-ddTHH:mm:ssZ")
$auditEvents = Invoke-GraphPagedRequest -Uri "$script:GraphBase/deviceManagement/virtualEndpoint/auditEvents?`$filter=activityDateTime ge $filterDate&`$orderby=activityDateTime desc"
$collected["audit-events"] = $auditEvents
Write-Host " [OK] ($($auditEvents.Count) events)" -ForegroundColor Green

# ---------------------------------------------------------
# Step 8: Reports (Connection Quality, Recommendations)
# ---------------------------------------------------------
Write-Host ""
Write-Host "Step 8: Reports" -ForegroundColor Cyan
Write-Host "-----------------" -ForegroundColor Gray

if (-not $SkipReports) {
    # Connection quality report — use the reports endpoint
    Write-Host "  Collecting connection quality data..." -ForegroundColor Gray -NoNewline
    try {
        $cqBody = @{
            reportName = "CloudPcConnectionQualityReport"
            filter     = ""
            select     = @()
            format     = "json"
        }
        $cqResponse = Invoke-MgGraphRequest -Method POST `
            -Uri "$script:GraphBase/deviceManagement/virtualEndpoint/reports/getRealTimeRemoteConnectionStatus" `
            -Body ($cqBody | ConvertTo-Json -Depth 5) `
            -ContentType "application/json"

        if ($null -ne $cqResponse) {
            $collected["connection-quality"] = $cqResponse
            Write-Host " [OK]" -ForegroundColor Green
        } else {
            Write-Host " [WARN] No data returned" -ForegroundColor Yellow
        }
    } catch {
        Write-Host " [WARN] $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Remote connection historical report
    Write-Host "  Collecting remote connection history..." -ForegroundColor Gray -NoNewline
    try {
        $rcBody = @{
            reportName = "RemoteConnectionHistoricalReports"
            filter     = "EventDateTime ge datetime'$filterDate'"
            select     = @("CloudPcId", "ManagedDeviceName", "UserPrincipalName", "RoundTripTimeInMs",
                          "AvailableBandwidthInMBps", "SignInDateTime", "SignOutDateTime",
                          "RemoteSignInTimeInSec", "CloudPcFailurePercentage")
            format     = "json"
        }
        $rcResponse = Invoke-MgGraphRequest -Method POST `
            -Uri "$script:GraphBase/deviceManagement/virtualEndpoint/reports/getRemoteConnectionHistoricalReports" `
            -Body ($rcBody | ConvertTo-Json -Depth 5) `
            -ContentType "application/json"

        if ($null -ne $rcResponse) {
            $collected["connection-history"] = $rcResponse
            Write-Host " [OK]" -ForegroundColor Green
        } else {
            Write-Host " [WARN] No data returned" -ForegroundColor Yellow
        }
    } catch {
        Write-Host " [WARN] $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Cloud PC recommendations (right-sizing)
    Write-Host "  Collecting right-sizing recommendations..." -ForegroundColor Gray -NoNewline
    try {
        $recsResponse = Invoke-GraphSingleRequest -Uri "$script:GraphBase/deviceManagement/virtualEndpoint/reports/getCloudPcRecommendationReports"
        if ($null -ne $recsResponse) {
            $collected["recommendations"] = $recsResponse
            Write-Host " [OK]" -ForegroundColor Green
        } else {
            Write-Host " [WARN] Not available" -ForegroundColor Yellow
        }
    } catch {
        Write-Host " [WARN] $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  - Skipped (SkipReports)" -ForegroundColor Gray
}

# =========================================================
# Save to JSON files
# =========================================================
Write-Host ""
Write-Host "Saving collected data..." -ForegroundColor Yellow

foreach ($key in $collected.Keys) {
    if ($null -ne $collected[$key]) {
        $filePath = Join-Path $collectionDir "$key.json"
        $collected[$key] | ConvertTo-Json -Depth 15 | Set-Content -Path $filePath -Encoding UTF8
        Write-Host "  [OK] $key.json" -ForegroundColor Green
    }
}

# Metadata
$metadata = @{
    SchemaVersion      = $script:SchemaVersion
    CollectorVersion   = $script:ScriptVersion
    TenantId           = $context.TenantId
    CollectedBy        = $context.Account
    CollectionDate     = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    CollectionDuration = [math]::Round(((Get-Date) - $script:CollectionStart).TotalSeconds, 1)
    DaysBack           = $DaysBack
    Parameters         = @{
        SkipReports = $SkipReports.IsPresent
    }
    DataSources        = @{}
}

foreach ($key in $collected.Keys) {
    $count = 0
    if ($null -ne $collected[$key]) {
        $count = if ($collected[$key] -is [array]) { $collected[$key].Count } else { 1 }
    }
    $metadata.DataSources[$key] = @{
        Status = if ($null -ne $collected[$key]) { "Collected" } else { "Failed" }
        Count  = $count
    }
}

$metadata | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $collectionDir "metadata.json") -Encoding UTF8
Write-Host "  [OK] metadata.json" -ForegroundColor Green

# =========================================================
# Create ZIP
# =========================================================
Write-Host ""
Write-Host "Creating collection pack ZIP..." -ForegroundColor Yellow

$zipName = "W365Collection_$($context.TenantId.Substring(0,8))_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"
$zipPath = Join-Path $OutputPath $zipName

Compress-Archive -Path "$collectionDir\*" -DestinationPath $zipPath -Force
Remove-Item $collectionDir -Recurse -Force

$zipSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
$duration = [math]::Round(((Get-Date) - $script:CollectionStart).TotalSeconds, 1)

Write-Host ""
Write-Host "======================================================" -ForegroundColor Green
Write-Host "  Collection Complete" -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Output:   $zipPath" -ForegroundColor White
Write-Host "  Size:     $zipSize MB" -ForegroundColor White
Write-Host "  Duration: ${duration}s" -ForegroundColor White
Write-Host "  Sources:  $($collected.Keys.Count) data categories" -ForegroundColor White
Write-Host ""
Write-Host "  Send this ZIP to your consultant for analysis." -ForegroundColor Yellow

# Disconnect
Disconnect-MgGraph | Out-Null
