using Microsoft.Agents.CopilotStudio.Client;

namespace TraceParserWeb.Services.Authentication
{
    internal class CopilotStudioConnectionSettings(
        IConfigurationSection copilotConfig,
        IConfigurationSection azureAdConfig)
        : ConnectionSettings(copilotConfig)
    {
        public string TenantId { get; } = azureAdConfig["TenantId"]
                                          ?? throw new ArgumentException("TenantId not found in AzureAd config");

        public string AppClientId { get; } = azureAdConfig["ClientId"]
                                             ?? throw new ArgumentException("ClientId not found in AzureAd config");

        public string? AppClientSecret { get; } = azureAdConfig["ClientSecret"];
        public bool UseS2SConnection { get; } = copilotConfig.GetValue<bool>("UseS2SConnection", false);
    }
}
