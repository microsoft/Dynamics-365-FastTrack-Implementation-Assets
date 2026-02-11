using Microsoft.Dynamics.Commerce.Runtime;
using Microsoft.Dynamics.Commerce.Runtime.DataModel;
using Microsoft.Dynamics.Commerce.Runtime.DataServices.Messages;
using Microsoft.Dynamics.Commerce.Runtime.Services;
using System;
using System.Linq;

namespace Extensions.Crt.InventoryAvailability
{
    public class ExtInventoryAvailabilityService : SingleRequestHandler<ExtGetInventoryAvailabilityForFulfillmentLinesServiceRequest, EntityDataServiceResponse<FulfillmentLine>>
    {
        protected override EntityDataServiceResponse<FulfillmentLine> Process(ExtGetInventoryAvailabilityForFulfillmentLinesServiceRequest request)
        {
            return this.GetFulfillmentLineInventoryAvailability(request);
        }

        private EntityDataServiceResponse<FulfillmentLine> GetFulfillmentLineInventoryAvailability(ExtGetInventoryAvailabilityForFulfillmentLinesServiceRequest request)
        {
            var dataAreadId = request.RequestContext.GetChannelConfiguration().InventLocationDataAreaId;
            var inventLocationId = request.InventLocationId;
            var fulfillmentLines = request.FulfillmentLines;
            var distinctProducsts = fulfillmentLines.Select(f => new { f.ProductId }).Distinct(); // Get distinct product Ids.
            var productWarehouses = distinctProducsts.Select(f => new ProductWarehouse()
            {
                DataAreaId = dataAreadId,
                InventLocationId = inventLocationId,
                ProductId = f.ProductId
            });

            // Get inventory availability of products
            var getProductDimensionsInventoryAvailabilityDataRequest = new GetProductDimensionsInventoryAvailabilityDataRequest(productWarehouses);
            var productInventoryAvailabilities = request.RequestContext.Execute<EntityDataServiceResponse<ProductDimensionInventoryAvailability>>(getProductDimensionsInventoryAvailabilityDataRequest).PagedEntityCollection.Results;

            // Get unposted quantities
            var dataRetriever = new InventoryAvailabilityServiceDataRetriever(request.RequestContext);
            var inventoryUnpostedQuantities = dataRetriever.GetUnpostedQuantities(productWarehouses);

            foreach (var fulfillmentLine in fulfillmentLines)
            {
                // find out product availability and unposted quantity of the product
                var productAvailability = productInventoryAvailabilities.First(p => p.ProductId == fulfillmentLine.ProductId
                    && p.InventLocationId.Equals(inventLocationId, StringComparison.OrdinalIgnoreCase)
                    && p.DataAreaId.Equals(dataAreadId, StringComparison.OrdinalIgnoreCase));
                var unpostedQuantity = inventoryUnpostedQuantities.First(i => i.ProductId == fulfillmentLine.ProductId
                    && i.InventLocationId.Equals(inventLocationId, StringComparison.OrdinalIgnoreCase)
                    && i.DataAreaId.Equals(dataAreadId, StringComparison.OrdinalIgnoreCase));

                // assign the value back to fulfillment line
                fulfillmentLine.StoreInventoryOrderedQuantity = productAvailability.OrderedInTotal;
                fulfillmentLine.StoreInventoryReservedQuantity = productAvailability.PhysicalReserved;
                fulfillmentLine.StoreInventoryTotalQuantity = productAvailability.PhysicalInventory - productAvailability.PhysicalReserved + productAvailability.UnprocessedQty + unpostedQuantity.UnpostedQuantity;
            }

            return new EntityDataServiceResponse<FulfillmentLine>(fulfillmentLines.AsPagedResult());
        }
    }
}
