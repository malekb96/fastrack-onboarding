---
name: pp-plugin
description: >
  Scaffold, build, and register a C# Dataverse plugin (IPlugin) for the FastTrackOnboarding
  solution via the SPN API. Use this skill whenever the user asks to create a plugin, add
  server-side business logic that runs on Dataverse events, build a pre/post operation handler,
  implement custom validation, or register a plugin step. Triggers on: "create a plugin",
  "add server-side logic", "pre-operation handler", "PostOperation plugin", "register plugin step",
  "C# plugin for...", "write a Dataverse plugin".
---

# pp-plugin — Scaffold & Register C# Dataverse Plugins

## Step-by-step

1. **Understand the step**: which table, which message (Create/Update/Delete/etc.), which stage (Pre/Post), sync or async.
2. **Scaffold the project** using the templates below.
3. **Build** with `dotnet build -c Release`.
4. **Register** using `Register-DvPlugin` from the module.

## Project layout

```
plugins/
└── <PluginName>/
    ├── <PluginName>.csproj
    ├── PluginBase.cs          ← tracing + org service helpers
    ├── <PluginName>.cs        ← business logic
    └── steps.json             ← step registration metadata
```

## .csproj template

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net462</TargetFramework>
    <AssemblyName>KT.FastTrack.<PluginName></AssemblyName>
    <RootNamespace>KT.FastTrack</RootNamespace>
    <Optimize>true</Optimize>
    <SignAssembly>false</SignAssembly>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.CrmSdk.CoreAssemblies" Version="9.0.2.52" />
  </ItemGroup>
</Project>
```

## PluginBase.cs

```csharp
using Microsoft.Xrm.Sdk;
using System;

namespace KT.FastTrack
{
    public abstract class PluginBase : IPlugin
    {
        protected string UnsecureConfig { get; }
        protected string SecureConfig   { get; }

        protected PluginBase(string unsecureConfig = null, string secureConfig = null)
        {
            UnsecureConfig = unsecureConfig;
            SecureConfig   = secureConfig;
        }

        public void Execute(IServiceProvider serviceProvider)
        {
            var context  = (IPluginExecutionContext)serviceProvider.GetService(typeof(IPluginExecutionContext));
            var tracer   = (ITracingService)serviceProvider.GetService(typeof(ITracingService));
            var factory  = (IOrganizationServiceFactory)serviceProvider.GetService(typeof(IOrganizationServiceFactory));
            var orgSvc   = factory.CreateOrganizationService(context.UserId);

            try
            {
                ExecutePlugin(context, orgSvc, tracer);
            }
            catch (InvalidPluginExecutionException)
            {
                throw;
            }
            catch (Exception ex)
            {
                tracer.Trace($"Unhandled exception: {ex}");
                throw new InvalidPluginExecutionException($"An error occurred: {ex.Message}", ex);
            }
        }

        protected abstract void ExecutePlugin(
            IPluginExecutionContext context,
            IOrganizationService    orgSvc,
            ITracingService         tracer);
    }
}
```

## Plugin.cs template

```csharp
using Microsoft.Xrm.Sdk;
using Microsoft.Xrm.Sdk.Query;

namespace KT.FastTrack
{
    // Stage 20 = PreOperation (can modify inputs, runs sync)
    // Stage 40 = PostOperation (read final state, can run async)
    public class DocumentSubmissionPreCreate : PluginBase
    {
        public DocumentSubmissionPreCreate(string unsecure = null, string secure = null)
            : base(unsecure, secure) { }

