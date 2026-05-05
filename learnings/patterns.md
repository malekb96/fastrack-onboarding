# Proven Patterns & Best Practices

Patterns that have been validated in this project. Use these as defaults.

---

## PowerShell / Dataverse API

### Module-first pattern
Always start any Dataverse script with:
```powershell
$env:PP_CLIENT_SECRET = "..."   # set before import if not already in env
Import-Module .\tools\PowerPlatform.psm1
```
This gives you all helpers without re-defining anything.

### Token-per-call via `Get-DvHeaders`
Don't cache the token manually. `Get-DvHeaders` fetches a fresh token each time, which avoids expiry issues during long scripts:
```powershell
$h = Get-DvHeaders   # fresh token every time
Invoke-RestMethod -Method Get -Uri "$script:Base/..." -Headers $h
```

### Build flow definitions as hashtables, not file reads
```powershell
$def = @{
    properties = @{
        displayName = "PA - My Flow"
        definition  = @{
            '$schema'      = "https://schema.management.azure.com/..."
            triggers       = @{ ... }
            actions        = @{ ... }
        }
        connectionReferences = @{ ... }
    }
}
Deploy-DvFlow -DisplayName "PA - My Flow" -PrimaryEntity "clinical_myentity" -FlowDefinition $def
```

### `Invoke-WebRequest` for POST/PATCH that return entity IDs
Use `Invoke-WebRequest` (not `Invoke-RestMethod`) whenever you need the `OData-EntityId` response header (table creation, workflow creation). Extract the GUID:
```powershell
$r  = Invoke-WebRequest ...
$id = [regex]::Match($r.Headers["OData-EntityId"], '[0-9a-f-]{36}').Value
```

---

## Dataverse Schema

### Namespace all columns with `clinical_` prefix
Every column, table, and relationship schema name must start with `clinical_`. This avoids conflicts with system columns and future MS updates.

### Primary column is always `clinical_name`
```powershell
$cols = @(
    (New-PrimaryAttr "clinical_name" "Name"),   # ALWAYS first, ALWAYS required
    ...
)
```

### Add to solution immediately after creation
`New-DvTable` and `Deploy-DvFlow` call `Add-ToSolution` automatically. For manually created components, always call:
```powershell
Add-ToSolution -ComponentId $id -ComponentType 29   # 29=Workflow, 1=Entity, 61=WebResource, 90=PluginAssembly
```

---

## Power Automate Flows

### Dataverse trigger — always use scope=4 (Organization)
```json
"subscriptionRequest/scope": 4
```
Scope 1 (User) and 2 (BusinessUnit) miss records created by other users / the SPN.

### runAfter chaining
Every non-root action needs `"runAfter": { "PreviousActionName": ["Succeeded"] }`. Omitting this makes actions run in parallel, which causes race conditions on record updates.

### Switch > nested If for multi-branch logic
```json
"Switch_On_Field": {
  "type": "Switch",
  "expression": "@triggerOutputs()?['body/clinical_reviewerdecision']",
  "cases": { ... },
  "default": { "actions": {} }
}
```
Switch is cleaner than nested If/Else when branching on a choice field.

### Use `coalesce()` for nullable fields in flow expressions
```
@coalesce(triggerOutputs()?['body/clinical_reviewercomments'], 'No comments provided.')
```

---

## JavaScript Web Resources

### Always use the `KT.<TableName>Form` IIFE namespace
```javascript
var KT = KT || {};
KT.DocumentForm = (function () {
    "use strict";
    // ... private functions ...
    return { onLoad, onSave, onReviewerDecisionChange };
})();
```
This prevents global conflicts and makes function registration unambiguous.

### Guard every `getControl` / `getAttribute` call
```javascript
var ctrl = formContext.getControl("clinical_myfield");
if (ctrl) ctrl.setDisabled(true);   // never assume the control exists
```

### Clear notifications before setting them
```javascript
formContext.ui.clearFormNotification("my_notification_id");
formContext.ui.setFormNotification("Message", "ERROR", "my_notification_id");
```
Otherwise stale notifications linger after the condition clears.

---

## C# Plugins

### Always inherit from `PluginBase`, never implement `IPlugin` directly
`PluginBase` handles tracing, service resolution, and wraps exceptions into `InvalidPluginExecutionException`. Direct `IPlugin` implementations miss this safety net.

### Use `context.UserId` (not `null`) for org service creation
```csharp
var orgSvc = factory.CreateOrganizationService(context.UserId);
```
`null` gives system-level access which bypasses security roles — use the triggering user's context.

### Stage 20 (PreOperation) for validation and field defaults; Stage 40 (PostOperation) for side-effects
- Stage 20: can modify `InputParameters["Target"]` before the record is written. Must be synchronous.
- Stage 40: record already committed, use for creating related records or calling external services. Can be async (Mode=1).
