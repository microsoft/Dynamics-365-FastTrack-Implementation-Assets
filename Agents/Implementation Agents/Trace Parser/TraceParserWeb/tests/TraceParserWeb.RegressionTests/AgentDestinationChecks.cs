#pragma warning disable BL0006
using System.Net;
using System.Net.Http.Headers;
using System.Reflection;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.Agents.CopilotStudio.Client;
using Microsoft.Agents.CopilotStudio.Client.Discovery;
using Microsoft.Agents.Core.Models;
using Microsoft.AspNetCore.Components;
using Microsoft.AspNetCore.Components.Rendering;
using Microsoft.AspNetCore.Components.RenderTree;
using Microsoft.AspNetCore.Components.Web;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Http;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Identity.Web;
using Microsoft.JSInterop;
using TraceParserWeb.Components.Pages.Chat;
using TraceParserWeb.Services;
using TraceParserWeb.Services.Authentication;

static class AgentDestinationChecks
{
    const string EnvironmentId = "11111111-2222-3333-4444-555555555555";
    const string Host = "111111112222333344445555555555.55.environment.api.powerplatform.com";
    const string Endpoint = "https://" + Host + "/copilotstudio/dataverse-backed/authenticated/bots/synthetic/conversations";
    const string Scope = "https://api.powerplatform.com/.default";

