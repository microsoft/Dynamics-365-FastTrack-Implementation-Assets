using Extensions.Crt.InventoryAvailability;
using Microsoft.Dynamics.Commerce.Runtime;
using Microsoft.Dynamics.Commerce.Runtime.Client;
using Microsoft.Dynamics.Commerce.Runtime.DataModel;
using Microsoft.Dynamics.Commerce.Runtime.DataServices.Messages;
using Microsoft.Dynamics.Commerce.Runtime.Framework.Exceptions;
using System;
using System.Collections.Generic;
using System.Linq;

namespace Extensions.Crt.NegativeInventoryCheck
{
    internal sealed class InventoryRequestHelper
    {
        public static void ValidateOnHandQuantities(IEnumerable<Tuple<long, decimal>> lineQuantities, RequestContext context)
        {
            object oSkipValue = context.GetProperty("SKIP_INVENTORY_CHECK");
            bool skipInventoryCheck = (oSkipValue != null ? (bool)oSkipValue : false);

            if (!skipInventoryCheck)
            {
                if (lineQuantities.Count() > 0)
                {
                    var productIds = lineQuantities.Select(line => line.Item1);
                    var productManager = ProductManager.Create(context.Runtime);
                    var products = productManager.GetByIds(context.GetChannel().RecordId, productIds, QueryResultSettings.AllRecords);
                    var nonServiceProducts = products.Where(product => product.ItemType != ReleasedProductType.Service);
                    var fulfillmentLines = nonServiceProducts.Select(product => new FulfillmentLine() { ProductId = product.RecordId }).ToArray();

                    ExtGetInventoryAvailabilityForFulfillmentLinesServiceRequest r = new ExtGetInventoryAvailabilityForFulfillmentLinesServiceRequest(
                        context.GetChannelConfiguration().InventLocation,
                        fulfillmentLines: fulfillmentLines);

                    var res = context.Runtime.Execute<EntityDataServiceResponse<FulfillmentLine>>(r, context, skipRequestTriggers: false);

                    foreach (var fulfillmentLine in res.ToArray())
                    {
                        var itemCartLine = lineQuantities.Where(cl => cl.Item1 == fulfillmentLine.ProductId).First();
                        // var totalQuantity = itemCartLines.Aggregate<SalesLine>(0.0m, (decimal total, CartLine itemCartLine) => total + itemCartLine.Quantity);

                        if (fulfillmentLine.StoreInventoryTotalQuantity < itemCartLine.Item2)
                        {
                            throw new CommerceException("Microsoft_Dynamics_Commerce_30104", ExceptionSeverity.Warning, null, "Custom error")
                            {
                                LocalizedMessage = string.Format("Not enough inventory for item '{0}'. You have only {1} on hand in the store.", fulfillmentLine.ItemId, fulfillmentLine.StoreInventoryTotalQuantity),
                                LocalizedMessageParameters = new object[] { fulfillmentLine.ItemId, fulfillmentLine.StoreInventoryTotalQuantity }
                            };
                        }
                    }

                }

                // if this gets called multiple times during a single request, we can skip after the first check...
                context.SetProperty("SKIP_INVENTORY_CHECK", true);
            }
        }

    }
}
