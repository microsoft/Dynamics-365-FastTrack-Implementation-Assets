using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Antiforgery;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.DependencyInjection;
using TraceParserWeb.Services;

internal static class DurableDeletionEndpointChecks
{
    public static async Task<int> RunAsync(DeletionJobService jobs, Guid tenant, Guid requester, Func<int> calls)
    {
        var antiforgery = new Antiforgery();
        using var provider = new ServiceCollection().AddLogging().AddRouting().AddSingleton(jobs)
            .AddSingleton<IAntiforgery>(antiforgery).AddSingleton<IAuthenticationService>(new Authentication()).BuildServiceProvider();
        var routes = new Routes(provider);
        routes.MapDeletionJobs();
        var endpoints = routes.DataSources.SelectMany(s => s.Endpoints).Cast<RouteEndpoint>().ToArray();
        var passed = 0;
        Check(endpoints.Length == 5 && endpoints.All(e => e.Metadata.GetMetadata<IAuthorizeData>() is not null),
            "Deletion endpoint authorization metadata missing");
        foreach (var endpoint in endpoints)
        {
            var before = calls();
            var post = endpoint.Metadata.GetMetadata<HttpMethodMetadata>()!.HttpMethods.Contains("POST");
            Check(await Invoke(endpoint, new ClaimsPrincipal(), post) == 403, "Anonymous job access accepted");
            Check(await Invoke(endpoint, User(Guid.NewGuid()), post) == 403, "Cross-tenant job access accepted");
            Check(calls() == before, "Rejected HTTP request reached the store");
            if (post)
            {
                antiforgery.Valid = false;
                Check(await Invoke(endpoint, User(tenant), true) == 400, "Mutation accepted invalid antiforgery");
                Check(calls() == before, "Missing antiforgery reached SQL");
            }
            antiforgery.Valid = true;
            Check(await Invoke(endpoint, User(tenant), post) == 200, "Authorized job endpoint failed");
        }
        return passed;

        ClaimsPrincipal User(Guid tid) => new(new ClaimsIdentity([
            new Claim("tid", tid.ToString()), new Claim("oid", requester.ToString())], "synthetic"));
        void Check(bool ok, string message) { if (!ok) throw new Exception(message); passed++; }
        async Task<int> Invoke(RouteEndpoint endpoint, ClaimsPrincipal user, bool post)
        {
            var context = new DefaultHttpContext { RequestServices = provider, User = user };
            context.Request.Method = post ? "POST" : "GET";
            context.Response.Body = new MemoryStream();
            context.Request.RouteValues["id"] = Guid.NewGuid().ToString();
            context.Features.Set<IHttpRequestBodyDetectionFeature>(new BodyFeature(post));
            if (post)
            {
                var bytes = Encoding.UTF8.GetBytes($$"""{"requestKey":"{{Guid.NewGuid()}}","traceId":1,"tenantId":"{{Guid.NewGuid()}}","requesterId":"{{Guid.NewGuid()}}"}""");
                context.Request.ContentType = "application/json";
                context.Request.ContentLength = bytes.Length;
                context.Request.Body = new MemoryStream(bytes);
            }
            await endpoint.RequestDelegate!(context);
            if (context.Response.Headers.CacheControl != "no-store") throw new Exception("Job HTTP response cacheable");
            return context.Response.StatusCode;
        }
    }
    sealed class Routes(IServiceProvider provider) : IEndpointRouteBuilder
    {
        public IServiceProvider ServiceProvider => provider;
        public ICollection<EndpointDataSource> DataSources { get; } = new List<EndpointDataSource>();
        public IApplicationBuilder CreateApplicationBuilder() => new ApplicationBuilder(provider);
    }
    sealed record BodyFeature(bool CanHaveBody) : IHttpRequestBodyDetectionFeature;
    sealed class Antiforgery : IAntiforgery
    {
        public bool Valid;
        public Task ValidateRequestAsync(HttpContext context) => Valid ? Task.CompletedTask :
            Task.FromException(new AntiforgeryValidationException("Synthetic missing token"));
        public Task<bool> IsRequestValidAsync(HttpContext context) => Task.FromResult(Valid);
        public AntiforgeryTokenSet GetAndStoreTokens(HttpContext context) => throw new NotSupportedException();
        public AntiforgeryTokenSet GetTokens(HttpContext context) => throw new NotSupportedException();
        public void SetCookieTokenAndHeader(HttpContext context) => throw new NotSupportedException();
    }
    sealed class Authentication : IAuthenticationService
    {
        public Task<AuthenticateResult> AuthenticateAsync(HttpContext context, string? scheme) => Task.FromResult(AuthenticateResult.NoResult());
        public Task ChallengeAsync(HttpContext context, string? scheme, AuthenticationProperties? properties)
        { context.Response.StatusCode = 401; return Task.CompletedTask; }
        public Task ForbidAsync(HttpContext context, string? scheme, AuthenticationProperties? properties)
        { context.Response.StatusCode = 403; return Task.CompletedTask; }
        public Task SignInAsync(HttpContext context, string? scheme, ClaimsPrincipal principal, AuthenticationProperties? properties) => throw new NotSupportedException();
        public Task SignOutAsync(HttpContext context, string? scheme, AuthenticationProperties? properties) => throw new NotSupportedException();
    }
}
