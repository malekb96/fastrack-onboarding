using Microsoft.Xrm.Sdk;
using Microsoft.Xrm.Sdk.Query;

namespace KT.FastTrack
{
    // Stage 20 = PreOperation (sync, can modify inputs)
    // Stage 40 = PostOperation (can run async)
    public class MyEntityPlugin : PluginBase
    {
        public MyEntityPlugin(string unsecure = null, string secure = null)
            : base(unsecure, secure) { }

        protected override void ExecutePlugin(
            IPluginExecutionContext context,
            IOrganizationService    orgSvc,
            ITracingService         tracer)
        {
            if (context.MessageName != "Create") return;
            if (context.Stage != 20) return;

            tracer.Trace("MyEntityPlugin: start");

            var target = (Entity)context.InputParameters["Target"];

            // Add business logic here
            // Example: set a default field value
            if (!target.Contains("clinical_myfield"))
                target["clinical_myfield"] = "default value";

            tracer.Trace("MyEntityPlugin: end");
        }
    }
}
