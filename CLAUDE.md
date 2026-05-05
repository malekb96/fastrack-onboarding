# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Fast Track Onboarding** is a Power Platform solution for automating clinical trial site document intake and compliance review. It lives in Dataverse environment **Malek Belhadj** (`https://orgebcd0239.crm3.dynamics.com`).

The solution unique name is `FastTrackOnboarding`.

## Dataverse API Access

All interactions with the environment use a service principal (SPN):

- **Tenant ID**: `ae481188-942a-44a5-9019-ae83fc025ac3`
- **Client ID**: `506c2f0b-4f76-4324-9c34-31065135a2ab`
- **Org URL**: `https://orgebcd0239.crm3.dynamics.com`
- **PA env ID**: `c229cf99-9f18-ed1e-93fb-da0119bd33f3`

Token fetch (Dataverse scope):
```powershell
$tok = (Invoke-RestMethod -Method Post `
  -Uri "https://login.microsoftonline.com/ae481188-942a-44a5-9019-ae83fc025ac3/oauth2/v2.0/token" `
  -Body @{ grant_type="client_credentials"; client_id="506c2f0b-4f76-4324-9c34-31065135a2ab"; client_secret=$env:CLIENT_SECRET; scope="https://orgebcd0239.crm3.dynamics.com/.default" }).access_token
```

Token fetch (Power Automate Management API):
```powershell
$paTok = (Invoke-RestMethod ... -Body @{ ...; scope="https://service.flow.microsoft.com/.default" }).access_token
```

> **Note**: The PA Management API (`api.flow.microsoft.com`) rejects SPN tokens with `ClientScopeAuthorizationFailed`. Flows must be created/updated via the **Dataverse `workflows` entity** (`category=5`, `type=1`) instead.

## Solution Architecture

```
Outlook email (attachment) ──► Flow 1: Intake
                                    │ creates Email Intake + Document Submission (status=Received)
                                    ▼
                              Flow 2: AI Document Audit  (Dataverse trigger on Doc Submission create)
                                    │ calls AI Builder prompt → parses JSON
                                    │ creates AI Audit Result + Document Anomalies
                                    │ updates Doc Submission (compliance status, AI summary)
                                    ▼
                         ┌──────────────────────────┐
                    blocking anomalies?        email_response.should_send_email?
                         │                          │
                         ▼                          ▼
                   Follow-up Task ──► Flow 3: Send Site Follow-up
                                    (Dataverse trigger on Follow-up Task create)

                   Reviewer sets decision ──► Flow 4: Human Review Decision Handler
                                    (Dataverse trigger on Doc Submission update)
                                    Approved → set Compliant, close anomalies
                                    Rejected → set Non-Compliant, create Follow-up Task
                                    Override → set Compliant, prefix AI summary with [OVERRIDE]
```

## Dataverse Tables (prefix: `clinical_`)

| Display Name | Logical Name | Entity Set |
|---|---|---|
| Clinical Trial | `clinical_clinicaltrial` | `clinical_clinicaltrials` |
| Clinical Site | `clinical_clinicalsite` | `clinical_clinicalsites` |
| Site Personnel | `clinical_sitepersonnel` | `clinical_sitepersonnels` |
| Document Requirement | `clinical_documentrequirement` | `clinical_documentrequirements` |
| Email Intake | `clinical_emailintake` | `clinical_emailintakes` |
| Document Submission | `clinical_documentsubmission` | `clinical_documentsubmissions` |
| AI Audit Result | `clinical_aiauditresult` | `clinical_aiauditresults` |
| Document Anomaly | `clinical_documentanomaly` | `clinical_documentanomalies` |
| Follow-up Task | `clinical_followuptask` | `clinical_followuptasks` |

## Choice Field Values

All choice fields use values starting at `100000000` in the order they were defined:

**`clinical_processingstatus`** (Document Submission): Received=`100000000`, AI Processing=`100000001`, Parsed=`100000002`, Stored=`100000003`, Failed=`100000004`

**`clinical_compliancestatus`** / **`clinical_auditstatus`**: Compliant=`100000000`, Non-Compliant=`100000001`, Needs Review=`100000002`, Unsupported=`100000003`

**`clinical_reviewerdecision`**: Pending=`100000000`, Approved=`100000001`, Rejected=`100000002`, Override=`100000003`

