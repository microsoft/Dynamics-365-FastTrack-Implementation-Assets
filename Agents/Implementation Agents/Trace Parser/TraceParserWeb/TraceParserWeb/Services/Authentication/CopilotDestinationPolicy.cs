using System.Text.RegularExpressions;
using Microsoft.Agents.CopilotStudio.Client;
using Microsoft.Agents.CopilotStudio.Client.Discovery;

namespace TraceParserWeb.Services.Authentication;

internal sealed class CopilotDestinationPolicy
{
    internal const string EnvironmentIdError =
        "Enter an Environment ID in GUID or Default-GUID format, not a URL.";

    private readonly Regex trustedHost;

    internal CopilotDestinationPolicy(PowerPlatformCloud? cloud)
    {
        // SDK 1.3.176: commercial environments split the final two ID characters
        // into a DNS label; the other hosted clouds split the final character.
        var (suffix, split) = (cloud ?? PowerPlatformCloud.Prod) switch
        {
            PowerPlatformCloud.Prod or PowerPlatformCloud.FirstRelease => ("api.powerplatform.com", 2),
            PowerPlatformCloud.Exp => ("api.exp.powerplatform.com", 1),
            PowerPlatformCloud.Dev => ("api.dev.powerplatform.com", 1),
            PowerPlatformCloud.Test => ("api.test.powerplatform.com", 1),
            PowerPlatformCloud.Preprod => ("api.preprod.powerplatform.com", 1),
            PowerPlatformCloud.Prv => ("api.prv.powerplatform.com", 1),
            PowerPlatformCloud.Gov or PowerPlatformCloud.GovFR => ("api.gov.powerplatform.microsoft.us", 1),
            PowerPlatformCloud.High => ("api.high.powerplatform.microsoft.us", 1),
            PowerPlatformCloud.DoD => ("api.appsplatform.us", 1),
            PowerPlatformCloud.Mooncake => ("api.powerplatform.partner.microsoftonline.cn", 1),
            PowerPlatformCloud.Ex => ("api.powerplatform.eaglex.ic.gov", 1),
            PowerPlatformCloud.Rx => ("api.powerplatform.microsoft.scloud", 1),
            _ => throw new ArgumentException("This Power Platform cloud is not supported. Local and custom clouds are not allowed.")
        };
        trustedHost = new Regex(
            $@"\A(?:default)?[0-9a-f]{{{32 - split}}}\.[0-9a-f]{{{split}}}\.environment\.{Regex.Escape(suffix)}\z",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.NonBacktracking);
    }

    internal static bool TryNormalizeEnvironmentId(string? value, out string normalized)
    {
        normalized = "";
        var candidate = value?.Trim();
        if (candidate is null) return false;
        var isDefault = candidate.StartsWith("Default-", StringComparison.OrdinalIgnoreCase);
        var id = isDefault ? candidate["Default-".Length..] : candidate;
        if (id.Length != 36 || !Guid.TryParseExact(id, "D", out var guid)) return false;
        normalized = (isDefault ? "Default-" : "") + guid.ToString("D");
        return true;
    }

    internal static void ValidateSettings(ConnectionSettings settings)
    {
        var direct = !string.IsNullOrEmpty(settings.DirectConnectUrl);
        if (settings.EnvironmentId is not null || !direct)
        {
            if (!TryNormalizeEnvironmentId(settings.EnvironmentId, out var environmentId))
                throw new ArgumentException(EnvironmentIdError, nameof(settings.EnvironmentId));
            settings.EnvironmentId = environmentId;
        }

        if (settings.SchemaName is not null || !direct)
        {
            if (string.IsNullOrWhiteSpace(settings.SchemaName))
                throw new ArgumentException("Enter an agent Schema Name.", nameof(settings.SchemaName));
            settings.SchemaName = settings.SchemaName.Trim();
        }

        var policy = new CopilotDestinationPolicy(settings.Cloud);
        if (!string.IsNullOrEmpty(settings.CustomPowerPlatformCloud))
            throw new ArgumentException("Custom Power Platform endpoints are not supported.");
        if (settings.UseExperimentalEndpoint)
            throw new ArgumentException("Experimental island endpoints are not supported.");
        if (direct)
        {
            if (!Uri.TryCreate(settings.DirectConnectUrl, UriKind.Absolute, out var uri))
                throw new ArgumentException("DirectConnectUrl must be an absolute trusted Power Platform URL.");
            policy.ValidateDestination(uri);
        }
    }

    internal void ValidateDestination(Uri? uri)
    {
        if (uri is null || !uri.IsAbsoluteUri ||
            !uri.IsWellFormedOriginalString() || uri.Scheme != Uri.UriSchemeHttps || uri.Port != 443 ||
            uri.UserInfo.Length != 0 || uri.Fragment.Length != 0 ||
            uri.HostNameType != UriHostNameType.Dns || !trustedHost.IsMatch(uri.IdnHost))
        {
            // Do not echo untrusted URLs, query strings, or credentials in errors.
            throw new InvalidOperationException("The agent destination is not a trusted HTTPS Power Platform environment endpoint.");
        }
    }
}
