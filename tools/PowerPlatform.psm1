# PowerPlatform.psm1 — Shared helpers for Dataverse API operations
# Usage: Import-Module .\tools\PowerPlatform.psm1

$script:ClientId     = if ($env:PP_CLIENT_ID)     { $env:PP_CLIENT_ID }     else { "506c2f0b-4f76-4324-9c34-31065135a2ab" }
$script:ClientSecret = if ($env:PP_CLIENT_SECRET) { $env:PP_CLIENT_SECRET } else { "" }
$script:TenantId     = if ($env:PP_TENANT_ID)     { $env:PP_TENANT_ID }     else { "ae481188-942a-44a5-9019-ae83fc025ac3" }
$script:OrgUrl       = if ($env:PP_ORG_URL)       { $env:PP_ORG_URL }       else { "https://orgebcd0239.crm3.dynamics.com" }
$script:SolutionName = "FastTrackOnboarding"
$script:Base         = "$script:OrgUrl/api/data/v9.2"

# ── Auth ──────────────────────────────────────────────────────────────────────

function Get-DvToken {
    $body = @{ grant_type="client_credentials"; client_id=$script:ClientId; client_secret=$script:ClientSecret; scope="$script:OrgUrl/.default" }
    $r = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$script:TenantId/oauth2/v2.0/token" -Body $body
    return $r.access_token
}
Export-ModuleMember -Function Get-DvToken

function Get-DvHeaders {
    $tok = Get-DvToken
    return @{ Authorization="Bearer $tok"; "OData-MaxVersion"="4.0"; "OData-Version"="4.0"; Accept="application/json"; "Content-Type"="application/json" }
}
Export-ModuleMember -Function Get-DvHeaders

# ── Label helpers ──────────────────────────────────────────────────────────────

function New-Lbl($text) {
    return @{ "@odata.type"="Microsoft.Dynamics.CRM.Label"; LocalizedLabels=@(@{ "@odata.type"="Microsoft.Dynamics.CRM.LocalizedLabel"; Label=$text; LanguageCode=1033 }) }
}

# ── Column builders ────────────────────────────────────────────────────────────

function New-PrimaryAttr($schema, $display, $maxLen=250) {
    @{ "@odata.type"="Microsoft.Dynamics.CRM.StringAttributeMetadata"; SchemaName=$schema; DisplayName=(New-Lbl $display); MaxLength=$maxLen; RequiredLevel=@{Value="ApplicationRequired"}; IsPrimaryName=$true }
}
Export-ModuleMember -Function New-PrimaryAttr

function New-StrAttr($schema, $display, $maxLen=100) {
    @{ "@odata.type"="Microsoft.Dynamics.CRM.StringAttributeMetadata"; SchemaName=$schema; DisplayName=(New-Lbl $display); MaxLength=$maxLen; RequiredLevel=@{Value="None"} }
}
Export-ModuleMember -Function New-StrAttr

function New-MemoAttr($schema, $display) {
    @{ "@odata.type"="Microsoft.Dynamics.CRM.MemoAttributeMetadata"; SchemaName=$schema; DisplayName=(New-Lbl $display); MaxLength=1048576; RequiredLevel=@{Value="None"} }
}
Export-ModuleMember -Function New-MemoAttr

function New-DecAttr($schema, $display, $min=0, $max=1, $precision=4) {
    @{ "@odata.type"="Microsoft.Dynamics.CRM.DecimalAttributeMetadata"; SchemaName=$schema; DisplayName=(New-Lbl $display); MinValue=$min; MaxValue=$max; Precision=$precision; RequiredLevel=@{Value="None"} }
}
Export-ModuleMember -Function New-DecAttr

function New-IntAttr($schema, $display, $min=0, $max=2147483647) {
    @{ "@odata.type"="Microsoft.Dynamics.CRM.IntegerAttributeMetadata"; SchemaName=$schema; DisplayName=(New-Lbl $display); MinValue=$min; MaxValue=$max; RequiredLevel=@{Value="None"} }
}
Export-ModuleMember -Function New-IntAttr

function New-BoolAttr($schema, $display, $trueLabel="Yes", $falseLabel="No") {
    @{ "@odata.type"="Microsoft.Dynamics.CRM.BooleanAttributeMetadata"; SchemaName=$schema; DisplayName=(New-Lbl $display)
       OptionSet=@{ "@odata.type"="Microsoft.Dynamics.CRM.BooleanOptionSetMetadata"; TrueOption=@{Value=1;Label=(New-Lbl $trueLabel)}; FalseOption=@{Value=0;Label=(New-Lbl $falseLabel)} }
       RequiredLevel=@{Value="None"} }
}
Export-ModuleMember -Function New-BoolAttr

