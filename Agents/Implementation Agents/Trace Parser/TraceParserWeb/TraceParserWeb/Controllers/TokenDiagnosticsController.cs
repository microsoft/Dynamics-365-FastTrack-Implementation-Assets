using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Caching.Distributed;
using Microsoft.Identity.Web;

namespace TraceParserWeb.Controllers
{
    /// <summary>
    /// Diagnostic controller to verify token acquisition and refresh token status.
    /// Use this in development to confirm your token configuration is working.
    /// 
    /// IMPORTANT: Remove or secure this controller in production!
    /// </summary>
    [Authorize]
    [Route("api/[controller]")]
    [ApiController]
    public class TokenDiagnosticsController : ControllerBase
    {
        private readonly ITokenAcquisition _tokenAcquisition;
        private readonly IDistributedCache _cache;
        private readonly ILogger<TokenDiagnosticsController> _logger;
        private readonly string _copilotScope;

        public TokenDiagnosticsController(
            ITokenAcquisition tokenAcquisition,
            IDistributedCache cache,
            CopilotScope copilotScope,
            ILogger<TokenDiagnosticsController> logger)
        {
            _tokenAcquisition = tokenAcquisition;
            _cache = cache;
            _copilotScope = copilotScope.Value;
            _logger = logger;
        }

        /// <summary>
        /// Check current token status and attempt to acquire a new token.
        /// This will use the refresh token if the access token is expired.
        /// </summary>
        [HttpGet("status")]
        public async Task<IActionResult> GetTokenStatus()
        {
            var diagnostics = new TokenDiagnostics
            {
                UserName = User.Identity?.Name ?? "Unknown",
                IsAuthenticated = User.Identity?.IsAuthenticated ?? false,
                CheckTime = DateTimeOffset.UtcNow,
                RequestedScope = _copilotScope
            };

            try
            {
                // Attempt to acquire token - this will use refresh token if access token expired
                var accessToken = await _tokenAcquisition.GetAccessTokenForUserAsync(
                    new[] { _copilotScope });

                diagnostics.TokenAcquired = true;
                diagnostics.TokenLength = accessToken?.Length ?? 0;

                // Parse JWT to get expiration (without validation)
                if (!string.IsNullOrEmpty(accessToken))
                {
                    var tokenInfo = ParseJwtPayload(accessToken);
                    diagnostics.TokenExpiration = tokenInfo.Expiration;
                    diagnostics.TokenIssuedAt = tokenInfo.IssuedAt;
                    diagnostics.TimeUntilExpiration = tokenInfo.Expiration.HasValue
                        ? tokenInfo.Expiration.Value - DateTimeOffset.UtcNow
                        : null;
                }

                _logger.LogInformation(
                    "Token acquired successfully for {User}. Expires: {Expiration}",
                    diagnostics.UserName,
                    diagnostics.TokenExpiration);
            }
            catch (MicrosoftIdentityWebChallengeUserException ex)
            {
                diagnostics.TokenAcquired = false;
                diagnostics.Error = "Token acquisition failed - user needs to re-authenticate";
                diagnostics.ErrorDetails = ex.Message;
                diagnostics.NeedsReauthentication = true;

                _logger.LogWarning(ex, "Token acquisition failed for {User}", diagnostics.UserName);
            }
            catch (Exception ex)
            {
                diagnostics.TokenAcquired = false;
                diagnostics.Error = "Token acquisition failed";
                diagnostics.ErrorDetails = ex.Message;

                _logger.LogError(ex, "Unexpected error during token acquisition for {User}", diagnostics.UserName);
            }

            // Check cookie-based cache status
            diagnostics.CacheType = _cache.GetType().Name;

            return Ok(diagnostics);
        }

        /// <summary>
        /// Force a token refresh by acquiring a new token.
        /// Useful for testing the refresh flow.
        /// </summary>
        [HttpGet("refresh")]
        public async Task<IActionResult> ForceRefresh()
        {
            try
            {
                // Force token refresh by setting ForceRefresh option
                var accessToken = await _tokenAcquisition.GetAccessTokenForUserAsync(
                    new[] { _copilotScope },
                    tokenAcquisitionOptions: new TokenAcquisitionOptions
                    {
                        ForceRefresh = true
                    });

                var tokenInfo = ParseJwtPayload(accessToken);

                _logger.LogInformation(
                    "Token forcefully refreshed for {User}. New expiration: {Expiration}",
                    User.Identity?.Name,
                    tokenInfo.Expiration);

                return Ok(new
                {
                    Success = true,
                    Message = "Token refreshed successfully",
                    NewExpiration = tokenInfo.Expiration,
                    IssuedAt = tokenInfo.IssuedAt
                });
            }
            catch (MicrosoftIdentityWebChallengeUserException ex)
            {
                _logger.LogWarning(ex, "Force refresh failed - no valid refresh token");

                return Ok(new
                {
                    Success = false,
                    Message = "Refresh token is invalid or expired. User needs to re-authenticate.",
                    Error = ex.Message
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Force refresh failed");

                return StatusCode(500, new
                {
                    Success = false,
                    Message = "Token refresh failed",
                    Error = ex.Message
                });
            }
        }

        private static (DateTimeOffset? Expiration, DateTimeOffset? IssuedAt) ParseJwtPayload(string token)
        {
            try
            {
                var parts = token.Split('.');
                if (parts.Length != 3) return (null, null);

                var payload = parts[1];
                // Add padding if needed
                payload = payload.PadRight(payload.Length + (4 - payload.Length % 4) % 4, '=');
                var jsonBytes = Convert.FromBase64String(payload);
                var json = System.Text.Encoding.UTF8.GetString(jsonBytes);

                using var doc = System.Text.Json.JsonDocument.Parse(json);
                var root = doc.RootElement;

                DateTimeOffset? exp = null;
                DateTimeOffset? iat = null;

                if (root.TryGetProperty("exp", out var expElement))
                {
                    exp = DateTimeOffset.FromUnixTimeSeconds(expElement.GetInt64());
                }

                if (root.TryGetProperty("iat", out var iatElement))
                {
                    iat = DateTimeOffset.FromUnixTimeSeconds(iatElement.GetInt64());
                }

                return (exp, iat);
            }
            catch
            {
                return (null, null);
            }
        }

        private class TokenDiagnostics
        {
            public string UserName { get; set; } = "";
            public bool IsAuthenticated { get; set; }
            public DateTimeOffset CheckTime { get; set; }
            public string RequestedScope { get; set; } = "";
            public bool TokenAcquired { get; set; }
            public int TokenLength { get; set; }
            public DateTimeOffset? TokenExpiration { get; set; }
            public DateTimeOffset? TokenIssuedAt { get; set; }
            public TimeSpan? TimeUntilExpiration { get; set; }
            public string? Error { get; set; }
            public string? ErrorDetails { get; set; }
            public bool NeedsReauthentication { get; set; }
            public string CacheType { get; set; } = "";
        }
    }
}