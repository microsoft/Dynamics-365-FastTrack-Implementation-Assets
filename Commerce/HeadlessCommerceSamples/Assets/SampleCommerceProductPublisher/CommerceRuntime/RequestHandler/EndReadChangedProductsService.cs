/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

namespace OperatingUnit.CommerceRuntime.RequestHandlers
{
    using System;
    using System.Collections.Generic;
    using System.Threading.Tasks;
    using Microsoft.Dynamics.Commerce.Runtime;
    using Microsoft.Dynamics.Commerce.Runtime.Messages;
    using Microsoft.Dynamics.Commerce.Runtime.DataServices.Messages;

    /// <summary>
    /// Sample service to demonstrate managing a collection of entities.
    /// </summary>
    public class EndReadChangedProductsService : IRequestHandlerAsync
    {
        /// <summary>
        /// Gets the collection of supported request types by this handler.
        /// </summary>
        public IEnumerable<Type> SupportedRequestTypes
        {
            get
            {
                return new[]
                {
                    typeof(EndReadChangedProductsRequest)
                };
            }
        }

        /// <summary>
        /// Entry point to service.
        /// </summary>
        /// <param name="request">The request to execute.</param>
        /// <returns>Result of executing request, or null object for void operations.</returns>
        public Task<Response> Execute(Request request)
        {
            ThrowIf.Null(request, nameof(request));

            switch (request)
            {
                case EndReadChangedProductsRequest endReadChangedProductsRequest:
                    return this.EndReadChangedProducts(endReadChangedProductsRequest);
                default:
                    throw new NotSupportedException($"Request '{request.GetType()}' is not supported.");
            }
        }


        private async Task<Response> EndReadChangedProducts(EndReadChangedProductsRequest request)
        {
            ThrowIf.Null(request, nameof(request));
            ThrowIf.Null(request.Session, "request.Session");
            ThrowIf.EmptyGuid(request.Session.Id, "request.Session.Id");

            DeleteChangedEntitiesIdsDataRequest deleteProductsRequest = new DeleteChangedEntitiesIdsDataRequest(Microsoft.Dynamics.Commerce.Runtime.DataModel.EntityType.Product, request.Session.Id);
            await request.RequestContext.ExecuteAsync<NullResponse>(deleteProductsRequest).ConfigureAwait(false);

            if (!string.IsNullOrEmpty(request.Session.NextSynchronizationToken))
            {
                Microsoft.Dynamics.Commerce.Runtime.DataModel.ChannelProperty channelProperty = new Microsoft.Dynamics.Commerce.Runtime.DataModel.ChannelProperty
                {
                    Name = Microsoft.Dynamics.Commerce.Runtime.DataModel.ChannelProperty.PropertyKeySyncAnchor,
                    Value = request.Session.NextSynchronizationToken,
                };

                UpdateChannelPropertiesByChannelIdDataRequest updatePropertyRequest = new UpdateChannelPropertiesByChannelIdDataRequest(request.RequestContext.GetPrincipal().ChannelId, new Microsoft.Dynamics.Commerce.Runtime.DataModel.ChannelProperty[] { channelProperty });

                await request.RequestContext.ExecuteAsync<NullResponse>(updatePropertyRequest).ConfigureAwait(false);
            }

            return new EndReadChangedProductsResponse();
        }
    }
}