    public static async Task<int> RunAsync()
    {
        var passed = 0;
        foreach (var invalid in new[] { "", " ", "abc", "attacker.example/abc", "//attacker.example/abc",
            "https://attacker.example/abc", "attacker.example\\abc", "attacker.example?abc", "attacker.example#abc",
            "attacker.example:443/abc", "user@attacker.example/abc", "%2f%2fattacker.example", "%252f",
            EnvironmentId + "/x", EnvironmentId + ".attacker.example", EnvironmentId + "@attacker.example",
            EnvironmentId.Insert(12, "\r\n"), "{" + EnvironmentId + "}", EnvironmentId.Replace("-", ""),
            "Default-attacker.example/abc", "Default-Default-" + EnvironmentId, "Default-" + EnvironmentId + "%2f" })
        {
            Check(!CopilotDestinationPolicy.TryNormalizeEnvironmentId(invalid, out _), "Invalid environment ID accepted");
            var config = Configuration(invalid);
            Throws<ArgumentException>(() => Startup(config));
            Throws<ArgumentException>(() => CopilotStudioConnectionSettings.ForAgent(Configuration(), invalid, "synthetic"));
            passed++;
        }
        foreach (var input in new[] { EnvironmentId, " " + EnvironmentId + " ", "DEFAULT-" + EnvironmentId,
            " ABCDEFAB-CDEF-ABCD-EFAB-CDEFABCDEFAB " })
        {
            Check(CopilotDestinationPolicy.TryNormalizeEnvironmentId(input, out var canonical), "Valid environment rejected");
            var startup = Startup(Configuration(input));
            var runtime = CopilotStudioConnectionSettings.ForAgent(Configuration(), input, " synthetic ");
            Check(startup.EnvironmentId == canonical && runtime.EnvironmentId == canonical &&
                runtime.SchemaName == "synthetic", "Startup/runtime normalization differs");
            Check(runtime.TenantId == startup.TenantId && runtime.AppClientId == startup.AppClientId &&
                runtime.AppClientSecret == startup.AppClientSecret, "Switching changed the server identity boundary");
            Check(CopilotClient.ScopeFromSettings(startup) == Scope && CopilotClient.ScopeFromSettings(runtime) == Scope,
                "Default token audience changed");
            passed++;
        }

        foreach (var option in new[] {
            ("Cloud", "Local"), ("Cloud", "Other"), ("Cloud", "Unknown"),
            ("Cloud", "999"), ("CustomPowerPlatformCloud", "https://attacker.example"),
            ("UseExperimentalEndpoint", "true") })
        {
            var config = Configuration(extra: new() { [option.Item1] = option.Item2 });
            Throws<ArgumentException>(() => Startup(config));
            Throws<ArgumentException>(() => CopilotStudioConnectionSettings.ForAgent(config, EnvironmentId, "synthetic"));
            Throws<ArgumentException>(() => Startup(Configuration(extra: new() {
                [option.Item1] = option.Item2, ["DirectConnectUrl"] = Endpoint })));
            passed++;
        }
        {
            var directOnly = Configuration(extra: new() {
                ["EnvironmentId"] = null, ["SchemaName"] = null, ["DirectConnectUrl"] = Endpoint });
            Check(Startup(directOnly).DirectConnectUrl == Endpoint, "Trusted direct-only configuration rejected");
            Throws<InvalidOperationException>(() => Startup(Configuration(extra: new() {
                ["DirectConnectUrl"] = Endpoint, ["Cloud"] = "High" })));
            passed++;
        }
        foreach (var direct in new[] { "https://attacker.example", "http://" + Host, "https://" + Host + ":444/",
            "https://user@" + Host, "https://" + Host + ".attacker.example", "/relative",
            "https://api.powerplatform.com/", "https://anything.environment.api.powerplatform.com/" })
        {
            if (direct == "/relative")
                Throws<ArgumentException>(() => Startup(Configuration(extra: new() { ["DirectConnectUrl"] = direct })));
            else
                Throws<InvalidOperationException>(() => Startup(Configuration(extra: new() { ["DirectConnectUrl"] = direct })));
            passed++;
        }
        {
            var config = Configuration(extra: new() { ["DirectConnectUrl"] = Endpoint });
            Check(Startup(config).DirectConnectUrl == Endpoint, "Trusted direct URL rejected");
            var switched = CopilotStudioConnectionSettings.ForAgent(config, "Default-" + EnvironmentId, "new_agent");
            Check(string.IsNullOrEmpty(switched.DirectConnectUrl) && switched.SchemaName == "new_agent",
                "Server default direct URL overrode agent switching");
            passed++;
        }

        var blockedUris = new Uri?[] {
            null, new("/relative", UriKind.Relative), new("https://attacker.example/abc"),
            new("http://" + Host), new("https://" + Host + ":444/"),
            new("https://user:synthetic@" + Host), new("https://" + Host + "@attacker.example"),
            new("https://" + Host + ".attacker.example"), new("https://evil" + Host),
            new("https://" + Host + "./"), new("https://" + Host + "/#fragment"),
            new("https://localhost"), new("https://127.0.0.1"), new("https://[::1]"),
            new("https://2130706433"), new("https://169.254.169.254/metadata/identity/oauth2/token"),
            new("https://environment.api.powerplatform.com"), new("https://api.powerplatform.com"),
            new("https://fake.environment.api.powerplatform.com"), new("https://powerplatform.com.attacker.example"),
            new("https://111111112222333344445555555555.55.environment.api.powerplatform.com.evil"),
            new("https://1111111122223333444455555555555.5.environment.api.high.powerplatform.microsoft.us"),
            new("https://111111112222333344445555555555.55.environment.api.powerplatform.cоm")
        };
        foreach (var malformed in new[] { "https://" + Host + "\\@attacker.example",
            "https://%61ttacker.example/", "https://" + Host + "%2f@attacker.example",
            "https://" + Host + "%00.attacker.example/" })
        {
            if (Uri.TryCreate(malformed, UriKind.Absolute, out var uri))
                Throws<InvalidOperationException>(() => new CopilotDestinationPolicy(null).ValidateDestination(uri));
            passed++;
        }
        foreach (var uri in blockedUris)
        foreach (var preauthorized in new[] { false, true })
        {
            using var transport = new AgentTransport();
            var tokens = Tokens();
            using var handler = Handler(tokens, transport);
            using var http = new HttpMessageInvoker(handler);
            using var request = new HttpRequestMessage(HttpMethod.Get, uri);
            if (preauthorized) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", "synthetic-existing");
            await ThrowsAsync<InvalidOperationException>(() => http.SendAsync(request, default));
            Check(tokens.Calls == 0 && transport.Requests.Count == 0, "Blocked destination reached token acquisition or transport");
            Check(preauthorized || request.Headers.Authorization is null, "Blocked destination acquired an authorization header");
            passed++;
        }
        foreach (var preauthorized in new[] { false, true })
        {
            using var transport = new AgentTransport();
            var tokens = Tokens();
            using var handler = Handler(tokens, transport);
            using var http = new HttpMessageInvoker(handler);
            using var request = new HttpRequestMessage(HttpMethod.Post, "https://" + Host.ToUpperInvariant() + ":443/activities");
            if (preauthorized) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", "synthetic-existing");
            using var response = await http.SendAsync(request, default);
            Check(transport.Requests.Count == 1 && transport.Authorized &&
                tokens.Calls == (preauthorized ? 0 : 1), "Valid request was not sent with authorization");
            if (!preauthorized) Check(tokens.Scopes.SequenceEqual(new[] { Scope }), "Default token scope changed");
            passed++;
        }
        {
            using var transport = new AgentTransport();
            var tokens = Tokens();
            using var handler = Handler(tokens, transport, authenticated: false);
            using var http = new HttpMessageInvoker(handler);
            using var request = new HttpRequestMessage(HttpMethod.Post, Endpoint);
            await ThrowsAsync<InvalidOperationException>(() => http.SendAsync(request, default));
            Check(tokens.Calls == 0 && transport.Requests.Count == 0, "Unauthenticated request was sent");
            passed++;
        }
        {
            using var transport = new AgentTransport();
            var tokens = Tokens();
            using var handler = Handler(tokens, transport);
            using var http = new HttpMessageInvoker(handler);
            AuthTokenHandler.ScopeOverride.Value = "synthetic-circuit-scope";
            try
            {
                using var request = new HttpRequestMessage(HttpMethod.Post, Endpoint);
                using var response = await http.SendAsync(request, default);
                Check(tokens.Scopes.Single() == "synthetic-circuit-scope", "Circuit scope override changed");
            }
            finally { AuthTokenHandler.ScopeOverride.Value = null; }
            passed++;
        }

        // Exercise the real named registration. Inspect redirect policy before replacing
        // ONLY its transport with an offline responder; no DNS/socket calls can occur.
        foreach (var status in new[] { 301, 302, 303, 307, 308 })
        foreach (var target in new[] { Endpoint + "/next", "https://attacker.example/redirect" })
        {
            using var transport = new AgentTransport { Response = () =>
            {
                var response = new HttpResponseMessage((HttpStatusCode)status);
                response.Headers.Location = new Uri(target);
                return response;
            }};
            var tokens = Tokens();
            var filter = new OfflineAgentTransport(transport);
            using var services = Services(tokens, filter);
            using var http = services.GetRequiredService<IHttpClientFactory>().CreateClient("mcs");
            await ThrowsAsync<HttpRequestException>(() => http.GetAsync(Endpoint));
            Check(filter.RedirectsDisabled && transport.Requests.Count == 1 && tokens.Calls == 1,
                "Redirect followed or bypassed named pipeline policy");
            passed++;
        }

        // Contract tests use the actual pinned SDK, not a copy of its URL builder.
        foreach (var cloud in Enum.GetValues<PowerPlatformCloud>()
            .Where(c => c is not (PowerPlatformCloud.Local or PowerPlatformCloud.Other or PowerPlatformCloud.Unknown)))
        foreach (var id in new[] { EnvironmentId, "Default-" + EnvironmentId })
        {
            var config = Configuration(id, new() { ["Cloud"] = cloud.ToString() });
            var settings = Startup(config);
            var switched = CopilotStudioConnectionSettings.ForAgent(config, id, "switched_agent");
            Check(switched.Cloud == cloud && CopilotClient.ScopeFromSettings(switched) == CopilotClient.ScopeFromSettings(settings),
                "Switching lost configured cloud or changed audience");
            using var transport = new AgentTransport();
            var tokens = Tokens();
            var scope = CopilotClient.ScopeFromSettings(settings);
            using var handler = Handler(tokens, transport, cloud: cloud, scope: scope);
            var sdk = new CopilotClient(settings, new AgentHttpFactory(handler), NullLogger.Instance, "mcs");
            await Drain(sdk.StartConversationAsync());
            await Drain(sdk.AskQuestionAsync("offline", "synthetic-conversation", default));
            await Drain(sdk.SendActivityAsync(new Activity { Type = "message", Text = "offline",
                Conversation = new ConversationAccount { Id = "synthetic-conversation" } }, default));
            Check(transport.Requests.Count == 3 && tokens.Calls == 3 &&
                transport.Requests.All(uri => uri.AbsolutePath.StartsWith("/copilotstudio/dataverse-backed/authenticated/bots/")),
                "SDK start/activity/stream requests did not pass destination policy");
            Check(tokens.Scopes.Single() == scope, "Configured cloud token scope changed");
            var directSettings = Startup(Configuration(id, new() {
                ["Cloud"] = cloud.ToString(), ["DirectConnectUrl"] = transport.Requests[0].AbsoluteUri }));
            Check(CopilotClient.ScopeFromSettings(directSettings) == scope, "Direct endpoint changed configured cloud audience");
            var directClient = new CopilotClient(directSettings, new AgentHttpFactory(handler), NullLogger.Instance, "mcs");
            await Drain(directClient.StartConversationAsync());
            Check(transport.Requests.Count == 4, "Trusted SDK direct URL was not sent");
            passed++;
        }
        foreach (var returned in new[] { Endpoint, "https://attacker.example/returned-stream" })
        {
            var allowed = returned == Endpoint;
            using var transport = new AgentTransport { ReturnedEndpoint = returned };
            var tokens = Tokens();
            using var handler = Handler(tokens, transport);
            var sdkSettings = Startup(Configuration());
            // Bypass the first layer deliberately to exercise SDK-returned URL handling.
            sdkSettings.UseExperimentalEndpoint = true;
            var sdk = new CopilotClient(sdkSettings, new AgentHttpFactory(handler), NullLogger.Instance, "mcs");
            await Drain(sdk.StartConversationAsync());
            if (allowed) await Drain(sdk.AskQuestionAsync("offline", "synthetic-conversation", default));
            else await ThrowsAsync<InvalidOperationException>(() => Drain(sdk.AskQuestionAsync("offline", "synthetic-conversation", default)));
            Check(tokens.Calls == (allowed ? 2 : 1) && transport.Requests.Count == tokens.Calls,
                "SDK response-derived URL bypassed guard or blocked trusted activity URL");
            passed++;
        }
        {
            using var transport = new AgentTransport();
            var tokens = Tokens();
            using var handler = Handler(tokens, transport);
            var unvalidated = new ConnectionSettings { EnvironmentId = "attacker.example/abc", SchemaName = "synthetic" };
            var sdk = new CopilotClient(unvalidated, new AgentHttpFactory(handler), NullLogger.Instance, "mcs");
            await ThrowsAsync<InvalidOperationException>(() => Drain(sdk.StartConversationAsync()));
            Check(tokens.Calls == 0 && transport.Requests.Count == 0, "Original SDK injection escaped the independent guard");
            passed++;
        }
        passed += await ProfileChecks();
        return passed;
    }