**`clinical_tasktype`** (Follow-up Task): Email Follow-up=`100000000`, Human Review=`100000001`, Escalation=`100000002`

**`clinical_status`** (Follow-up Task): Open=`100000000`, Sent=`100000001`, Waiting Response=`100000002`, Completed=`100000003`, Cancelled=`100000004`

**`clinical_status`** (Document Anomaly): Open=`100000000`, Resolved=`100000001`, Waived=`100000002`

**`clinical_severity`**: Low=`100000000`, Medium=`100000001`, High=`100000002`, Critical=`100000003`

## Flow Definitions

The `flows/` directory contains the canonical Logic Apps JSON definitions for all 4 flows:

| File | Flow Name | Dataverse Workflow ID |
|---|---|---|
| `flow1-intake-outlook.json` | PA - Intake Outlook Site Documents | `6938a6fc-2e48-f111-bec7-000d3af4c95b` |
| `flow2-ai-document-audit.json` | PA - AI Document Audit | `7e38a6fc-2e48-f111-bec7-000d3af4c95b` |
| `flow3-send-site-followup.json` | PA - Send Site Follow-up | `55b22639-2f48-f111-bec7-000d3af4c95b` |
| `flow4-human-review-handler.json` | PA - Human Review Decision Handler | `9138a6fc-2e48-f111-bec7-000d3af4c95b` |

### Deploying a flow update via API

```powershell
$flowJson = Get-Content "flows/flow2-ai-document-audit.json" -Raw | ConvertFrom-Json
$clientdata = @{ schemaVersion="1.0.0.0"; properties=$flowJson.properties } | ConvertTo-Json -Depth 30 -Compress
$payload = @{ clientdata=$clientdata } | ConvertTo-Json -Depth 5
Invoke-RestMethod -Method Patch -Uri "$base/workflows(7e38a6fc-2e48-f111-bec7-000d3af4c95b)" -Headers $h -Body $payload
```

### Adding a component to the solution

```powershell
# ComponentType: 1=Entity, 29=Workflow/Flow
$sp = @{ ComponentId=$id; ComponentType=29; SolutionUniqueName="FastTrackOnboarding"; AddRequiredComponents=$false } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri "$base/AddSolutionComponent" -Headers $h -Body $sp
```

## AI Builder Prompt

The prompt **"FAST TRACK ONBOARDING DOCUMENT AUDIT"** (GPT-4.1) is referenced in `flow2-ai-document-audit.json` via the placeholder `REPLACE_WITH_FAST_TRACK_ONBOARDING_DOCUMENT_AUDIT_PROMPT_ID`. The prompt ID must be set manually in the Power Automate maker portal after authorizing connections.

The prompt always returns a structured JSON with sections: `processing_metadata`, `compliance_assessment`, `site_context`, `person_context`, `document_details`, `extracted_fields`, `anomalies`, `recommended_actions`, `email_response`.

## GitHub Repository

`malekb96/fastrack-onboarding` — push via `git push origin master`.
gh CLI is authenticated as `malekb96`.

## Auto-Learning Protocol

This repo uses a recursive self-improvement system. Every Claude session is expected to feed discoveries back into the knowledge base.

### At the start of any non-trivial session
1. Check `.claude/pending-learnings.md` — process any unchecked items from prior sessions.
2. Glance at `learnings/pitfalls.md` for entries relevant to the current task.

### During a session — write learnings immediately when you:
- Hit an error and fix it → `learnings/pitfalls.md`
- Find a pattern that works better than the current skill instructions → `learnings/patterns.md`
- Receive a user correction → `memory/feedback_*.md` (and update the skill if applicable)
- Create a new table, flow, or choice field with IDs → this file (`CLAUDE.md`)

### Use `/learn` or the **auto-learn** skill to capture any learning.

### Never hardcode secrets — always use `$env:PP_CLIENT_SECRET` (and the other `PP_*` env vars).

### Skills available (`.claude/skills/`)
| Skill | Trigger |
|---|---|
| `pp-table` | Create Dataverse table / add columns |
| `pp-flow` | Create or update a Power Automate flow |
| `pp-webresource` | Create JS or HTML web resource |
| `pp-plugin` | Scaffold and register a C# Dataverse plugin |
| `auto-learn` | Persist any new pitfall, pattern, or correction |
