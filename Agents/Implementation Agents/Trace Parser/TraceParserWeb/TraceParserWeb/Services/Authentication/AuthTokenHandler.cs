using System.Net.Http.Headers;
using Microsoft.Identity.Web;

namespace TraceParserWeb.Services.Authentication
{
    internal class AuthTokenHandler(
        IHttpContextAccessor httpContextAccessor,
        ITokenAcquisition tokenAcquisition,
        CopilotScope copilotScope,
        CopilotDestinationPolicy destinations,
        ILogger<AuthTokenHandler> logger)
        : DelegatingHandler
    {
        private readonly string _defaultScope = copilotScope.Value;

        /// <summary>
        /// Per-circuit scope override. Set this before CopilotClient calls to use a
        /// different scope than the default (e.g., when switching agents at runtime).
        /// </summary>
        internal static readonly AsyncLocal<string?> ScopeOverride = new();

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            // This also covers pre-authorized requests and SDK response-derived URLs.
            destinations.ValidateDestination(request.RequestUri);

            if (request.Headers.Authorization is null)
            {
                var context = httpContextAccessor.HttpContext
                    ?? throw new InvalidOperationException("No HttpContext available");

                if (context.User.Identity?.IsAuthenticated != true)
                {
                    throw new InvalidOperationException("User is not authenticated");
                }

                try
                {
                    var scope = ScopeOverride.Value ?? _defaultScope;
                    var accessToken = await tokenAcquisition
                        .GetAccessTokenForUserAsync(new[] { scope });

                    request.Headers.Authorization =
                        new AuthenticationHeaderValue("Bearer", accessToken);
                }
                catch (MicrosoftIdentityWebChallengeUserException ex)
                {
                    logger.LogWarning(ex, "Token acquisition failed - user needs to re-authenticate");
                    throw new InvalidOperationException("Session expired. Please sign out and sign back in.");
                }
            }

            var response = await base.SendAsync(request, cancellationToken);
            if ((int)response.StatusCode is >= 300 and < 400)
            {
                var status = response.StatusCode;
                response.Dispose();
                throw new HttpRequestException("Copilot Studio redirects are not supported.", null, status);
            }
            return response;
        }
    }

    internal static class CopilotStudioHttpClientRegistration
    {
        internal static IServiceCollection AddCopilotStudioHttpClient(this IServiceCollection services)
        {
            services.AddScoped<AuthTokenHandler>();
            services.AddHttpClient("mcs")
                // Redirects in the transport do not re-enter AuthTokenHandler.
                .ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler { AllowAutoRedirect = false })
                .AddHttpMessageHandler<AuthTokenHandler>();
            return services;
        }
    }
}