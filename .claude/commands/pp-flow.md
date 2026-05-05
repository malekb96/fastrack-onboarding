---
description: Create and deploy a Power Automate cloud flow to the FastTrackOnboarding Dataverse solution
---

Use the **pp-flow** skill to create a Power Automate flow.

Ask the user for:
1. Trigger type — Dataverse row event, Outlook email, Recurrence, or manual
2. Main logic and tables involved
3. Whether it calls AI Builder
4. Flow display name

Then generate the Logic Apps JSON, save it to `flows/`, and deploy via `Deploy-DvFlow` from `tools/PowerPlatform.psm1`.

Remember: never use `api.flow.microsoft.com` — always create flows via the Dataverse `workflows` entity.