    static async Task<int> ProfileChecks()
    {
        var passed = 0;
        foreach (var id in new[] { "attacker.example/abc", EnvironmentId, "DEFAULT-" + EnvironmentId })
        {
            var js = new AgentJs { Profiles = JsonSerializer.Serialize(new[] {
                new { Name = "legacy", EnvironmentId = id, SchemaName = "synthetic",
                    TenantId = "untrusted-legacy-tenant", ClientId = "untrusted-legacy-client",
                    ClientSecret = "synthetic-legacy-secret" } }) };
            using var transport = new AgentTransport();
            var tokens = Tokens();
            using var handler = Handler(tokens, transport);
            var factory = new AgentHttpFactory(handler);
            var chatClient = new CopilotStudioIChatClient(new CopilotClient(
                Startup(Configuration()), factory, NullLogger.Instance, "mcs"));
            using var page = new Chat();
            Set(page, "JS", js);
            Set(page, "Configuration", Configuration());
            Set(page, "LoggerFactory", NullLoggerFactory.Instance);
            Set(page, "HttpClientFactory", factory);
            Set(page, "CopilotStudioClient", chatClient);
            var input = new ChatInput();
            Set(input, "textArea", new ElementReference("offline", new WebElementReferenceContext(js)));
            Set(page, "chatInput", input);
            await (Task)Invoke(page, "OpenAgentSelector")!;
            var profiles = (List<Chat.AgentProfile>)Get(page, "savedAgentProfiles")!;
            Check(profiles.Single().EnvironmentId == id, "Legacy profile did not load");
            Invoke(page, "SelectAgentProfile", profiles.Single());
            await (Task)Invoke(page, "ConnectToAgent")!;
            if (id.StartsWith("attacker", StringComparison.Ordinal))
            {
                Check(js.Saves == 0 && chatClient.ActiveAgentName is null && tokens.Calls == 0 &&
                    transport.Requests.Count == 0, "Malicious saved profile saved or connected");
                using var builder = new RenderTreeBuilder();
                Invoke(page, "BuildRenderTree", builder);
                var frames = builder.GetFrames();
                Check(frames.Array.Take(frames.Count).Any(frame => frame.FrameType == RenderTreeFrameType.Text &&
                    frame.TextContent.Contains("GUID", StringComparison.Ordinal)), "Validation feedback was not rendered");
            }
            else
            {
                Check(js.Saves == 1 && chatClient.ActiveAgentName == "legacy", "Valid legacy agent could not switch");
                using var saved = JsonDocument.Parse(js.Profiles!);
                var profile = saved.RootElement[0];
                Check(profile.EnumerateObject().Count() == 3 && !profile.TryGetProperty("ClientSecret", out _),
                    "Legacy authentication fields survived saving");
                Check(profile.GetProperty("EnvironmentId").GetString() ==
                    (id.StartsWith("DEFAULT", StringComparison.Ordinal) ? "Default-" : "") + EnvironmentId,
                    "Saved environment was not canonical");
            }
            passed++;
        }
        {
            using var page = new Chat();
            Set(page, "editEnvironmentId", EnvironmentId);
            Set(page, "editSchemaName", " ");
            await (Task)Invoke(page, "ConnectToAgent")!;
            Check((string?)Get(page, "agentValidationError") == "Enter an agent Schema Name.",
                "Missing schema silently rejected");
            passed++;
        }
        return passed;
    }

