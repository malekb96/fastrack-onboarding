# Pitfalls & Known Issues

Each entry follows: **Symptom → Root cause → Fix → Files updated**.

---

## Power Automate API

### SPN tokens rejected by `api.flow.microsoft.com`
- **Symptom**: `ClientScopeAuthorizationFailed` when calling `api.flow.microsoft.com/providers/Microsoft.ProcessSimple/...`
- **Root cause**: The PA Management API only accepts delegated user tokens (interactive sign-in). Client-credentials SPN tokens are always rejected.
- **Fix**: Create and update flows via the Dataverse **`workflows` entity** (`category=5`, `type=1`, `primaryentity=<table>`) using the Dataverse token. Use `Deploy-DvFlow` / `Update-DvFlow` from `tools/PowerPlatform.psm1`.
- **Documented in**: CLAUDE.md, `.claude/skills/pp-flow/SKILL.md`

### Flows owned by SPN not visible in "My flows"
- **Symptom**: Deployed flows are invisible in the Power Automate portal under "My flows".
- **Root cause**: Flows are owned by the SPN app user account, not the human user.
- **Fix**: Access via **Solutions → FastTrackOnboarding → Cloud Flows**. If ownership transfer is needed, patch `ownerid@odata.bind` only AFTER connections are authorized (otherwise you get `FlowMissingConnection`).
- **Documented in**: CLAUDE.md

---

## Dataverse REST API

### `Invoke-RestMethod` drops response headers
- **Symptom**: After table creation (HTTP 204), the MetadataId / entity GUID is null or missing.
- **Root cause**: PowerShell's `Invoke-RestMethod` silently discards response headers on no-content responses.
- **Fix**: Use `Invoke-WebRequest` instead. Parse the GUID from `$r.Headers["OData-EntityId"]` — it's a URL like `https://org.crm.dynamics.com/api/data/v9.2/EntityDefinitions(guid)`.
  ```powershell
  $r   = Invoke-WebRequest -Method Post -Uri $uri -Headers $h -Body $body
  $url = $r.Headers["OData-EntityId"]
  $id  = [regex]::Match($url, '[0-9a-f-]{36}').Value
  ```
- **Documented in**: `tools/PowerPlatform.psm1` → `New-DvTable`, `.claude/skills/pp-table/SKILL.md`

### Primary attribute requires `IsPrimaryName = $true`
- **Symptom**: `Required field 'PrimaryAttribute' is missing` when creating an entity, even when `PrimaryNameAttribute` is set at the entity level.
- **Root cause**: The Dataverse API requires `IsPrimaryName=$true` to be set **inside the attribute object itself** in the `Attributes` array. The entity-level property alone is ignored.
- **Fix**: Always pass the primary name column through `New-PrimaryAttr` (not `New-StrAttr`). `New-PrimaryAttr` sets `IsPrimaryName=$true`.
- **Documented in**: `tools/PowerPlatform.psm1`, `.claude/skills/pp-table/SKILL.md`

### Choice field values start at 100000000
- **Pattern**: All picklist options are assigned integer values starting at `100000000`, incrementing by 1 in declaration order.
- **Risk**: Hardcoding wrong values in flow conditions causes silent mismatches.
- **Fix**: Always declare option labels in order and document the mapping in CLAUDE.md when creating new choice columns.
- **Documented in**: CLAUDE.md → "Choice Field Values"

### Filter expression in Dataverse webhook trigger requires single-quotes around GUIDs
- **Pattern**: `$filter` on webhook triggers must use single-quoted string values for GUID comparisons:
  ```
  "_clinical_documentsubmissionid_value eq '<guid>'"
  ```
  Not double-quoted. Dynamic expressions use `@concat(...)`.

---

## PowerShell Execution

### Functions don't persist between separate tool calls
- **Symptom**: `The term 'Get-DvToken' is not recognized as the name of a cmdlet`.
- **Root cause**: Each `Bash` / `PowerShell` tool invocation is an independent process. Variables, functions, and `Import-Module` calls don't carry over.
- **Fix**: Either (a) put function definitions **and** their usage in ONE single command block, or (b) start every block with `Import-Module .\tools\PowerPlatform.psm1`.

### `??` null-coalescing operator not available in Windows PowerShell 5.1
- **Symptom**: `ParserError: Unexpected token '??'` — module fails to import entirely.
- **Root cause**: `??` requires PowerShell 7+. The environment runs Windows PowerShell 5.1.
- **Fix**: Use `if/else` — the only safe pattern in PS 5.1:
  ```powershell
  $x = if ($env:MY_VAR) { $env:MY_VAR } else { "default" }
  ```
- **Status**: Fixed in `tools/PowerPlatform.psm1` lines 4–7. Never use `??` in this repo.

