using Microsoft.Dynamics.Commerce.Runtime;
using Microsoft.Dynamics.Commerce.Runtime.Messages;
using System;
using System.Collections.Generic;

namespace Extensions.Crt.NegativeInventoryCheck
{
    class SuspendCartRequestTrigger : IRequestTrigger
    {
        IEnumerable<Type> IRequestTrigger.SupportedRequestTypes
        {
            get
            {
                return new[] { typeof(SuspendCartRequest) };
            }
        }

        public void OnExecuted(Request request, Response response)
        {
            // no operation
        }

        public void OnExecuting(Request request)
        {
            // when we resume a transaction, we do not check (we will check during checkout)
            request.RequestContext.SetProperty("SKIP_INVENTORY_CHECK", true);
        }
    }
}
