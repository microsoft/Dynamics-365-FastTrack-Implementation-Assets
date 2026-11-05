using Microsoft.AspNetCore.Antiforgery;

namespace TraceParserWeb.Services;

public static class RegisteredImportEndpoints
{
    public static void MapRegisteredImports(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost("/api/imports", async (RegisterImportRequest request, HttpContext context,
            IAntiforgery antiforgery, RegisteredImportService imports, CancellationToken ct) =>
        {
            context.Response.Headers.CacheControl = "no-store";
            try
            {
                imports.RequireTenant(context.User);
                await antiforgery.ValidateRequestAsync(context);
                return Results.Ok(await imports.RegisterAsync(context.User, request.SessionName, request.FileName, ct));
            }
            catch (UnauthorizedAccessException) { return Results.Forbid(); }
            catch (UploadAdmissionHeldException)
            {
                context.Response.Headers.RetryAfter = "60";
                return Results.Problem(UploadAdmissionHeldException.MessageText, statusCode: StatusCodes.Status503ServiceUnavailable);
            }
            catch (AntiforgeryValidationException) { return Results.BadRequest("A valid anti-forgery token is required."); }
            catch (ArgumentException) { return Results.BadRequest("A valid session name and ETL filename are required."); }
        }).RequireAuthorization();

        endpoints.MapGet("/api/imports/{id:guid}", async (Guid id, HttpContext context,
            RegisteredImportService imports, CancellationToken ct) =>
        {
            context.Response.Headers.CacheControl = "no-store";
            try { return Results.Ok(await imports.GetAsync(context.User, id, ct)); }
            catch (UnauthorizedAccessException) { return Results.Forbid(); }
            catch (ArgumentException) { return Results.BadRequest("A valid import receipt is required."); }
        }).RequireAuthorization();
    }
}

public sealed record RegisterImportRequest(string SessionName, string FileName);
