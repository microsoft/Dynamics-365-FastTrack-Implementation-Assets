using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Azure.Identity;
using Microsoft.Extensions.Configuration;
using StoreMonitoringAlertFunction.Models;

namespace StoreMonitoringAlertFunction.Services;

public sealed class AgentFlowClient
{
    private readonly HttpClient _httpClient;
    private readonly Uri _flowUri;
    private readonly Uri _tokenUri;
    private readonly string _clientId;
    private readonly string _clientSecret;
    private readonly string _tokenScope;

    public AgentFlowClient(HttpClient httpClient, IConfiguration configuration)
    {
        _httpClient = httpClient;

        var flowUrl = GetRequiredSetting(configuration, "AgentFlow:FlowUrl");
        var tenantId = GetRequiredSetting(configuration, "AgentFlow:TenantId");
        var clientId = GetRequiredSetting(configuration, "AgentFlow:ClientId");
        var clientSecret = GetRequiredSetting(configuration, "AgentFlow:ClientSecret");
        var tokenScope = configuration["AgentFlow:TokenScope"] ?? "https://service.flow.microsoft.com/.default";

        _flowUri = new Uri(flowUrl, UriKind.Absolute);
        _tokenUri = new Uri($"https://login.microsoftonline.com/{tenantId}/oauth2/v2.0/token", UriKind.Absolute);
        _clientId = clientId;
        _clientSecret = clientSecret;
        _tokenScope = NormalizeScope(tokenScope);
    }

    public async Task<AgentFlowResult> SendAlertAsync(
        string alertPayload,
        CancellationToken cancellationToken)
    {
        var accessToken = await GetAccessTokenAsync(cancellationToken);

        using var request = new HttpRequestMessage(HttpMethod.Post, _flowUri)
        {
            Content = new StringContent(alertPayload, Encoding.UTF8, "application/json")
        };

        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

        using var response = await _httpClient.SendAsync(request, cancellationToken);
        var responseBody = await response.Content.ReadAsStringAsync(cancellationToken);

        return new AgentFlowResult(response.StatusCode, responseBody);
    }

    private async Task<string> GetAccessTokenAsync(CancellationToken cancellationToken)
    {
        using var tokenRequest = new HttpRequestMessage(HttpMethod.Post, _tokenUri)
        {
            Content = new FormUrlEncodedContent(new Dictionary<string, string>
            {
                ["client_id"] = _clientId,
                ["client_secret"] = _clientSecret,
                ["scope"] = _tokenScope,
                ["grant_type"] = "client_credentials"
            })
        };

        using var tokenResponse = await _httpClient.SendAsync(tokenRequest, cancellationToken);

        if (!tokenResponse.IsSuccessStatusCode)
        {
            throw new AuthenticationFailedException($"Token request failed with status {(int)tokenResponse.StatusCode}.");
        }

        var responseBody = await tokenResponse.Content.ReadAsStringAsync(cancellationToken);

        using var tokenJson = JsonDocument.Parse(responseBody);

        if (!tokenJson.RootElement.TryGetProperty("access_token", out var accessTokenElement))
        {
            throw new AuthenticationFailedException("Token response did not include an access_token value.");
        }

        return accessTokenElement.GetString()
            ?? throw new AuthenticationFailedException("Token response included an empty access_token value.");
    }

    private static string NormalizeScope(string tokenScope)
    {
        var trimmedScope = tokenScope.Trim();

        return trimmedScope.EndsWith("/.default", StringComparison.OrdinalIgnoreCase)
            ? trimmedScope
            : $"{trimmedScope.TrimEnd('/')}/.default";
    }

    private static string GetRequiredSetting(IConfiguration configuration, string key)
    {
        var value = configuration[key];

        if (string.IsNullOrWhiteSpace(value))
        {
            throw new InvalidOperationException($"Missing required configuration setting '{key}'.");
        }

        return value;
    }
}