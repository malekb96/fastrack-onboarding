---
description: Create and deploy a JavaScript or HTML web resource to Dataverse for use in Model-Driven App forms
---

Use the **pp-webresource** skill to create a web resource.

Ask the user for:
1. Type — form script (OnLoad/OnSave/OnChange), ribbon command handler, or HTML dialog
2. Target table/form name
3. Fields and logic needed

Then generate the code following the `KT.<TableName>Form` namespace pattern and deploy via `Deploy-DvWebResource` from `tools/PowerPlatform.psm1`.

Naming: `clinical_/js/kt_<tablename>_form.js` or `clinical_/html/kt_<name>_dialog.html`
