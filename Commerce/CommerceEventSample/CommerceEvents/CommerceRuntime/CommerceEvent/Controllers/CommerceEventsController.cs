/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */
 
namespace CommerceEvent.CommerceRuntime.Controllers
{
    using System.Threading.Tasks;

    using Microsoft.Dynamics.Commerce.Runtime;
    using Microsoft.Dynamics.Commerce.Runtime.DataModel;
    using Microsoft.Dynamics.Commerce.Runtime.Hosting.Contracts;
    using CommerceEvent.CommerceRuntime.Entities.DataModel;
    using CommerceEvent.CommerceRuntime.Messages;
    using CommerceEvent.CommerceRuntime.DataModel;


    /// <summary>
    /// An extension controller to handle requests to the StoreHours entity set.
    /// </summary>
    [RoutePrefix("CommerceEventsController")]
    [BindEntity(typeof(CommerceEvent.CommerceRuntime.Entities.DataModel.CommerceEventEntity))]
    public class CommerceEventsController : IController
    {
        [HttpGet]
        [Authorization(CommerceRoles.Anonymous, CommerceRoles.Application,CommerceRoles.Customer, CommerceRoles.Device, CommerceRoles.Employee)]
        public async Task<PagedResult<Entities.DataModel.CommerceEventEntity>> GetAllCommerceEvents(IEndpointContext context,QueryResultSettings queryResultSettings)
        {
            var request = new Messages.CommerceEventEntityDataRequest() { QueryResultSettings = queryResultSettings };
            var response = await context.ExecuteAsync<Messages.CommerceEventEntityDataResponse>(request).ConfigureAwait(false);
            return response.CommerceEvents;
        }

        [HttpPost]
        [Authorization(CommerceRoles.Anonymous, CommerceRoles.Application,CommerceRoles.Customer, CommerceRoles.Device, CommerceRoles.Employee)]
        public async Task<PagedResult<Entities.DataModel.CommerceEventEntity>> Search(IEndpointContext context,CommerceEventSearchCriteria commerceEventSearchCriteria, QueryResultSettings queryResultSettings )
        {
            var searchEventEntityDataRequest=new SearchEventEntityDataRequest();
            searchEventEntityDataRequest.QueryResultSettings = queryResultSettings;
            searchEventEntityDataRequest.SearchCriteria = commerceEventSearchCriteria;
            var response = await context.ExecuteAsync<Messages.SearchEventEntityDataResponse>(searchEventEntityDataRequest).ConfigureAwait(false);
            return response.CommerceEvents;
        }


    }
}
