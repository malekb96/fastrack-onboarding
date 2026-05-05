---
name: pp-webresource
description: >
  Create, update, and deploy JavaScript or HTML web resources to Dataverse for use in
  Model-Driven App forms, ribbons, and dialogs. Use this skill whenever the user asks to
  add JavaScript to a form, create a web resource, build a ribbon command, add a custom
  button, write form OnLoad/OnSave/OnChange logic, create an HTML dialog, or style a
  Model-Driven App. Triggers on: "add JS to form", "create web resource", "form script",
  "ribbon button", "custom dialog", "OnLoad handler", "web resource for...".
---

# pp-webresource — Create & Deploy Web Resources

## Step-by-step

1. **Understand what's needed**: form script (OnLoad/OnSave/OnChange), ribbon command, or HTML dialog.
2. **Generate the code** using the templates below.
3. **Deploy** with `Deploy-DvWebResource` from the module.
4. **Verify**: published web resources appear immediately in model-driven app forms.

## Naming convention

```
clinical_/js/kt_<tablename>_form.js       ← Form scripts
clinical_/js/kt_<tablename>_commands.js   ← Ribbon command handlers
clinical_/html/kt_<name>_dialog.html      ← HTML dialogs
clinical_/css/kt_<name>.css              ← Stylesheets
```

## Deploy

```powershell
Import-Module .\tools\PowerPlatform.psm1

# From a file path:
Deploy-DvWebResource `
    -Name        "clinical_/js/kt_documentsubmission_form.js" `
    -DisplayName "Document Submission Form Script" `
    -Type        "JavaScript" `
    -Content     ".\templates\webresources\kt_documentsubmission_form.js"

# Or from a string directly:
Deploy-DvWebResource `
    -Name        "clinical_/js/kt_test.js" `
    -DisplayName "Test Script" `
    -Type        "JavaScript" `
    -Content     "var KT = KT || {}; KT.Test = { onLoad: function(ctx) { console.log('loaded'); } };"
```

The function automatically creates-or-updates and publishes.

## JavaScript form script template

```javascript
// Namespace pattern — always use to avoid global conflicts
var KT = KT || {};
KT.DocumentForm = (function () {
    "use strict";

    // ── OnLoad ──────────────────────────────────────────────────────────────
    function onLoad(executionContext) {
        var formContext = executionContext.getFormContext();
        // Lock AI-generated fields so users can't accidentally overwrite them
        lockAiFields(formContext);
        showComplianceNotification(formContext);
        setConditionalVisibility(formContext);
    }

    // ── Field locking ────────────────────────────────────────────────────────
    function lockAiFields(formContext) {
        ["clinical_compliancestatus", "clinical_aiconfidencescore",
         "clinical_aisummary", "clinical_extractedjson"].forEach(function (f) {
            var ctrl = formContext.getControl(f);
            if (ctrl) ctrl.setDisabled(true);
        });
    }

    // ── Notifications ────────────────────────────────────────────────────────
    function showComplianceNotification(formContext) {
        var attr = formContext.getAttribute("clinical_compliancestatus");
        if (!attr) return;
        formContext.ui.clearFormNotification("kt_compliance_notice");
        var val = attr.getValue();
        // Replace 100000001 / 100000002 with your actual option values
        if (val === 100000001) {
            formContext.ui.setFormNotification(
                "This document is Non-Compliant. Review anomalies before taking action.",
                "ERROR", "kt_compliance_notice");
        } else if (val === 100000002) {
            formContext.ui.setFormNotification(
                "This document requires human review.",
                "WARNING", "kt_compliance_notice");
        }
    }

    // ── Conditional visibility ───────────────────────────────────────────────
    function setConditionalVisibility(formContext) {
        var decision = formContext.getAttribute("clinical_reviewerdecision");
        var comments = formContext.getControl("clinical_reviewercomments");
        if (!decision || !comments) return;
        // Show reviewer comments only when Override is selected (100000003)
        comments.setVisible(decision.getValue() === 100000003);
    }

    // ── OnChange handlers ────────────────────────────────────────────────────
    function onReviewerDecisionChange(executionContext) {
        var formContext = executionContext.getFormContext();
        setConditionalVisibility(formContext);
        var decision = formContext.getAttribute("clinical_reviewerdecision");
        var comments = formContext.getAttribute("clinical_reviewercomments");
        if (!decision || !comments) return;
        comments.setRequiredLevel(decision.getValue() === 100000003 ? "required" : "none");
    }

    function onComplianceStatusChange(executionContext) {
        showComplianceNotification(executionContext.getFormContext());
    }

    // ── OnSave ───────────────────────────────────────────────────────────────
    function onSave(executionContext) {
        var formContext = executionContext.getFormContext();
        var eventArgs  = executionContext.getEventArgs();
        var decision  = formContext.getAttribute("clinical_reviewerdecision");
        var comments  = formContext.getAttribute("clinical_reviewercomments");
        if (!decision || !comments) return;
        // Block save if Override selected without sufficient reviewer comment
        if (decision.getValue() === 100000003) {
            var txt = comments.getValue();
            if (!txt || txt.trim().length < 10) {
                eventArgs.preventDefault();
                formContext.ui.setFormNotification(
                    "Reviewer comments are required (min 10 chars) when overriding the AI decision.",
                    "ERROR", "kt_override_required");
            } else {
                formContext.ui.clearFormNotification("kt_override_required");
            }
        }
    }

    // ── Ribbon command: trigger manual AI audit ──────────────────────────────
    async function requestManualAiAudit(primaryControl) {
        var formContext = primaryControl;
        var recordId = formContext.data.entity.getId();
        if (!recordId) {
            Xrm.Navigation.openAlertDialog({ text: "Save the record before requesting an AI audit." });
            return;
        }
        var result = await Xrm.Navigation.openConfirmDialog(
            { title: "Run AI Audit", text: "Request a new AI audit for this document?" },
            { height: 200, width: 450 });
        if (!result.confirmed) return;
        Xrm.Utility.showProgressIndicator("Requesting AI audit…");
        try {
            await Xrm.WebApi.updateRecord(
                "clinical_documentsubmission",
                recordId.replace(/[{}]/g, ""),
                { clinical_manualauditrequested: true, clinical_processingstatus: 100000000 });
            Xrm.Utility.closeProgressIndicator();
            await Xrm.Navigation.openAlertDialog({ text: "AI audit requested. Status will update shortly." });
            formContext.data.refresh(false);
        } catch (err) {
            Xrm.Utility.closeProgressIndicator();
            Xrm.Navigation.openErrorDialog({ message: "Failed: " + err.message });
        }
    }

    // ── Public API ────────────────────────────────────────────────────────────
    return {
        onLoad:                    onLoad,
        onSave:                    onSave,
        onReviewerDecisionChange:  onReviewerDecisionChange,
        onComplianceStatusChange:  onComplianceStatusChange,
        requestManualAiAudit:      requestManualAiAudit
    };
})();
```