    static IConfiguration Configuration(string id = EnvironmentId, Dictionary<string, string?>? extra = null)
    {
        var values = new Dictionary<string, string?> {
            ["CopilotStudio:EnvironmentId"] = id, ["CopilotStudio:SchemaName"] = "synthetic",
            ["AzureAd:TenantId"] = "22222222-2222-2222-2222-222222222222",
            ["AzureAd:ClientId"] = "33333333-3333-3333-3333-333333333333",
            ["AzureAd:ClientSecret"] = "synthetic-server-credential"
        };
        foreach (var pair in extra ?? []) values["CopilotStudio:" + pair.Key] = pair.Value;
        return new ConfigurationBuilder().AddInMemoryCollection(values).Build();
    }

    static CopilotStudioConnectionSettings Startup(IConfiguration config) =>
        new(config.GetSection("CopilotStudio"), config.GetSection("AzureAd"));
    static SyntheticAgentTokens Tokens() => (SyntheticAgentTokens)DispatchProxy.Create<ITokenAcquisition, SyntheticAgentTokens>();
    static IHttpContextAccessor Context(bool authenticated = true) => new HttpContextAccessor {
        HttpContext = new DefaultHttpContext { User = new ClaimsPrincipal(new ClaimsIdentity(
            [new Claim("tid", "22222222-2222-2222-2222-222222222222")], authenticated ? "synthetic" : null)) }
    };
    static AuthTokenHandler Handler(SyntheticAgentTokens tokens, AgentTransport transport,
        bool authenticated = true, PowerPlatformCloud? cloud = null, string scope = Scope) =>
        new(Context(authenticated), (ITokenAcquisition)tokens, new CopilotScope(scope),
            new CopilotDestinationPolicy(cloud), NullLogger<AuthTokenHandler>.Instance) { InnerHandler = transport };
    static ServiceProvider Services(SyntheticAgentTokens tokens, OfflineAgentTransport filter) =>
        new ServiceCollection().AddLogging()
            .AddSingleton(Context()).AddSingleton((ITokenAcquisition)tokens)
            .AddSingleton(new CopilotScope(Scope)).AddSingleton(new CopilotDestinationPolicy(null))
            .AddSingleton<IHttpMessageHandlerBuilderFilter>(filter).AddCopilotStudioHttpClient().BuildServiceProvider();
    static async Task Drain(IAsyncEnumerable<IActivity> activities)
    {
        await foreach (var _ in activities) { }
    }
    static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
    }
    static void Throws<T>(Action action) where T : Exception
    {
        try { action(); }
        catch (T) { return; }
        throw new Exception($"Expected {typeof(T).Name}");
    }
    static async Task ThrowsAsync<T>(Func<Task> action) where T : Exception
    {
        try { await action(); }
        catch (T) { return; }
        throw new Exception($"Expected {typeof(T).Name}");
    }
    const BindingFlags Members = BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public;
    static void Set(object instance, string name, object value)
    {
        if (instance.GetType().GetField(name, Members) is { } field) field.SetValue(instance, value);
        else instance.GetType().GetProperty(name, Members)!.SetValue(instance, value);
    }
    static object? Get(object instance, string name) => instance.GetType().GetField(name, Members)!.GetValue(instance);
    static object? Invoke(object instance, string name, params object[] args) =>
        instance.GetType().GetMethod(name, Members)!.Invoke(instance, args);
}

