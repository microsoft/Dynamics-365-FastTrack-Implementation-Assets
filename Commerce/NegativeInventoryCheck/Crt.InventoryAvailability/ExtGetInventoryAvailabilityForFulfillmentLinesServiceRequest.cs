using Microsoft.Dynamics.Commerce.Runtime.DataModel;
using Microsoft.Dynamics.Commerce.Runtime.Services.Messages;
using System.Collections.Generic;
using System.Runtime.Serialization;

namespace Extensions.Crt.InventoryAvailability
{
    [DataContract]
    public class ExtGetInventoryAvailabilityForFulfillmentLinesServiceRequest : ServiceRequest
    {
        /// <summary>
        /// Initializes a new instance of the <see cref="GetInventoryAvailabilityForFulfillmentLinesServiceRequest"/> class.
        /// </summary>
        /// <param name="inventLocationId">The warehouse identifier for the request.</param>
        /// <param name="fulfillmentLines">The fulfillment lines for the request.</param>
        public ExtGetInventoryAvailabilityForFulfillmentLinesServiceRequest(string inventLocationId, IEnumerable<FulfillmentLine> fulfillmentLines)
        {
            this.InventLocationId = inventLocationId;
            this.FulfillmentLines = fulfillmentLines;
        }

        /// <summary>
        /// Gets the warehouse identifier.
        /// </summary>
        public string InventLocationId { get; private set; }

        /// <summary>
        /// Gets the fulfillment lines.
        /// </summary>
        public IEnumerable<FulfillmentLine> FulfillmentLines { get; private set; }
    }
}
