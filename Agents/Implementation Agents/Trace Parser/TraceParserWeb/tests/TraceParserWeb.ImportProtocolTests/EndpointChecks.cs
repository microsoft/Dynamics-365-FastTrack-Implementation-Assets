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

internal static class EndpointChecks
{
    public static async Task<int> Run(RegisteredImportService imports, string tenant, Guid id, Func<int> calls)
    {
        var antiforgery=new ProbeAntiforgery();
        using var provider=new ServiceCollection().AddLogging().AddRouting()
            .AddSingleton(imports).AddSingleton<IAntiforgery>(antiforgery)
            .AddSingleton<IAuthenticationService>(new ProbeHttpAuthentication()).BuildServiceProvider();
        var routes=new Routes(provider);
        routes.MapRegisteredImports();
        var endpoints=routes.DataSources.SelectMany(s=>s.Endpoints).Cast<RouteEndpoint>().ToList();
        var post=endpoints.Single(e=>e.RoutePattern.RawText=="/api/imports");
        var get=endpoints.Single(e=>e.RoutePattern.RawText=="/api/imports/{id:guid}");
        var passed=0;
        Check(endpoints.All(e=>e.Metadata.GetMetadata<IAuthorizeData>() is not null),"HTTP authorization metadata missing");
        var before=calls();
        Check(await Invoke(post,new ClaimsPrincipal(),"POST")==403,"Anonymous HTTP registration was not forbidden");
        Check(await Invoke(post,User(Guid.NewGuid().ToString()),"POST")==403,"Wrong-tenant HTTP registration was not forbidden");
        Check(calls()==before,"Denied HTTP registrations reached SQL/store");
        Check(await Invoke(get,User(Guid.NewGuid().ToString()),"GET")==403,"Wrong-tenant HTTP status was not forbidden");
        Check(await Invoke(post,User(tenant),"POST")==400,"HTTP registration accepted missing antiforgery validation");
        Check(calls()==before,"Failed antiforgery validation reached SQL/store");
        antiforgery.Valid=true;
        Check(await Invoke(post,User(tenant),"POST")==200 && calls()==before+1,
            "Authenticated tenant/antiforgery request did not register exactly once");
        Check(await Invoke(get,User(tenant),"GET")==200,"Authenticated HTTP status failed");
        return passed;

        ClaimsPrincipal User(string tid)=>new(new ClaimsIdentity([new Claim("tid",tid)],"synthetic"));
        void Check(bool ok,string message){if(!ok)throw new Exception(message);passed++;}
        async Task<int> Invoke(RouteEndpoint endpoint,ClaimsPrincipal user,string method)
        {
            var context=new DefaultHttpContext{RequestServices=provider,User=user};
            context.Request.Method=method;
            context.Request.Scheme="https";
            context.Request.Host=new HostString("synthetic.invalid");
            context.Response.Body=new MemoryStream();
            context.Request.RouteValues["id"]=id.ToString();
            context.Features.Set<IHttpRequestBodyDetectionFeature>(new BodyFeature(method=="POST"));
            if(method=="POST")
            {
                var bytes=Encoding.UTF8.GetBytes("""{"sessionName":"http fixture","fileName":"http-fixture.etl"}""");
                context.Request.ContentType="application/json";
                context.Request.ContentLength=bytes.Length;
                context.Request.Body=new MemoryStream(bytes);
            }
            await endpoint.RequestDelegate!(context);
            if(context.Response.Headers.CacheControl!="no-store")throw new Exception("Private HTTP response is cacheable");
            return context.Response.StatusCode;
        }
    }

    private sealed class Routes(IServiceProvider services):IEndpointRouteBuilder
    {
        public IServiceProvider ServiceProvider=>services;
        public ICollection<EndpointDataSource> DataSources{get;}=new List<EndpointDataSource>();
        public IApplicationBuilder CreateApplicationBuilder()=>new ApplicationBuilder(services);
    }
    private sealed record BodyFeature(bool CanHaveBody):IHttpRequestBodyDetectionFeature;
    private sealed class ProbeAntiforgery:IAntiforgery
    {
        public bool Valid;
        public Task ValidateRequestAsync(HttpContext context)=>Valid?Task.CompletedTask:
            Task.FromException(new AntiforgeryValidationException("Synthetic missing token"));
        public Task<bool> IsRequestValidAsync(HttpContext context)=>Task.FromResult(Valid);
        public AntiforgeryTokenSet GetAndStoreTokens(HttpContext context)=>throw new NotSupportedException();
        public AntiforgeryTokenSet GetTokens(HttpContext context)=>throw new NotSupportedException();
        public void SetCookieTokenAndHeader(HttpContext context)=>throw new NotSupportedException();
    }
    private sealed class ProbeHttpAuthentication:IAuthenticationService
    {
        public Task<AuthenticateResult> AuthenticateAsync(HttpContext context,string? scheme)=>Task.FromResult(AuthenticateResult.NoResult());
        public Task ChallengeAsync(HttpContext context,string? scheme,AuthenticationProperties? properties)
        {context.Response.StatusCode=401;return Task.CompletedTask;}
        public Task ForbidAsync(HttpContext context,string? scheme,AuthenticationProperties? properties)
        {context.Response.StatusCode=403;return Task.CompletedTask;}
        public Task SignInAsync(HttpContext context,string? scheme,ClaimsPrincipal principal,AuthenticationProperties? properties)=>throw new NotSupportedException();
        public Task SignOutAsync(HttpContext context,string? scheme,AuthenticationProperties? properties)=>throw new NotSupportedException();
    }
}
