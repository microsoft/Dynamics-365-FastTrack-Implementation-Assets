/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

namespace Contoso.CommerceRuntime.Controllers
{
    using System;

    using System.Threading.Tasks;
    using CommerceEvent.CommerceRuntime.Messages;

    using Microsoft.Dynamics.Commerce.Runtime.DataModel;
    using Microsoft.Dynamics.Commerce.Runtime.Hosting.Contracts;

    /// <summary>
    /// An extension controller to handle requests to the StoreHours entity set.
    /// </summary>
    public class CommerceEventsLastSyncController : IController
    {
        [HttpPost]
        [Authorization(CommerceRoles.Application,CommerceRoles.Device,CommerceRoles.Anonymous)]
        public async Task<DateTime> GetLastSyncDatetimeUTC(IEndpointContext context,string appName)
        {
            var request = new GetCommerceEventLastSyncDataRequest();
            request.AppName = appName;
            var response = await context.ExecuteAsync<GetCommerceEventLastSyncDataResponse>(request).ConfigureAwait(false);
            return response.LastSyncDateTime;
        }

        [HttpPost]
        [Authorization(CommerceRoles.Application,CommerceRoles.Device,CommerceRoles.Anonymous)]
        public async Task<DateTime> SetLastSyncDatetime(IEndpointContext context,DateTimeOffset lastSyncDatetime,string appName)
        {
            SetCommerceEventLastSyncDataRequest setCommerceEventLastSyncDataRequest= new SetCommerceEventLastSyncDataRequest();
            setCommerceEventLastSyncDataRequest.LastSyncDateTime = lastSyncDatetime.UtcDateTime;
            setCommerceEventLastSyncDataRequest.AppName = appName;
            await context.ExecuteAsync<SetCommerceEventLastSyncDataResponse>(setCommerceEventLastSyncDataRequest).ConfigureAwait(false);
            return setCommerceEventLastSyncDataRequest.LastSyncDateTime;
        }
    }
}
