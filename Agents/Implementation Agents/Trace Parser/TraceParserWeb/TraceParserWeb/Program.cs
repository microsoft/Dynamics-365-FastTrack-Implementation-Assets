using TraceParserWeb;
using TraceParserWeb.Components;
using TraceParserWeb.Services;
using TraceParserWeb.Services.Authentication;
using Microsoft.Agents.CopilotStudio.Client;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authentication.OpenIdConnect;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.AspNetCore.Components.Server;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.Caching.Distributed;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.Identity.Web;
using Microsoft.Identity.Web.UI;
using Azure.Storage.Blobs;
using Microsoft.Extensions.Options;

var builder = WebApplication.CreateBuilder(args);

// Data Protection: persist keys to Azure Blob + encrypt with Key Vault in production
if (builder.Environment.IsProduction())
{
    var blobUri = builder.Configuration["DataProtection:BlobUri"];
    var keyVaultKeyUri = builder.Configuration["DataProtection:KeyVaultKeyUri"];

    if (!string.IsNullOrEmpty(blobUri) && !string.IsNullOrEmpty(keyVaultKeyUri))
    {
        builder.Services.AddDataProtection()
            .PersistKeysToAzureBlobStorage(new Uri(blobUri), new Azure.Identity.DefaultAzureCredential())
            .ProtectKeysWithAzureKeyVault(new Uri(keyVaultKeyUri), new Azure.Identity.DefaultAzureCredential());
    }
    else
    {
        builder.Services.AddDataProtection();
    }
}
else
{
    builder.Services.AddDataProtection();
}

// Add Razor components
builder.Services.AddRazorComponents().AddInteractiveServerComponents();

// Build connection settings
var copilotSettings = new CopilotStudioConnectionSettings(
    builder.Configuration.GetSection("CopilotStudio"),
    builder.Configuration.GetSection("AzureAd"));

string copilotScope = CopilotClient.ScopeFromSettings(copilotSettings);

// Register the cookie-based distributed cache BEFORE authentication
builder.Services.AddHttpContextAccessor();

// Configure authentication with MSAL using our cookie-based distributed cache
builder.Services.AddAuthentication(OpenIdConnectDefaults.AuthenticationScheme)
    .AddMicrosoftIdentityWebApp(builder.Configuration.GetSection("AzureAd"))
    .EnableTokenAcquisitionToCallDownstreamApi(new[] { copilotScope })
    .AddDistributedTokenCaches();

builder.Services.Configure<CookieAuthenticationOptions>(CookieAuthenticationDefaults.AuthenticationScheme, options =>
{
    options.ExpireTimeSpan = TimeSpan.FromHours(8);
    options.SlidingExpiration = true;
});

// Add controllers with Microsoft Identity UI
builder.Services.AddControllersWithViews()
    .AddMicrosoftIdentityUI();

builder.Services.Configure<OpenIdConnectOptions>(
    OpenIdConnectDefaults.AuthenticationScheme, options =>
    {
        options.Scope.Add("offline_access");
        // Change the post-logout callback path
        options.SignedOutCallbackPath = "/signout-callback";
        // Redirect to main page after sign-out callback
        options.Events ??= new OpenIdConnectEvents();
        options.Events.OnSignedOutCallbackRedirect = context =>
        {
            context.HttpContext.Response.Redirect("/");
            context.HandleResponse();
            return Task.CompletedTask;
        };
    });

// Add authorization
builder.Services.AddAuthorization();
builder.Services.AddCascadingAuthenticationState();
builder.Services.AddScoped<AuthenticationStateProvider, ServerAuthenticationStateProvider>();

// Register settings and scope
builder.Services.AddSingleton(copilotSettings);
builder.Services.AddSingleton(new CopilotDestinationPolicy(copilotSettings.Cloud));
builder.Services.AddSingleton(new CopilotScope(copilotScope));
builder.Services.AddSingleton<IDistributedCache, CookieDistributedCache>();

// Register HttpClient for Copilot Studio with token handler
builder.Services.AddCopilotStudioHttpClient();

// Register CopilotClient
builder.Services.AddScoped<CopilotClient>(sp =>
{
    var logger = sp.GetRequiredService<ILoggerFactory>().CreateLogger<CopilotClient>();
    return new CopilotClient(copilotSettings, sp.GetRequiredService<IHttpClientFactory>(), logger, "mcs");
});

// Register CopilotStudioIChatClient
builder.Services.AddScoped<CopilotStudioIChatClient>(sp =>
{
    var copilotClient = sp.GetRequiredService<CopilotClient>();
    return new CopilotStudioIChatClient(copilotClient);
});

builder.Services.AddScoped<IChatClient>(sp => sp.GetRequiredService<CopilotStudioIChatClient>());

// Register ETL upload service
builder.Services.Configure<EtlImportOptions>(builder.Configuration.GetSection("EtlImport"));
builder.Services.AddScoped<EtlUploadService>();
builder.Services.AddScoped<TraceService>();
builder.Services.AddScoped<TraceDeletionService>();
builder.Services.AddScoped<TraceParser.Deletion.IDeletionJobStore>(_ =>
    new TraceParser.Deletion.SqlDeletionJobStore(builder.Configuration["DurableDeletion:WebSqlConnectionString"] ?? ""));
builder.Services.AddScoped<DeletionJobService>();
builder.Services.Configure<TraceAdministrationOptions>(builder.Configuration.GetSection("TraceAdministration"));
builder.Services.AddScoped<ITraceDeletionStore, SqlTraceDeletionStore>();
builder.Services.AddScoped<IRegisteredImportStore, SqlRegisteredImportStore>();
builder.Services.AddScoped<RegisteredImportService>();
builder.Services.AddHttpClient("dab", client =>
{
    var dabUrl = builder.Configuration["EtlImport:DabBaseUrl"] ?? "";
    if (!string.IsNullOrEmpty(dabUrl))
        client.BaseAddress = new Uri(dabUrl);
}).ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler { AllowAutoRedirect = false });

var app = builder.Build();

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error", createScopeForErrors: true);
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();

app.UseAuthentication();
app.UseAuthorization();

app.UseAntiforgery();

app.MapControllers();
app.MapRazorComponents<App>()
    .AddInteractiveServerRenderMode();

app.MapGet("/health", () => Results.Ok(new { status = "healthy" }));

// Registered uploads require tenant checks and anti-forgery validation, not a
// state-changing GET that hands out overwrite permissions for historical paths.
app.MapRegisteredImports();
app.MapDeletionJobs();

// Ensure the upload container exists at startup
using (var scope = app.Services.CreateScope())
{
    var opts = scope.ServiceProvider.GetRequiredService<IOptions<EtlImportOptions>>();
    if (!string.IsNullOrEmpty(opts.Value.StorageConnectionString))
    {
        var container = new BlobContainerClient(opts.Value.StorageConnectionString, opts.Value.ContainerName);
        container.CreateIfNotExists();
    }
}

app.Run();

public record CopilotScope(string Value);
