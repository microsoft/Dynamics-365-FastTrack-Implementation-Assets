using Microsoft.Dynamics.Commerce.Runtime;
using Microsoft.Dynamics.Commerce.Runtime.DataServices.Messages;
using Microsoft.Dynamics.Commerce.Runtime.Messages;
using System;
using System.Collections.Generic;
using System.Linq;

namespace Extensions.Crt.NegativeInventoryCheck
{
    class SaveCartVersionedDataRequestTrigger : IRequestTrigger
    {
        IEnumerable<Type> IRequestTrigger.SupportedRequestTypes
        {
            get
            {
                return new[] { typeof(SaveCartVersionedDataRequest) };
            }
        }

        public void OnExecuted(Request request, Response response)
        {
            // no operation
        }

        public void OnExecuting(Request request)
        {
            SaveCartVersionedDataRequest r = (SaveCartVersionedDataRequest)request;

            if (r.SalesTransaction != null && r.SalesTransaction.ActiveSalesLines.Count > 0)
            {
                // active lines - voided lines, aggregate them over ProductId
                var productQuanityPairs = r.SalesTransaction.ActiveSalesLines.Where(asl => !asl.IsVoided).GroupBy(cl => new { cl.ProductId }).Select(group => new Tuple<long, decimal>(group.Key.ProductId, group.Sum(i => i.Quantity)));

                InventoryRequestHelper.ValidateOnHandQuantities(productQuanityPairs, request.RequestContext);
            }
        }
    }
}

