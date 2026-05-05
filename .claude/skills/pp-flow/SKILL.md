---
name: pp-flow
description: >
  Create, update, or deploy a Power Automate cloud flow to the FastTrackOnboarding Dataverse
  solution using the SPN. Use this skill whenever the user asks to create a flow, automate a
  process, add a Power Automate workflow, build a trigger for Dataverse or Outlook events,
  or update an existing flow definition. Triggers on: "create a flow", "automate when X happens",
  "add a workflow that...", "update the flow for...", "deploy flow", "new PA flow".
---

# pp-flow — Create & Deploy Power Automate Flows

## Critical: PA API limitation

The `api.flow.microsoft.com` Management API rejects SPN tokens with `ClientScopeAuthorizationFailed`.
**Always create/update flows via the Dataverse `workflows` entity** (category=5).

## Step-by-step

1. **Understand the flow**: ask for trigger type, main logic, tables involved, and whether it calls AI Builder.
2. **Generate the flow JSON** following the Logic Apps schema below.
3. **Deploy** using `Deploy-DvFlow` from the module or the raw PowerShell pattern.
4. **Verify** by querying `GET /api/data/v9.2/workflows?$filter=name eq '...' and category eq 5`.

## Trigger patterns

### Dataverse trigger (row created/updated)
```json
"triggers": {
  "When_Row_Created": {
    "type": "OpenApiConnectionWebhook",
    "inputs": {
      "host": { "connectionName": "shared_commondataserviceforapps", "operationId": "SubscribeWebhookTrigger", "apiId": "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps" },
      "parameters": {
        "subscriptionRequest/message": 1,
        "subscriptionRequest/entityname": "clinical_documentsubmission",
        "subscriptionRequest/scope": 4
      },
      "authentication": "@parameters('$authentication')"
    }
  }
}
```
- `message`: 1=Create, 2=Delete, 4=Update, 5=Create+Update
- `scope`: 4=Organization

### Outlook trigger (new email with attachment)
```json
"triggers": {
  "When_a_new_email_arrives": {
    "type": "OpenApiConnection",
    "inputs": {
      "host": { "connectionName": "shared_office365", "operationId": "OnNewEmailV3", "apiId": "/providers/Microsoft.PowerApps/apis/shared_office365" },
      "parameters": { "fetchOnlyWithAttachment": true, "includeAttachments": true, "folderPath": "Inbox" },
      "authentication": "@parameters('$authentication')"
    },
    "recurrence": { "frequency": "Minute", "interval": 3 },
    "splitOn": "@triggerOutputs()?['body/value']"
  }
}
```

### Scheduled (recurrence)
```json
"triggers": {
  "Recurrence": {
    "type": "Recurrence",
    "recurrence": { "frequency": "Day", "interval": 1, "startTime": "2026-01-01T08:00:00Z" }
  }
}
```

## Common action patterns

### Create Dataverse record
```json
"Create_Record": {
  "type": "OpenApiConnection",
  "runAfter": {},
  "inputs": {
    "host": { "connectionName": "shared_commondataserviceforapps", "operationId": "CreateRecord", "apiId": "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps" },
    "parameters": {
      "entityName": "clinical_documentsubmissions",
      "item/clinical_documentname": "@triggerOutputs()?['body/subject']",
      "item/clinical_processingstatus": 100000000,
      "item/clinical_emailintakeid@odata.bind": "@concat('/clinical_emailintakes(', variables('emailIntakeId'), ')')"
    },
    "authentication": "@parameters('$authentication')"
  }
}
```

### Update Dataverse record
```json
"Update_Record": {
  "type": "OpenApiConnection",
  "runAfter": { "Create_Record": ["Succeeded"] },
  "inputs": {
    "host": { "connectionName": "shared_commondataserviceforapps", "operationId": "UpdateRecord", "apiId": "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps" },
    "parameters": {
      "entityName": "clinical_documentsubmissions",
      "recordId": "@outputs('Create_Record')?['body/clinical_documentsubmissionid']",
      "item/clinical_processingstatus": 100000003
    },
    "authentication": "@parameters('$authentication')"
  }
}
```

