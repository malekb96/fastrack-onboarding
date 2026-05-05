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

### `REPLACE_WITH_FAST_TRACK_ONBOARDING_DOCUMENT_AUDIT_PROMPT_ID` placeholder
- **Pattern**: The AI Builder prompt ID cannot be obtained programmatically via SPN. Must be retrieved from the maker portal after manually authorizing the AI Builder connection.
- **Location**: `flows/flow2-ai-document-audit.json` → `Call_AI_Builder.inputs.parameters.promptId`
- **Fix**: After authorizing connections in the maker portal, find the prompt ID under AI Builder → Prompts, then patch the flow JSON.
