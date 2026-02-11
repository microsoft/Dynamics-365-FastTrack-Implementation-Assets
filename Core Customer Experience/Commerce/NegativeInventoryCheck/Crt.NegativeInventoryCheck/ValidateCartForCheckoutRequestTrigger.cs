using Microsoft.Dynamics.Commerce.Runtime;
using Microsoft.Dynamics.Commerce.Runtime.Messages;
using System;
using System.Collections.Generic;
using System.Linq;

namespace Extensions.Crt.NegativeInventoryCheck
{
    class ValidateCartForCheckoutRequestTrigger : IRequestTrigger
    {
        IEnumerable<Type> IRequestTrigger.SupportedRequestTypes
        {
            get
            {
                return new[] { typeof(ValidateCartForCheckoutRequest) };
            }
        }

        public void OnExecuted(Request request, Response response)
        {
            // no operation
        }

        public void OnExecuting(Request request)
        {
            ValidateCartForCheckoutRequest r = (ValidateCartForCheckoutRequest)request;

            // active lines - voided lines, aggregate them over ProductId
            var productQuanityPairs = r.Cart.CartLines.Where(cl => !cl.IsVoided).GroupBy(cl => new { cl.ProductId }).Select(group => new Tuple<long, decimal>(group.Key.ProductId, group.Sum(i => i.Quantity)));
            InventoryRequestHelper.ValidateOnHandQuantities(productQuanityPairs, request.RequestContext);
        }
    }
}