public class SyntheticAgentTokens : DispatchProxy
{
    public int Calls { get; private set; }
    public string[] Scopes { get; private set; } = [];
    protected override object? Invoke(MethodInfo? targetMethod, object?[]? args)
    {
        if (targetMethod?.Name != nameof(ITokenAcquisition.GetAccessTokenForUserAsync))
            throw new NotSupportedException("Unexpected token method");
        Calls++;
        Scopes = ((IEnumerable<string>)args![0]!).ToArray();
        return Task.FromResult("offline-synthetic-token");
    }
}

sealed class AgentTransport : HttpMessageHandler
{
    public List<Uri> Requests { get; } = [];
    public bool Authorized { get; private set; }
    public string? ReturnedEndpoint { get; init; }
    public Func<HttpResponseMessage>? Response { get; init; }
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        Requests.Add(request.RequestUri!);
        Authorized = request.Headers.Authorization is not null;
        var response = Response?.Invoke() ?? new HttpResponseMessage(HttpStatusCode.OK) {
            Content = new StringContent("event: activity\ndata: {\"type\":\"message\",\"text\":\"offline\",\"conversation\":{\"id\":\"synthetic-conversation\"}}\n\n",
                System.Text.Encoding.UTF8, "text/event-stream")
        };
        response.Headers.TryAddWithoutValidation("x-ms-conversationid", "synthetic-conversation");
        if (ReturnedEndpoint is not null)
            response.Headers.TryAddWithoutValidation("x-ms-d2e-experimental", ReturnedEndpoint);
        return Task.FromResult(response);
    }
}