### Call AI Builder prompt
```json
"Call_AI_Builder": {
  "type": "OpenApiConnection",
  "inputs": {
    "host": { "connectionName": "shared_aibuilder", "operationId": "CreateTextUsingPromptDeprecated", "apiId": "/providers/Microsoft.PowerApps/apis/shared_aibuilder" },
    "parameters": {
      "promptId": "REPLACE_WITH_PROMPT_ID",
      "promptParameterValues": [{ "key": "Document input", "fileContent": "@{base64(body('Get_File'))}", "fileName": "@{triggerOutputs()?['body/name']}" }]
    },
    "authentication": "@parameters('$authentication')"
  }
}
```

### Parse JSON
```json
"Parse_JSON": {
  "type": "ParseJson",
  "inputs": {
    "content": "@body('Call_AI_Builder')?['text']",
    "schema": { "type": "object", "properties": { "status": { "type": "string" } } }
  }
}
```

### Condition
```json
"Check_Condition": {
  "type": "If",
  "expression": { "greater": ["@body('Parse_JSON')?['count']", 0] },
  "actions": { "If_True_Action": { ... } },
  "else": { "actions": {} }
}
```

### Apply to each
```json
"Loop_Items": {
  "type": "Foreach",
  "foreach": "@body('Parse_JSON')?['items']",
  "actions": { "Process_Item": { ... } }
}
```

### Send email
```json
"Send_Email": {
  "type": "OpenApiConnection",
  "inputs": {
    "host": { "connectionName": "shared_office365", "operationId": "SendEmailV2", "apiId": "/providers/Microsoft.PowerApps/apis/shared_office365" },
    "parameters": { "emailMessage/To": "@variables('recipientEmail')", "emailMessage/Subject": "Subject", "emailMessage/Body": "Body text" },
    "authentication": "@parameters('$authentication')"
  }
}
```

## Full flow JSON wrapper

Every flow file must use this structure:

```json
{
  "properties": {
    "displayName": "PA - Flow Name",
    "definition": {
      "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
      "contentVersion": "1.0.0.0",
      "parameters": {
        "$connections": { "defaultValue": {}, "type": "Object" },
        "$authentication": { "defaultValue": {}, "type": "SecureObject" }
      },
      "triggers": { ... },
      "actions": { ... },
      "outputs": {}
    },
    "connectionReferences": {
      "shared_commondataserviceforapps": { "runtimeSource": "embedded", "connection": {}, "api": { "name": "shared_commondataserviceforapps" } },
      "shared_office365": { "runtimeSource": "invoker", "connection": {}, "api": { "name": "shared_office365" } },
      "shared_aibuilder": { "runtimeSource": "embedded", "connection": {}, "api": { "name": "shared_aibuilder" } }
    }
  }
}
```
Only include the connectionReferences that the flow actually uses.

## Deploy via PowerShell

```powershell
Import-Module .\tools\PowerPlatform.psm1
$flowDef = Get-Content "flows\my-flow.json" -Raw | ConvertFrom-Json
$id = Deploy-DvFlow -DisplayName "PA - My Flow" -PrimaryEntity "clinical_documentsubmission" -FlowDefinition $flowDef
```

For Outlook-triggered or non-entity flows, use `PrimaryEntity = "none"`.

## Update existing flow

```powershell
Import-Module .\tools\PowerPlatform.psm1
$flowDef = Get-Content "flows\my-flow.json" -Raw | ConvertFrom-Json
Update-DvFlow -FlowId "FLOW-GUID-HERE" -FlowDefinition $flowDef
```

## After deployment

Save the JSON to `flows/` in the repo, commit, and update the flow ID table in `CLAUDE.md`.
The user must authorize connections in Power Automate maker portal (Solutions → FastTrackOnboarding → Cloud Flows).

## Known pitfalls

See `learnings/pitfalls.md` — relevant sections:
- **SPN tokens rejected by `api.flow.microsoft.com`** — always use Dataverse `workflows` entity
- **Flows owned by SPN not visible in "My flows"** — access via Solutions → FastTrackOnboarding → Cloud Flows
- **Flow JSON encoding issue when reading from file** — build definitions as PowerShell hashtables, not file reads
- **`runAfter` omitted** — actions run in parallel and race condition on record updates; always chain explicitly