function New-DtAttr($schema, $display, $format="DateAndTime") {
    @{ "@odata.type"="Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"; SchemaName=$schema; DisplayName=(New-Lbl $display); Format=$format; RequiredLevel=@{Value="None"} }
}
Export-ModuleMember -Function New-DtAttr

function New-PickAttr($schema, $display, [string[]]$options) {
    $opts = @(); $i = 100000000
    foreach ($o in $options) { $opts += @{Value=$i; Label=(New-Lbl $o)}; $i++ }
    @{ "@odata.type"="Microsoft.Dynamics.CRM.PicklistAttributeMetadata"; SchemaName=$schema; DisplayName=(New-Lbl $display)
       OptionSet=@{ "@odata.type"="Microsoft.Dynamics.CRM.OptionSetMetadata"; IsGlobal=$false; Options=$opts }
       RequiredLevel=@{Value="None"} }
}
Export-ModuleMember -Function New-PickAttr

function New-EmailAttr($schema, $display) {
    @{ "@odata.type"="Microsoft.Dynamics.CRM.StringAttributeMetadata"; SchemaName=$schema; DisplayName=(New-Lbl $display); MaxLength=250; FormatName=@{Value="Email"}; RequiredLevel=@{Value="None"} }
}
Export-ModuleMember -Function New-EmailAttr

# ── Table creation ─────────────────────────────────────────────────────────────

function New-DvTable {
    param(
        [string]$SchemaName,       # e.g. "clinical_MyTable"
        [string]$DisplayName,
        [string]$DisplayPluralName,
        [array]$Columns            # Array built with New-*Attr helpers
    )
    $h = Get-DvHeaders
    $def = @{
        "@odata.type"="Microsoft.Dynamics.CRM.EntityMetadata"
        SchemaName=$SchemaName; DisplayName=(New-Lbl $DisplayName); DisplayCollectionName=(New-Lbl $DisplayPluralName)
        HasActivities=$false; HasNotes=$false; IsActivity=$false; OwnershipType="UserOwned"
        Attributes=$Columns
    }
    $wr = Invoke-WebRequest -Method Post -Uri "$script:Base/EntityDefinitions" -Headers $h -Body ($def|ConvertTo-Json -Depth 20)
    $mid = [regex]::Match($wr.Headers["OData-EntityId"],"([0-9a-f-]{36})").Value
    if (-not $mid) { throw "Table created but could not extract MetadataId from response." }
    Add-ToSolution $mid 1
    Write-Host "Table created: $DisplayName [$mid]" -ForegroundColor Green
    return $mid
}
Export-ModuleMember -Function New-DvTable

# Add a lookup column to an existing table (N:1 relationship)
function Add-DvLookup {
    param(
        [string]$FromTable,         # Logical name of table getting the lookup
        [string]$ToTable,           # Logical name of referenced table
        [string]$LookupSchemaName,  # e.g. "clinical_clinicalsiteid"
        [string]$DisplayName,
        [string]$RelationshipSchemaName  # e.g. "clinical_clinicalsite_documentsubmission"
    )
    $h = Get-DvHeaders
    $def = @{
        "@odata.type"="Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata"
        SchemaName=$RelationshipSchemaName
        ReferencedEntity=$ToTable
        ReferencingEntity=$FromTable
        Lookup=@{
            "@odata.type"="Microsoft.Dynamics.CRM.LookupAttributeMetadata"
            SchemaName=$LookupSchemaName
            DisplayName=(New-Lbl $DisplayName)
            RequiredLevel=@{Value="None"}
        }
    }
    Invoke-RestMethod -Method Post -Uri "$script:Base/RelationshipDefinitions" -Headers $h -Body ($def|ConvertTo-Json -Depth 10) | Out-Null
    Write-Host "Lookup added: $LookupSchemaName -> $ToTable" -ForegroundColor Green
}
Export-ModuleMember -Function Add-DvLookup

# ── Solution component ─────────────────────────────────────────────────────────

function Add-ToSolution {
    param([string]$ComponentId, [int]$ComponentType)
    # ComponentType: 1=Entity, 29=Workflow, 61=WebResource, 90=PluginAssembly, 92=SdkStep
    $h = Get-DvHeaders
    $sp = @{ ComponentId=$ComponentId; ComponentType=$ComponentType; SolutionUniqueName=$script:SolutionName; AddRequiredComponents=$false } | ConvertTo-Json
    try { Invoke-RestMethod -Method Post -Uri "$script:Base/AddSolutionComponent" -Headers $h -Body $sp | Out-Null }
    catch { Write-Warning "AddSolutionComponent: $($_.Exception.Message)" }
}
Export-ModuleMember -Function Add-ToSolution

# ── Flows ──────────────────────────────────────────────────────────────────────

