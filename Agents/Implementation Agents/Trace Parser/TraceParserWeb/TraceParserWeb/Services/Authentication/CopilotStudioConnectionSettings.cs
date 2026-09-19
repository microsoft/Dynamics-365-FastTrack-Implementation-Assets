using Microsoft.Agents.CopilotStudio.Client;
using Microsoft.Agents.CopilotStudio.Client.Discovery;

namespace TraceParserWeb.Services.Authentication
{
    internal class CopilotStudioConnectionSettings : ConnectionSettings
    {
        internal CopilotStudioConnectionSettings(
            IConfigurationSection copilotConfig,
            IConfigurationSection azureAdConfig) : base(copilotConfig)
        {
            // The SDK skips these configuration values when DirectConnectUrl is set.
            // They must still pass the same server policy, including the cloud boundary.
            EnvironmentId = copilotConfig["EnvironmentId"];
            SchemaName = copilotConfig["SchemaName"];
            Cloud = copilotConfig.GetValue("Cloud", PowerPlatformCloud.Prod);
            CustomPowerPlatformCloud = copilotConfig["CustomPowerPlatformCloud"];
            UseExperimentalEndpoint = copilotConfig.GetValue<bool>("UseExperimentalEndpoint");
            CopilotDestinationPolicy.ValidateSettings(this);
            TenantId = azureAdConfig["TenantId"]
                       ?? throw new ArgumentException("TenantId not found in AzureAd config");
            AppClientId = azureAdConfig["ClientId"]
                          ?? throw new ArgumentException("ClientId not found in AzureAd config");
            AppClientSecret = azureAdConfig["ClientSecret"];
            UseS2SConnection = copilotConfig.GetValue<bool>("UseS2SConnection", false);
        }

        internal static CopilotStudioConnectionSettings ForAgent(
            IConfiguration configuration, string environmentId, string schemaName)
        {
            using var agentConfiguration = new ConfigurationManager();
            agentConfiguration.AddConfiguration(configuration);
            agentConfiguration.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["CopilotStudio:EnvironmentId"] = environmentId,
                ["CopilotStudio:SchemaName"] = schemaName,
                // A server default direct URL must not override the selected agent.
                ["CopilotStudio:DirectConnectUrl"] = null
            });
            return new CopilotStudioConnectionSettings(
                agentConfiguration.GetSection("CopilotStudio"),
                configuration.GetSection("AzureAd"));
        }

        public string TenantId { get; }
        public string AppClientId { get; }
        public string? AppClientSecret { get; }
        public bool UseS2SConnection { get; }
    }
}
