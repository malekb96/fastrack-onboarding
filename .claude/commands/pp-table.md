---
description: Create a new Dataverse table with columns and relationships in the FastTrackOnboarding solution
---

Use the **pp-table** skill to create a Dataverse table.

Ask the user for:
1. Table display name (singular + plural)
2. Schema prefix (default: `clinical_`)
3. Columns needed — name, type, and any constraints
4. Any lookup relationships to existing tables

Then scaffold and run the PowerShell using `tools/PowerPlatform.psm1`.
