---
description: Scaffold, build, and register a C# Dataverse IPlugin for server-side business logic
---

Use the **pp-plugin** skill to create a C# Dataverse plugin.

Ask the user for:
1. Plugin class name and purpose
2. Target table (entity logical name)
3. Message — Create, Update, Delete, Retrieve, etc.
4. Stage — PreValidation (10), PreOperation (20), or PostOperation (40)
5. Mode — Synchronous (0) or Asynchronous (1)
6. FilterAttributes for Update steps (which fields trigger the step)

Then scaffold the project under `plugins/<PluginName>/`, build with `dotnet build -c Release`, and register via `Register-DvPlugin` from `tools/PowerPlatform.psm1`.
