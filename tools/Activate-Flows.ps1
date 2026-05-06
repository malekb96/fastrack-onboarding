# Activate-Flows.ps1
# Lance ce script pour appliquer les fixes finaux + activer les flows.
# Tu auras un device code à saisir une seule fois.
#
# Usage:
#   .\tools\Activate-Flows.ps1

$ErrorActionPreference = "Stop"

$tenantId = "ae481188-942a-44a5-9019-ae83fc025ac3"
$clientId = "04b07795-8ddb-461a-bbee-02f9e1bf7b46"  # Azure CLI public client
$orgUrl   = "https://orgebcd0239.crm3.dynamics.com"
$base     = "$orgUrl/api/data/v9.2"

# === Device code auth ===
$dcResp = Invoke-RestMethod -Method Post `
    -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/devicecode" `
    -Body @{ client_id=$clientId; scope="$orgUrl/.default offline_access" }

Write-Host ""
Write-Host "==========================================================="
Write-Host "  AUTHENTIFIE-TOI MAINTENANT :"
Write-Host ""
Write-Host "  URL  : $($dcResp.verification_uri)"
Write-Host "  CODE : $($dcResp.user_code)"
Write-Host ""
Write-Host "  Expire dans 15 min — fais-le tout de suite."
Write-Host "==========================================================="
Write-Host ""

$expiry   = (Get-Date).AddSeconds($dcResp.expires_in)
$interval = [Math]::Max([int]$dcResp.interval, 5)
$tok = $null

while ((Get-Date) -lt $expiry) {
    Start-Sleep -Seconds $interval
    try {
        $r = Invoke-RestMethod -Method Post `
            -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" `
            -Body @{
                grant_type  = "urn:ietf:params:oauth:grant-type:device_code"
                client_id   = $clientId
                device_code = $dcResp.device_code
            } -ErrorAction Stop
        $tok = $r.access_token
        Write-Host "Token obtenu" -ForegroundColor Green
        break
    } catch {
        $e = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($e.error -eq "authorization_pending") { continue }
        if ($e.error -eq "slow_down") { $interval += 5; continue }
        Write-Host "Erreur: $($e.error) - $($e.error_description)" -ForegroundColor Red
        exit 1
    }
}
if (-not $tok) { Write-Host "Code expiré sans authentification" -ForegroundColor Red; exit 1 }

$h = @{
    Authorization     = "Bearer $tok"
    "Content-Type"    = "application/json"
    "OData-MaxVersion"= "4.0"
    "OData-Version"   = "4.0"
}

# === Découverte automatique des flows à fixer ===
$malekId = "845c68dc-49f7-f011-8406-7ced8d052d35"
$allFlows = (Invoke-RestMethod -Method Get `
    -Uri "$base/workflows?`$filter=category eq 5 and _ownerid_value eq '$malekId'&`$select=workflowid,name,statecode" `
    -Headers $h).value

Write-Host ""
Write-Host "=== Flows appartenant à Malek ==="
$allFlows | ForEach-Object { Write-Host "  $($_.workflowid) | $($_.name)" }

# === Connection references ===
$dvRef   = "msdyn_Dataverse"
$o365Ref = "new_shared_office365"

foreach ($flow in $allFlows) {
    Write-Host ""
    Write-Host "--- $($flow.name) ---" -ForegroundColor Cyan

    $wf = Invoke-RestMethod -Method Get -Uri "$base/workflows($($flow.workflowid))?`$select=clientdata" -Headers $h
    $cd = $wf.clientdata | ConvertFrom-Json

    # Fix 1: GetRecord → GetItem (string-level replacement)
    $cdJson = $cd | ConvertTo-Json -Depth 30
    $cdJson = $cdJson -replace '"operationId":\s*"GetRecord"', '"operationId": "GetItem"'
    $cd = $cdJson | ConvertFrom-Json

    # Fix 2: Connection references → connectionReferenceLogicalName
    foreach ($key in @("shared_commondataserviceforapps", "shared_office365", "shared_aibuilder")) {
        if ($cd.properties.connectionReferences.PSObject.Properties[$key]) {
            $refName = switch ($key) {
                "shared_commondataserviceforapps" { $dvRef }
                "shared_office365"                { $o365Ref }
                "shared_aibuilder"                { $null }
            }
            if ($refName) {
                $cd.properties.connectionReferences.$key.connection = [PSCustomObject]@{
                    connectionReferenceLogicalName = $refName
                }
                Write-Host "  $key → $refName"
            }
        }
    }

    $newCd = @{ schemaVersion="1.0.0.0"; properties=$cd.properties } | ConvertTo-Json -Depth 30 -Compress

    # Update définition
    try {
        Invoke-RestMethod -Method Patch -Uri "$base/workflows($($flow.workflowid))" -Headers $h `
            -Body (@{ clientdata=$newCd } | ConvertTo-Json -Depth 5) | Out-Null
        Write-Host "  Définition mise à jour" -ForegroundColor Green
    } catch {
        $msg = ($_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue).error.message
        Write-Host "  Erreur définition: $msg" -ForegroundColor Red
        continue
    }

    # Activation
    try {
        Invoke-RestMethod -Method Patch -Uri "$base/workflows($($flow.workflowid))" -Headers $h `
            -Body (@{ statecode=1; statuscode=2 } | ConvertTo-Json) | Out-Null
        Write-Host "  ★ ACTIVÉ" -ForegroundColor Green
    } catch {
        $msg = ($_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue).error.message
        Write-Host "  Activation: $msg" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=== ÉTAT FINAL ===" -ForegroundColor Cyan
(Invoke-RestMethod -Method Get `
    -Uri "$base/workflows?`$filter=category eq 5 and _ownerid_value eq '$malekId'&`$select=name,statecode" `
    -Headers $h).value | ForEach-Object {
    $s = switch($_.statecode) { 0{"Draft"} 1{"★ ACTIVÉ"} default{"?"} }
    Write-Host "$($_.name) → $s"
}
