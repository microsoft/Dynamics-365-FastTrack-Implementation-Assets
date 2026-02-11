using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Microsoft.Graph;
using Azure.Identity;
using Microsoft.Graph.Models;
using Microsoft.Graph.Users.Item.AssignLicense;
using Microsoft.Kiota.Abstractions;

namespace FieldService.Optimize25.VendorIntegration
{
    public class InviteVendorResource
    {
        private readonly ILogger<InviteVendorResource> _logger;
        private readonly GraphServiceClient _graphClient;

        public InviteVendorResource(ILogger<InviteVendorResource> logger)
        {
            _logger = logger;

            var credential = new ClientSecretCredential(
                Environment.GetEnvironmentVariable("TenantId"),
                Environment.GetEnvironmentVariable("ClientId"),
                Environment.GetEnvironmentVariable("ClientSecret"));

            _graphClient = new GraphServiceClient(credential);
        }

        [Function("InviteVendorResource")]
        public async Task<IActionResult> Run([HttpTrigger(AuthorizationLevel.Function, "post")] HttpRequest req)
        {
            try
            {
                _logger.LogInformation("Processing vendor invitation request.");

                string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
                var data = System.Text.Json.JsonSerializer.Deserialize<InvitationRequest>(requestBody);

                var invitation = new Invitation
                {
                    InvitedUserEmailAddress = data.Email,
                    InviteRedirectUrl = data.RedirectUrl ?? "https://microsoft.com",
                    SendInvitationMessage = true,
                    InvitedUserType = "Guest",
                    InvitedUserDisplayName = data.DisplayName
                };

                var result = await _graphClient.Invitations.PostAsync(invitation);

                _logger.LogInformation($"Invitation sent to {data.Email}");

                return new OkObjectResult(result);
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error processing vendor invitation: {ex.Message}");
                return new StatusCodeResult(StatusCodes.Status500InternalServerError);
            }
        }

        [Function("AssignUserLicense")]
        public async Task<IActionResult> AssignUserLicense([HttpTrigger(AuthorizationLevel.Function, "post")] HttpRequest req)
        {
            try
            {
                _logger.LogInformation("Processing license assignment request.");

                string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
                var data = System.Text.Json.JsonSerializer.Deserialize<LicenseAssignmentRequest>(requestBody);

                // Look up user by email, including usageLocation
                var users = await _graphClient.Users.GetAsync(config =>
                {
                    config.QueryParameters.Filter = $"mail eq '{data.Email}'";
                    config.QueryParameters.Select = new[] { "id", "usageLocation" };
                });

                if (users?.Value == null || users.Value.Count == 0)
                {
                    return new NotFoundObjectResult($"User with email {data.Email} not found");
                }

                string userId = users.Value[0].Id;
                var user = users.Value[0];

                // Check and update usage location if needed
                if (string.IsNullOrEmpty(user.UsageLocation))
                {
                    var usageLocation = data.UsageLocation ?? "US"; // Default to US if not provided
                    await _graphClient.Users[userId].PatchAsync(new User
                    {
                        UsageLocation = usageLocation
                    });
                }

                var licensesToAssign = new List<AssignedLicense>
                {
                    new AssignedLicense
                    {
                        SkuId = Guid.Parse(data.LicenseSkuId)
                    }
                };

                await _graphClient.Users[userId].AssignLicense.PostAsync(new AssignLicensePostRequestBody
                {
                    AddLicenses = licensesToAssign,
                    RemoveLicenses = new List<Guid?>()
                });

                _logger.LogInformation($"License {data.LicenseSkuId} assigned to user {userId}");

                return new OkResult();
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error assigning license to user: {ex.Message}");
                return new StatusCodeResult(StatusCodes.Status500InternalServerError);
            }
        }

        [Function("AddToEntraIDGroup")]
        public async Task<IActionResult> AddToEntraIDGroup([HttpTrigger(AuthorizationLevel.Function, "post")] HttpRequest req)
        {
            try
            {
                _logger.LogInformation("Processing Entra ID group membership addition request.");

                string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
                var data = System.Text.Json.JsonSerializer.Deserialize<GroupMembershipRequest>(requestBody);

                // Look up user by email, including usageLocation
                var users = await _graphClient.Users.GetAsync(config =>
                {
                    config.QueryParameters.Filter = $"mail eq '{data.Email}'";
                    config.QueryParameters.Select = new[] { "id" };
                });

                if (users?.Value == null || users.Value.Count == 0)
                {
                    return new NotFoundObjectResult($"User with email {data.Email} not found");
                }

                string userId = users.Value[0].Id;
                var user = users.Value[0];

                // Add user to group
                var groupId = data.EntraGroupId;
                var memberRequestBody = new ReferenceCreate
                {
                    OdataId = $"https://graph.microsoft.com/v1.0/directoryObjects/{userId}",
                };
                await _graphClient.Groups[groupId].Members.Ref.PostAsync(memberRequestBody);

                _logger.LogInformation($"User {userId} added to group {groupId}");

                return new OkResult();
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error processing Entra ID group membership addition request: {ex.Message}");
                return new StatusCodeResult(StatusCodes.Status500InternalServerError);
            }
        }

        [Function("RemoveUserLicense")]
        public async Task<IActionResult> RemoveUserLicense([HttpTrigger(AuthorizationLevel.Function, "post")] HttpRequest req)
        {
            try
            {
                _logger.LogInformation("Processing license removal request.");

                string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
                var data = System.Text.Json.JsonSerializer.Deserialize<LicenseAssignmentRequest>(requestBody);

                // Look up user by email, including usageLocation
                var users = await _graphClient.Users.GetAsync(config =>
                {
                    config.QueryParameters.Filter = $"mail eq '{data.Email}'";
                    config.QueryParameters.Select = new[] { "id" };
                });

                if (users?.Value == null || users.Value.Count == 0)
                {
                    return new NotFoundObjectResult($"User with email {data.Email} not found");
                }

                string userId = users.Value[0].Id;
                var user = users.Value[0];

                var licensesToRemove = new List<Guid?>
                {
                    Guid.Parse(data.LicenseSkuId)
                };

                await _graphClient.Users[userId].AssignLicense.PostAsync(new AssignLicensePostRequestBody
                {
                    AddLicenses = [],
                    RemoveLicenses = licensesToRemove
                });

                _logger.LogInformation($"License {data.LicenseSkuId} removed from user {userId}");

                return new OkResult();
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error removing license from user: {ex.Message}");
                return new StatusCodeResult(StatusCodes.Status500InternalServerError);
            }
        }
    }

    public class InvitationRequest
    {
        public required string Email { get; set; }
        public string? RedirectUrl { get; set; }
        public string? DisplayName { get; set; }
    }

    public class LicenseAssignmentRequest
    {
        public required string Email { get; set; }
        public required string LicenseSkuId { get; set; }
        public string? UsageLocation { get; set; }
    }

    public class GroupMembershipRequest
    {
        public required string Email { get; set; }
        public required string EntraGroupId { get; set; }
    }
}