function Deploy-DvFlow {
    param(
        [string]$DisplayName,
        [string]$PrimaryEntity,   # e.g. "clinical_documentsubmission" or "none"
        [object]$FlowDefinition   # Already-parsed PSObject (from ConvertFrom-Json on a flow JSON file)
    )
    $h = Get-DvHeaders
    $clientdata = @{ schemaVersion="1.0.0.0"; properties=$FlowDefinition.properties } | ConvertTo-Json -Depth 30 -Compress
    $payload = @{ name=$DisplayName; category=5; type=1; primaryentity=$PrimaryEntity; clientdata=$clientdata } | ConvertTo-Json -Depth 5
    $resp = Invoke-RestMethod -Method Post -Uri "$script:Base/workflows" -Headers $h -Body $payload
    $fid = $resp.workflowid
    if ($fid) {
        Add-ToSolution $fid 29
        Write-Host "Flow deployed: $DisplayName [$fid]" -ForegroundColor Green
    } else {
        # Try to find it by name
        $found = (Invoke-RestMethod -Method Get -Uri "$script:Base/workflows?`$filter=name eq '$DisplayName' and category eq 5&`$select=workflowid&`$orderby=createdon desc&`$top=1" -Headers $h).value[0]
        $fid = $found?.workflowid
        if ($fid) { Add-ToSolution $fid 29; Write-Host "Flow deployed: $DisplayName [$fid]" -ForegroundColor Green }
        else { Write-Warning "Flow may have been created but ID could not be confirmed." }
    }
    return $fid
}
Export-ModuleMember -Function Deploy-DvFlow

function Update-DvFlow {
    param([string]$FlowId, [object]$FlowDefinition)
    $h = Get-DvHeaders
    $clientdata = @{ schemaVersion="1.0.0.0"; properties=$FlowDefinition.properties } | ConvertTo-Json -Depth 30 -Compress
    $payload = @{ clientdata=$clientdata } | ConvertTo-Json -Depth 5
    Invoke-RestMethod -Method Patch -Uri "$script:Base/workflows($FlowId)" -Headers $h -Body $payload | Out-Null
    Write-Host "Flow updated: $FlowId" -ForegroundColor Green
}
Export-ModuleMember -Function Update-DvFlow

# ── Web Resources ──────────────────────────────────────────────────────────────

function Deploy-DvWebResource {
    param(
        [string]$Name,          # e.g. "clinical_/js/my_form.js" (no prefix slash needed)
        [string]$DisplayName,
        [string]$Type,          # "JavaScript" | "HTML" | "CSS" | "PNG" | "SVG"
        [string]$Content        # Raw file content (string) OR file path
    )
    $h = Get-DvHeaders
    # Resolve type code
    $typeMap = @{ JavaScript=3; HTML=1; CSS=6; XML=4; PNG=5; JPG=7; GIF=8; XAP=9; XSL=10; ICO=11; SVG=11; Resx=12 }
    $typeCode = $typeMap[$Type]
    if (-not $typeCode) { throw "Unknown web resource type: $Type. Use: JavaScript, HTML, CSS, PNG, SVG" }
    # Load content
    if (Test-Path $Content -ErrorAction SilentlyContinue) { $Content = Get-Content $Content -Raw }
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Content))
    # Check if exists
    $existing = (Invoke-RestMethod -Method Get -Uri "$script:Base/webresourceset?`$filter=name eq '$Name'&`$select=webresourceid" -Headers $h).value[0]
    if ($existing) {
        $wrid = $existing.webresourceid
        $payload = @{ content=$b64; displayname=$DisplayName } | ConvertTo-Json
        Invoke-RestMethod -Method Patch -Uri "$script:Base/webresourceset($wrid)" -Headers $h -Body $payload | Out-Null
        Write-Host "Web resource updated: $Name [$wrid]" -ForegroundColor Yellow
    } else {
        $payload = @{ name=$Name; displayname=$DisplayName; webresourcetype=$typeCode; content=$b64 } | ConvertTo-Json
        $wr = Invoke-WebRequest -Method Post -Uri "$script:Base/webresourceset" -Headers $h -Body $payload
        $wrid = [regex]::Match($wr.Headers["OData-EntityId"],"([0-9a-f-]{36})").Value
        Add-ToSolution $wrid 61
        Write-Host "Web resource created: $Name [$wrid]" -ForegroundColor Green
    }
    # Publish
    $xml = "<importexportxml><webresources><webresource>{$wrid}</webresource></webresources></importexportxml>"
    Invoke-RestMethod -Method Post -Uri "$script:Base/PublishXml" -Headers $h -Body (@{ParameterXml=$xml}|ConvertTo-Json) | Out-Null
    Write-Host "Published: $Name" -ForegroundColor Green
    return $wrid
}
Export-ModuleMember -Function Deploy-DvWebResource

# ── Plugins ────────────────────────────────────────────────────────────────────

