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


    public class CheckoutCartRequestHandler : SingleAsyncRequestHandler<CheckoutCartRequest>
    {

        protected override async Task<Response> Process(CheckoutCartRequest request)
        {
            ThrowIf.Null(request, "request");

            CheckoutCartResponse response;
            
            using (var databaseContext = new DatabaseContext(request.RequestContext))
            {
            using (var transactionScope = new TransactionScope(TransactionScopeAsyncFlowOption.Enabled))
            {
                // Execute original logic.
                response = await this.ExecuteNextAsync<CheckoutCartResponse>(request).ConfigureAwait(false);
                CommerceEventEntity commerceEventEntity= new CommerceEventEntity();
                commerceEventEntity.EventDateTime = DateTime.Now;
                commerceEventEntity.EventType = "Checkout";
                var channelConfiguration = request.RequestContext.GetChannelConfiguration();
                commerceEventEntity.EventTransactionId = request.CartId;
                commerceEventEntity.EventDataAreaId = channelConfiguration.InventLocationDataAreaId;
                commerceEventEntity.EventChannelId = channelConfiguration.RecordId;
                commerceEventEntity.EventCustomerId = response.SalesOrder.CustomerId;
                commerceEventEntity.EventStaffId = response.SalesOrder.StaffId;
                commerceEventEntity.EventTerminalId = response.SalesOrder.TerminalId;
                commerceEventEntity.EventData= "{}";
                
                var createCommerceEventEntityDataRequest =new CreateCommerceEventEntityDataRequest(commerceEventEntity);
                await request.RequestContext.ExecuteAsync<CreateCommerceEventEntityDataResponse>(createCommerceEventEntityDataRequest).ConfigureAwait(false);

                transactionScope.Complete();
            }
            }
            return response;
        }

        
    }
}