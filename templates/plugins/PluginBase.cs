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