function Register-DvPlugin {
    param(
        [string]$DllPath,           # Path to compiled .dll
        [string]$PluginTypeName,    # Full type name e.g. "Kantia.Plugins.OnCreateDocument"
        [string]$AssemblyName,      # Friendly name e.g. "Kantia.Plugins"
        [array]$Steps               # Array of step definitions (see Register-DvPluginStep)
    )
    $h = Get-DvHeaders
    $dllBytes = [IO.File]::ReadAllBytes($DllPath)
    $b64 = [Convert]::ToBase64String($dllBytes)
    # Register assembly
    $asmPayload = @{ name=$AssemblyName; content=$b64; isolationmode=2; sourcetype=0 } | ConvertTo-Json
    $asmWr = Invoke-WebRequest -Method Post -Uri "$script:Base/pluginassemblies" -Headers $h -Body $asmPayload
    $asmId = [regex]::Match($asmWr.Headers["OData-EntityId"],"([0-9a-f-]{36})").Value
    Add-ToSolution $asmId 90
    Write-Host "Plugin assembly registered: $AssemblyName [$asmId]" -ForegroundColor Green
    # Register plugin type
    $typePayload = @{ name=$PluginTypeName; typename=$PluginTypeName; "pluginassemblyid@odata.bind"="/pluginassemblies($asmId)" } | ConvertTo-Json
    $typeWr = Invoke-WebRequest -Method Post -Uri "$script:Base/plugintypes" -Headers $h -Body $typePayload
    $typeId = [regex]::Match($typeWr.Headers["OData-EntityId"],"([0-9a-f-]{36})").Value
    Write-Host "Plugin type registered: $PluginTypeName [$typeId]" -ForegroundColor Green
    # Register steps
    foreach ($step in $Steps) {
        Register-DvPluginStep -PluginTypeId $typeId -Step $step
    }
    return @{ AssemblyId=$asmId; TypeId=$typeId }
}
Export-ModuleMember -Function Register-DvPlugin

function Register-DvPluginStep {
    param([string]$PluginTypeId, [hashtable]$Step)
    # Step keys: MessageName, EntityLogicalName, Stage (10=PreValidation,20=PreOperation,40=PostOperation), Mode (0=Sync,1=Async), Rank, FilteringAttributes
    $h = Get-DvHeaders
    # Resolve SDK message
    $msg = (Invoke-RestMethod -Method Get -Uri "$script:Base/sdkmessages?`$filter=name eq '$($Step.MessageName)'&`$select=sdkmessageid" -Headers $h).value[0]
    $msgId = $msg.sdkmessageid
    # Resolve message filter (entity-specific)
    $filter = (Invoke-RestMethod -Method Get -Uri "$script:Base/sdkmessagefilters?`$filter=_sdkmessageid_value eq $msgId and primaryobjecttypecode eq '$($Step.EntityLogicalName)'&`$select=sdkmessagefilterid" -Headers $h).value[0]
    $filterId = $filter?.sdkmessagefilterid
    $stepPayload = @{
        name = "$($Step.EntityLogicalName): $($Step.MessageName) of $PluginTypeId"
        rank = if($Step.Rank){$Step.Rank}else{1}
        stage = $Step.Stage
        mode = $Step.Mode
        "plugintypeid@odata.bind" = "/plugintypes($PluginTypeId)"
        "sdkmessageid@odata.bind" = "/sdkmessages($msgId)"
    }
    if ($filterId) { $stepPayload["sdkmessagefilterid@odata.bind"] = "/sdkmessagefilters($filterId)" }
    if ($Step.FilteringAttributes) { $stepPayload["filteringattributes"] = $Step.FilteringAttributes }
    $stepWr = Invoke-WebRequest -Method Post -Uri "$script:Base/sdkmessageprocessingsteps" -Headers $h -Body ($stepPayload|ConvertTo-Json)
    $stepId = [regex]::Match($stepWr.Headers["OData-EntityId"],"([0-9a-f-]{36})").Value
    Add-ToSolution $stepId 92
    Write-Host "Step registered: $($Step.MessageName) on $($Step.EntityLogicalName) [Stage $($Step.Stage)] [$stepId]" -ForegroundColor Green
    return $stepId
}
Export-ModuleMember -Function Register-DvPluginStep

function Update-DvPlugin {
    param([string]$AssemblyId, [string]$DllPath)
    $h = Get-DvHeaders
    $dllBytes = [IO.File]::ReadAllBytes($DllPath)
    $b64 = [Convert]::ToBase64String($dllBytes)
    Invoke-RestMethod -Method Patch -Uri "$script:Base/pluginassemblies($AssemblyId)" -Headers $h -Body (@{content=$b64}|ConvertTo-Json) | Out-Null
    Write-Host "Plugin assembly updated: $AssemblyId" -ForegroundColor Green
}
Export-ModuleMember -Function Update-DvPlugin