sealed class AgentHttpFactory(HttpMessageHandler handler) : IHttpClientFactory
{
    public HttpClient CreateClient(string name) => name == "mcs"
        ? new HttpClient(handler, disposeHandler: false)
        : throw new InvalidOperationException("Unexpected SDK client name");
}

sealed class OfflineAgentTransport(AgentTransport transport) : IHttpMessageHandlerBuilderFilter
{
    public bool RedirectsDisabled { get; private set; }
    public Action<HttpMessageHandlerBuilder> Configure(Action<HttpMessageHandlerBuilder> next) => builder =>
    {
        next(builder);
        RedirectsDisabled = builder.PrimaryHandler is HttpClientHandler { AllowAutoRedirect: false };
        builder.PrimaryHandler.Dispose();
        builder.PrimaryHandler = transport;
    };
}

sealed class AgentJs : IJSRuntime
{
    public string? Profiles { get; set; }
    public int Saves { get; private set; }
    public ValueTask<TValue> InvokeAsync<TValue>(string identifier, object?[]? args) =>
        InvokeAsync<TValue>(identifier, default, args);
    public ValueTask<TValue> InvokeAsync<TValue>(string identifier, CancellationToken cancellationToken, object?[]? args)
    {
        if (identifier == "localStorage.getItem") return ValueTask.FromResult((TValue)(object)Profiles!);
        if (identifier == "localStorage.setItem") { Saves++; Profiles = (string)args![1]!; }
        else if (identifier != "Blazor._internal.domWrapper.focus")
            throw new NotSupportedException("Unexpected JS call");
        return ValueTask.FromResult(default(TValue)!);
    }
}
