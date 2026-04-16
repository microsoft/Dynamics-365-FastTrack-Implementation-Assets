using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authentication.OpenIdConnect;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Identity.Web;

namespace TraceParserWeb.Controllers;

[Route("[controller]/[action]")]
public class AccountController : Controller
{
    [HttpGet]
    public new IActionResult SignOut()
    {
        return SignOut(
            new AuthenticationProperties { RedirectUri = "/" },
            CookieAuthenticationDefaults.AuthenticationScheme,
            OpenIdConnectDefaults.AuthenticationScheme);
    }

    /// <summary>
    /// Triggers incremental consent for the Dataverse scope.
    /// Uses a separate Challenge with ONLY the Dataverse scope to avoid
    /// AADSTS70011 (.default can't be combined with resource-specific scopes).
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> ConsentDataverse(
        [FromQuery] string? envUrl,
        [FromQuery] string? returnUrl,
        [FromServices] ITokenAcquisition tokenAcquisition)
    {
        if (string.IsNullOrEmpty(envUrl))
            return Redirect(returnUrl ?? "/agent-editor");

        var scope = $"https://{envUrl}/user_impersonation";

        try
        {
            // Try silent token acquisition first — works if admin consent is already granted
            await tokenAcquisition.GetAccessTokenForUserAsync(new[] { scope });
            return Redirect(returnUrl ?? "/agent-editor");
        }
        catch (MicrosoftIdentityWebChallengeUserException)
        {
            // Trigger incremental consent by issuing a Challenge with ONLY the Dataverse
            // + OIDC scopes. Setting the "scope" parameter REPLACES the default scopes
            // (which include the Copilot Studio .default scope) in the authorize request.
            var properties = new AuthenticationProperties
            {
                RedirectUri = returnUrl ?? "/agent-editor"
            };
            properties.SetParameter("scope",
                $"openid profile offline_access {scope}");
            properties.SetParameter("login_hint",
                User.FindFirst("preferred_username")?.Value);

            return Challenge(properties, OpenIdConnectDefaults.AuthenticationScheme);
        }
    }
}