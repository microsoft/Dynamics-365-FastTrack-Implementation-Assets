/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

namespace CommerceEvent.CommerceRuntime.Messages
{
    using System;
    using System.Runtime.Serialization;
    using Microsoft.Dynamics.Commerce.Runtime.Messages;

    /// <summary>
    /// A simple response class to indicate whether creating a new entity succeeded or not.
    /// </summary>
    [DataContract]
    public sealed class CreateCommerceEventEntityDataResponse : Response
    {
        /// <summary>
        /// Initializes a new instance of the <see cref="CreateCommerceEventEntityDataResponse"/> class.
        /// </summary>
        public CreateCommerceEventEntityDataResponse(string eventTransactionId,string eventType, DateTime eventDateTime,string dataArea)
        {
            this.EventDateTime = eventDateTime;
            this.EventType = eventType;
            this.EventTransactionId = eventTransactionId;
            this.DataArea = dataArea;
        }

        public DateTime EventDateTime { get; private set; }

        public string EventType { get; private set; }

        public string EventTransactionId { get; private set; }

        public string DataArea { get; private set; }
    }
}