---
name: pp-table
description: >
  Create a new Dataverse table (entity) with columns, option sets, and lookup relationships
  in the FastTrackOnboarding solution via the SPN API. Use this skill whenever the user asks
  to add a table, entity, or data model to the Power Platform environment — even if they say
  "create a new table for X", "I need to track Y in Dataverse", or "add columns to the solution".
  Triggers for any Dataverse schema work: new tables, new columns on existing tables, lookups.
---

# pp-table — Create Dataverse Tables

Use the PowerPlatform module at `tools/PowerPlatform.psm1`. Import it at the start of every script.

## Step-by-step

1. **Understand the table**: Ask the user for display name, plural name, schema prefix (default `clinical_`), and what columns are needed. Infer reasonable column types if obvious.

2. **Build the PowerShell script** using the helper functions below.

3. **Run via PowerShell** and confirm the table appears in the solution.

4. **Add lookups** if the table needs to reference other tables (separate step after table creation).

## Column builder reference

```powershell
Import-Module .\tools\PowerPlatform.psm1

# Always start with the primary name column (required)
$cols = @(
    (New-PrimaryAttr "clinical_name"      "Name"),           # Primary, required
    (New-StrAttr     "clinical_code"      "Code"        50), # Short text
    (New-StrAttr     "clinical_email"     "Email"      250), # Long text
    (New-MemoAttr    "clinical_notes"     "Notes"),          # Multiline / unlimited
    (New-IntAttr     "clinical_count"     "Count"),          # Integer
    (New-DecAttr     "clinical_score"     "Score" 0 1 4),    # Decimal min/max/precision
    (New-BoolAttr    "clinical_active"    "Active"),         # Yes/No
    (New-DtAttr      "clinical_date"      "Date" "DateOnly"),# Date only (or "DateAndTime")
    (New-PickAttr    "clinical_status"    "Status" @("Open","Closed","Pending")), # Choice — values start at 100000000
    (New-EmailAttr   "clinical_email"     "Email Address")   # Email format
)

$tableId = New-DvTable `
    -SchemaName       "clinical_MyTable" `
    -DisplayName      "My Table" `
    -DisplayPluralName "My Tables" `
    -Columns          $cols
```

## Adding a lookup (N:1 relationship) to an existing table

```powershell
Add-DvLookup `
    -FromTable              "clinical_documentsubmission" `
    -ToTable                "clinical_clinicalsite" `
    -LookupSchemaName       "clinical_clinicalsiteid" `
    -DisplayName            "Clinical Site" `
    -RelationshipSchemaName "clinical_clinicalsite_documentsubmission"
```

## Adding columns to an existing table (after creation)

Post individually to `EntityDefinitions(LogicalName='...')/Attributes`:

```powershell
$h = Get-DvHeaders
$col = New-StrAttr "clinical_newfield" "New Field" 100
Invoke-RestMethod -Method Post `
    -Uri "$script:Base/EntityDefinitions(LogicalName='clinical_mytable')/Attributes" `
    -Headers $h -Body ($col | ConvertTo-Json -Depth 10)
```

## Choice field values

Options are assigned values starting at `100000000` in declaration order. Document this in CLAUDE.md when you create new choice columns.

## Important rules

- Schema names must be unique. Check first: `GET /api/data/v9.2/EntityDefinitions?$select=LogicalName`
- All tables are automatically added to the `FastTrackOnboarding` solution.
- The `New-DvTable` function reads `OData-EntityId` from the response header — do not use `Invoke-RestMethod` for table creation (it discards headers); use `Invoke-WebRequest`.
- After creation, verify with: `GET /api/data/v9.2/EntityDefinitions(LogicalName='...')?$select=LogicalName,MetadataId`