        protected override void ExecutePlugin(
            IPluginExecutionContext context,
            IOrganizationService    orgSvc,
            ITracingService         tracer)
        {
            if (context.MessageName != "Create") return;
            if (context.Stage != 20) return;  // PreOperation

            tracer.Trace("DocumentSubmissionPreCreate: start");

            // Target entity from the execution context
            var target = (Entity)context.InputParameters["Target"];

            // Example: set a default value before the record is written
            if (!target.Contains("clinical_processingstatus"))
                target["clinical_processingstatus"] = new OptionSetValue(100000000); // Pending

            tracer.Trace("DocumentSubmissionPreCreate: end");
        }
    }
}
```

## steps.json — step registration metadata

```json
[
  {
    "PluginTypeName": "KT.FastTrack.DocumentSubmissionPreCreate",
    "MessageName":    "Create",
    "EntityLogicalName": "clinical_documentsubmission",
    "Stage":          20,
    "Mode":           0,
    "Rank":           1,
    "FilterAttributes": "",
    "Description":    "Sets default processing status before record creation"
  }
]
```

Stage values: `10`=PreValidation, `20`=PreOperation, `40`=PostOperation  
Mode values:  `0`=Synchronous, `1`=Asynchronous (only valid for Stage 40)  
FilterAttributes: comma-separated logical names — step fires only when those fields change (Update only)

## Build

```powershell
dotnet build plugins\<PluginName>\<PluginName>.csproj -c Release
# Output: plugins\<PluginName>\bin\Release\net462\KT.FastTrack.<PluginName>.dll
```

Requires .NET SDK ≥ 6 and a `net462` targeting pack installed.

## Register via PowerShell

```powershell
Import-Module .\tools\PowerPlatform.psm1

# Reads steps.json, registers assembly + type(s) + step(s), adds to solution
$dllPath = "plugins\<PluginName>\bin\Release\net462\KT.FastTrack.<PluginName>.dll"
$steps   = Get-Content "plugins\<PluginName>\steps.json" | ConvertFrom-Json

Register-DvPlugin `
    -AssemblyPath    $dllPath `
    -AssemblyName    "KT.FastTrack.<PluginName>" `
    -Steps           $steps
```

`Register-DvPlugin` automatically:
- Creates or updates the `pluginassemblies` record (base64-encodes the DLL)
- Creates `plugintypes` for each class found in steps.json
- Resolves `sdkmessage` + `sdkmessagefilter` GUIDs
- Creates `sdkmessageprocessingsteps`
- Adds assembly + steps to `FastTrackOnboarding` solution

## Update an existing plugin (redeploy after code change)

```powershell
Import-Module .\tools\PowerPlatform.psm1

Update-DvPlugin `
    -AssemblyId   "GUID-FROM-CLAUDE.md" `
    -AssemblyPath "plugins\<PluginName>\bin\Release\net462\KT.FastTrack.<PluginName>.dll"
```

## Common patterns

### Read a related record
```csharp
var submission = orgSvc.Retrieve(
    "clinical_documentsubmission",
    target.GetAttributeValue<EntityReference>("clinical_submissionid").Id,
    new ColumnSet("clinical_documentname", "clinical_processingstatus"));
```

### Query multiple records
```csharp
var query = new QueryExpression("clinical_documentanomaly")
{
    ColumnSet = new ColumnSet("clinical_anomalydescription", "clinical_isblocking"),
    Criteria  = new FilterExpression()
};
query.Criteria.AddCondition("clinical_documentsubmissionid", ConditionOperator.Equal, submissionId);
var results = orgSvc.RetrieveMultiple(query).Entities;
```

### Throw a user-visible validation error
```csharp
throw new InvalidPluginExecutionException("Document name cannot be empty.");
```

### Access pre-image (Update only — must be registered with pre-image)
```csharp
var preImage = context.PreEntityImages["PreImage"];
var oldStatus = preImage.GetAttributeValue<OptionSetValue>("clinical_processingstatus")?.Value;
```

## After deployment

Save steps.json and the assembly GUID to CLAUDE.md so future sessions can update rather than re-register.

## Known pitfalls

See `learnings/pitfalls.md` — relevant sections:
- **Always inherit `PluginBase`** — direct `IPlugin` implementations miss tracing and exception wrapping
- **Use `context.UserId` for org service** — `null` gives system-level access that bypasses security roles
- **Stage 20 for validation/defaults, Stage 40 for side-effects** — mixing them causes unpredictable behavior
- **`net462` target required** — Dataverse plugin registration rejects assemblies targeting other frameworks