## HTML dialog template

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Dialog</title>
  <style>
    body { font-family: "Segoe UI", sans-serif; margin: 16px; color: #333; }
    h2   { font-size: 16px; margin-bottom: 12px; }
    .btn { padding: 8px 16px; border: none; border-radius: 3px; cursor: pointer; margin-right: 8px; }
    .btn-primary { background: #0078d4; color: #fff; }
    .btn-secondary { background: #eee; color: #333; }
  </style>
</head>
<body>
  <h2 id="title">Dialog Title</h2>
  <p id="message">Dialog message goes here.</p>
  <div style="margin-top:20px">
    <button class="btn btn-primary"   onclick="confirm()">Confirm</button>
    <button class="btn btn-secondary" onclick="cancel()">Cancel</button>
  </div>
  <script>
    // Receive data from parent form
    var data = {};
    try { data = JSON.parse(window.location.search.replace('?data=','')); } catch(e){}

    function confirm() {
      // Return result to parent form
      Xrm.Page.close({ result: "confirmed", data: data });
    }
    function cancel() {
      Xrm.Page.close({ result: "cancelled" });
    }

    // Open this dialog from a form/ribbon:
    // Xrm.Navigation.navigateTo(
    //   { pageType: "webresource", webresourceName: "clinical_/html/kt_mydialog.html",
    //     data: JSON.stringify({ recordId: recordId }) },
    //   { target: 2, position: 1, width: { value: 500, unit: "px" }, height: { value: 400, unit: "px" } }
    // ).then(function(result) { console.log(result); });
  </script>
</body>
</html>
```

## Event registration in maker portal

After deploying, register events on the form in Power Apps maker:
| Event | Handler function |
|---|---|
| Form OnLoad | `KT.DocumentForm.onLoad` |
| Form OnSave | `KT.DocumentForm.onSave` |
| Field OnChange (Reviewer Decision) | `KT.DocumentForm.onReviewerDecisionChange` |
| Field OnChange (Compliance Status) | `KT.DocumentForm.onComplianceStatusChange` |
| Ribbon command | `KT.DocumentForm.requestManualAiAudit` |

Pass execution context: check "Pass execution context as first parameter" for all events except ribbon commands.

## Known pitfalls

See `learnings/pitfalls.md` — relevant sections:
- **Guard every `getControl` / `getAttribute` call** — controls may not exist on all form views; always null-check
- **Clear notifications before setting them** — stale notifications persist; always call `clearFormNotification` first
- **Hardcoded secrets in committed files** — never put CLIENT_SECRET or tokens in JS files