### Flow JSON encoding issue when reading from file
- **Symptom**: `Exception: Stream was not readable` when piping file content through ConvertFrom-Json → ConvertTo-Json → REST call.
- **Root cause**: Mixing file-read encoding with nested JSON re-serialization causes buffer corruption in complex pipelines.
- **Fix**: Build flow definitions entirely as **PowerShell hashtables** (`@{ }`) and serialize at the last moment with `ConvertTo-Json -Depth 30 -Compress`. Avoid intermediate file reads for the definition object.

---

## Git / GitHub

### GitHub push protection blocks hardcoded secrets
- **Symptom**: `GH013: Repository rule violations — Push cannot contain secrets` → push is rejected.
- **Root cause**: GitHub secret scanning detects Azure AD client secrets committed in source files.
- **Fix**: **Never hardcode** `CLIENT_SECRET` (or any credential) in committed files. Use environment variables:
  ```powershell
  $env:PP_CLIENT_SECRET = "..."
  Import-Module .\tools\PowerPlatform.psm1
  ```
- **Rule**: All secrets go into env vars only. The module reads `$env:PP_CLIENT_SECRET`.

---

## AI Builder

### Prompt ID retrieval via Dataverse
- **Pattern**: AI Builder prompts are stored in `msdyn_aimodels` entity. Query with SPN token:
  ```powershell
  GET /api/data/v9.2/msdyn_aimodels?$filter=contains(msdyn_name,'PROMPT')&$select=msdyn_aimodelid,msdyn_name
  ```
- **Current prompt**: `43661eeb-0417-45a5-9ac9-a26307b9b31b` = `PROMPT — FAST TRACK ONBOARDING DOCUMENT AUDIT`

## Power Platform Connection Limitations (CRITICAL)

### SPN cannot use OAuth connections owned by users
- **Symptom**: `ConnectionAuthorizationFailed: The caller [SPN object id] cannot be used to activate this flow... Either replace the connection... or have the connection owner activate the flow, so the connection is shared with you in the context of this flow.`
- **Root cause**: SPNs do not get implicit access to user-owned OAuth connections (Office 365, AI Builder, etc). This is a platform security feature, not a bug.
- **Fix**: Either (a) the user shares each connection with the SPN as "Can use" via Power Automate → Data → Connections → ... → Share, or (b) the user opens each flow in the portal and saves it once (the platform then associates the user's connection in the flow context).

### OAuth connections cannot be created via API
- **Symptom**: `405 Method Not Allowed` or `404 Not Found` when POST/PUT to `https://canada.api.powerapps.com/providers/Microsoft.PowerApps/connections`
- **Root cause**: OAuth connectors (Office 365, AI Builder) require browser-based consent flow that cannot be executed programmatically.
- **Fix**: User must create connections manually in **Power Automate → Data → Connections → + New connection**.

### Flow ownership transfer is blocked when flow definition has invalid connection refs
- **Symptom**: `BadRequest` on simple `PATCH ownerid@odata.bind` because validation runs on existing clientdata.
- **Root cause**: ANY workflow PATCH triggers full flow definition re-validation. If existing `connectionReferences.<key>.connection = {}` is empty, validation fails before ownership transfer can happen.
- **Fix**: PATCH ownerid AND clientdata in the same request, with corrected connection references in the new clientdata.

### Patching flow owned by SPN as user fails with MissingUserDetails
- **Symptom**: `BapListServicePlansFailed: The user details for tenant id ... and principal id <SPN id> doesn't exist.`
- **Root cause**: When a user token PATCHes a workflow owned by an SPN, the platform tries to verify the SPN's PA service plan and fails (SPN has no PA license).
- **Fix**: Transfer ownership to a licensed user before patching, OR use SPN token but only after sharing the connections with SPN.

### Dataverse connector: `GetRecord` is not a valid operation
- **Symptom**: `WorkflowOperationInputsApiOperationNotFound: The API operation 'GetRecord' could not be found in API 'commondataserviceforapps'`
- **Fix**: Use `GetItem` for retrieving a single record by ID. Other valid ops: `ListRecords`, `CreateRecord`, `UpdateRecord`, `DeleteRecord`.

### `connectionReferenceLogicalName` requires existing Dataverse connectionreferences record
- **Pattern**: To use connection references in a flow, the `connectionreferences` entity must have a record with the right `connectorid` and a non-empty `connectionid` BEFORE the flow can reference it via `connection: { connectionReferenceLogicalName: "<name>" }`.
- **Useful**: Query existing refs first:
  ```
  GET /connectionreferences?$select=connectionreferencelogicalname,connectorid,connectionid
  ```
- **Pre-existing in fresh env**: `msdyn_Dataverse` (for `shared_commondataserviceforapps`), `msdyn_ContentConversion`, but `connectionid` is empty until a user token PATCHes them.

### Creating connection references requires user token (not SPN)
- **Symptom**: `ConnectionAuthorizationFailed` when SPN tries to create or PATCH connectionreferences with a user-owned connectionid.
- **Fix**: Use device code flow to get user's Dataverse token, then create/patch connection references with that token.
