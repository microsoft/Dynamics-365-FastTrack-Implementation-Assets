using Microsoft.AspNetCore.Antiforgery;
using Microsoft.Data.SqlClient;

namespace TraceParserWeb.Services;

public static class DeletionJobEndpoints
{
    public static void MapDeletionJobs(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost("/api/deletion-jobs", (EnqueueDeletionRequest request, HttpContext context,
            IAntiforgery antiforgery, DeletionJobService jobs, CancellationToken ct) =>
            Handle(context, jobs, antiforgery, async () =>
                Results.Ok(await jobs.EnqueueAsync(context.User, request.RequestKey, request.TraceId, ct))))
            .RequireAuthorization();
        endpoints.MapGet("/api/deletion-jobs", (HttpContext context, DeletionJobService jobs, CancellationToken ct) =>
            Handle(context, jobs, null, async () => Results.Ok(await jobs.ReadAsync(context.User, null, ct))))
            .RequireAuthorization();
        endpoints.MapGet("/api/deletion-jobs/{id:guid}", (Guid id, HttpContext context, DeletionJobService jobs, CancellationToken ct) =>
            Handle(context, jobs, null, async () =>
            {
                var results = await jobs.ReadAsync(context.User, id, ct);
                return results.Count == 0 ? Results.NotFound() : Results.Ok(results[0]);
            })).RequireAuthorization();
        foreach (var action in new[] { "Cancel", "Resume" })
        {
            var verb = action;
            endpoints.MapPost($"/api/deletion-jobs/{{id:guid}}/{verb.ToLowerInvariant()}",
                (Guid id, HttpContext context, IAntiforgery antiforgery, DeletionJobService jobs, CancellationToken ct) =>
                Handle(context, jobs, antiforgery, async () =>
                    Results.Ok(await jobs.ControlAsync(context.User, id, verb, ct)))).RequireAuthorization();
        }
    }

    private static async Task<IResult> Handle(HttpContext context, DeletionJobService jobs,
        IAntiforgery? antiforgery, Func<Task<IResult>> action)
    {
        context.Response.Headers.CacheControl = "no-store";
        try
        {
            jobs.RequireIdentity(context.User);
            if (antiforgery is not null) await antiforgery.ValidateRequestAsync(context);
            return await action();
        }
        catch (UnauthorizedAccessException) { return Results.Forbid(); }
        catch (AntiforgeryValidationException) { return Results.BadRequest("A valid anti-forgery token is required."); }
        catch (ArgumentException) { return Results.BadRequest("Invalid deletion request."); }
        catch (InvalidOperationException) { return Results.Problem("Durable deletion is unavailable.", statusCode: 503); }
        catch (SqlException ex) when (ex.Number == 51203) { return Results.NotFound(); }
        catch (SqlException ex) when (ex.Number is 51130 or 51131 or 51201 or 51204 or 51206)
        { return Results.Conflict("Trace is absent, busy, ineligible, or already requested. Refresh your deletion jobs before retrying."); }
        catch (SqlException) { return Results.Problem("Deletion SQL is unavailable. No completion is inferred; refresh before retrying.", statusCode: 503); }
    }
}

public sealed record EnqueueDeletionRequest(Guid RequestKey, int TraceId);
