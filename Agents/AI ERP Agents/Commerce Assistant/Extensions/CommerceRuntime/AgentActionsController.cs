/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

namespace Contoso.CommerceRuntime.Services
{
    using System;
    using System.Threading.Tasks;
    using Contoso.CommerceRuntime.Messages;
    using Microsoft.Dynamics.Commerce.Runtime.DataModel;
    using Microsoft.Dynamics.Commerce.Runtime.Hosting.Contracts;
    using Microsoft.Dynamics.Commerce.Runtime.Messages;

    /// <summary>
    /// Commerce endpoints used by the POS Copilot sample.
    /// </summary>
    public class AgentActionsController : IController
    {
        /// <summary>
        /// Gets the APIM endpoint configured for Commerce Runtime.
        /// </summary>
        /// <param name="context">The endpoint context.</param>
        /// <returns>The configured APIM endpoint.</returns>
        [HttpPost]
        [Authorization(CommerceRoles.Application, CommerceRoles.Customer, CommerceRoles.Device, CommerceRoles.Employee)]
        public async Task<string> GetApimEndpoint(IEndpointContext context)
        {
            GetApimEndpointResponse response =
                await context.ExecuteAsync<GetApimEndpointResponse>(new GetApimEndpointRequest()).ConfigureAwait(false);

            return response.ApimEndpoint;
        }

        /// <summary>
        /// Applies a validated ship-to-address delivery specification to the active customer-order cart.
        /// </summary>
        /// <param name="context">The endpoint context.</param>
        /// <param name="cartId">The cart identifier.</param>
        /// <param name="deliveryModeCode">The validated delivery mode code.</param>
        /// <param name="shippingAddress">The customer's Commerce-resolved shipping address.</param>
        /// <param name="fulfillmentStoreId">The store selected to fulfill the order.</param>
        /// <param name="warehouseId">The optional warehouse selected to fulfill the order.</param>
        /// <param name="requestedShipDate">The requested ship date in ISO 8601 format.</param>
        /// <returns>The updated cart.</returns>
        [HttpPost]
        [Authorization(CommerceRoles.Device, CommerceRoles.Employee)]
        public async Task<Cart> ConfigureAgentCustomerOrderDelivery(
            IEndpointContext context,
            string cartId,
            string deliveryModeCode,
            Address shippingAddress,
            string fulfillmentStoreId,
            string warehouseId,
            string requestedShipDate)
        {
            if (string.IsNullOrWhiteSpace(cartId))
            {
                throw new ArgumentException("A cart identifier is required.", nameof(cartId));
            }

            if (string.IsNullOrWhiteSpace(deliveryModeCode))
            {
                throw new ArgumentException("A delivery mode code is required.", nameof(deliveryModeCode));
            }

            if (shippingAddress == null || shippingAddress.RecordId == 0)
            {
                throw new ArgumentException("A saved customer shipping address is required.", nameof(shippingAddress));
            }

            if (string.IsNullOrWhiteSpace(fulfillmentStoreId))
            {
                throw new ArgumentException("A fulfillment store identifier is required.", nameof(fulfillmentStoreId));
            }

            DateTimeOffset shipDate;
            if (!DateTimeOffset.TryParse(requestedShipDate, out shipDate))
            {
                throw new ArgumentException("A valid requested ship date is required.", nameof(requestedShipDate));
            }

            DeliverySpecification specification = new DeliverySpecification
            {
                DeliveryModeId = deliveryModeCode,
                DeliveryPreferenceType = DeliveryPreferenceType.ShipToAddress,
                DeliveryAddress = shippingAddress,
                RequestedDeliveryDate = shipDate,
                ShipFromStoreId = fulfillmentStoreId,
                ShipFromWarehouseId = warehouseId
            };

            UpdateDeliverySpecificationsResponse response =
                await context.ExecuteAsync<UpdateDeliverySpecificationsResponse>(
                    new UpdateDeliverySpecificationsRequest(cartId, specification)).ConfigureAwait(false);

            return response.Cart;
        }
    }
}
