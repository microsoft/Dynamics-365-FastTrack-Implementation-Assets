/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

namespace Contoso.CommerceRuntime.RequestHandlers
{
    using System.Threading.Tasks;
    using Microsoft.Dynamics.Commerce.Runtime;
    using Microsoft.Dynamics.Commerce.Runtime.Data;
    using System.Transactions;
    using Microsoft.Dynamics.Commerce.Runtime.Messages;
    using Microsoft.Dynamics.Commerce.Runtime.DataModel;
    using Microsoft.Dynamics.Commerce.Runtime.Services.Messages;
    using System;
    using CommerceEvent.CommerceRuntime.Entities.DataModel;
    using CommerceEvent.CommerceRuntime.Messages;
    using System.Collections.Generic;
    using System.Linq;
    using Microsoft.Dynamics.Commerce.Runtime.Framework.Serialization;


    public class AddCartLineRequestHandler : SingleAsyncRequestHandler<AddCartLinesRequest>
    {

        protected override async Task<Response> Process(AddCartLinesRequest request)
        {
            ThrowIf.Null(request, "request");

            SaveCartResponse response;
            
            using (var databaseContext = new DatabaseContext(request.RequestContext))
            {
            using (var transactionScope = new TransactionScope(TransactionScopeAsyncFlowOption.Enabled))
            {
                // Execute original logic.
                response = await this.ExecuteNextAsync<SaveCartResponse>(request).ConfigureAwait(false);
                CommerceEventEntity commerceEventEntity= new CommerceEventEntity();
                commerceEventEntity.EventDateTime = DateTime.Now;
                commerceEventEntity.EventType = "AddCartLines";
                commerceEventEntity.EventTransactionId = request.CartId;
                var channelConfiguration = request.RequestContext.GetChannelConfiguration();
                commerceEventEntity.EventDataAreaId = channelConfiguration.InventLocationDataAreaId;
                commerceEventEntity.EventChannelId = channelConfiguration.RecordId;

                var cartSearchCriteria = new CartSearchCriteria(request.CartId);

                var getCartServiceRequest = new GetCartServiceRequest(cartSearchCriteria, QueryResultSettings.SingleRecord);
                var cartResponse = await request.RequestContext.ExecuteAsync<GetCartServiceResponse>(getCartServiceRequest).ConfigureAwait(false);
                var cart = cartResponse.Carts.SingleOrDefault();
                List<string> data= new List<string>();
                foreach (var cartLine in request.CartLines)
                {
                    data.Add(cartLine.ItemId);
                }
                
                commerceEventEntity.EventData= JsonHelper.Serialize(data);
                commerceEventEntity.EventCustomerId = String.IsNullOrEmpty(cart.CustomerId) ? "":cart.CustomerId;
                commerceEventEntity.EventStaffId = String.IsNullOrEmpty(cart.StaffId) ? "":cart.StaffId;
                commerceEventEntity.EventTerminalId = String.IsNullOrEmpty(cart.TerminalId) ? "":cart.TerminalId;
                
                var createCommerceEventEntityDataRequest =new CreateCommerceEventEntityDataRequest(commerceEventEntity);
                await request.RequestContext.ExecuteAsync<CreateCommerceEventEntityDataResponse>(createCommerceEventEntityDataRequest).ConfigureAwait(false);

                transactionScope.Complete();
            }
            }
            return response;
        }

        
    }
}