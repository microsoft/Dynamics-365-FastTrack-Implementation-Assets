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
    using System.Runtime.Serialization;
    using CommerceEvent.CommerceRuntime.Entities.DataModel;
    using Microsoft.Dynamics.Commerce.Runtime;

    using Microsoft.Dynamics.Commerce.Runtime.Messages;

    [DataContract]
    public sealed class SearchEventEntityDataResponse : Response
    {
        public SearchEventEntityDataResponse(PagedResult<CommerceEventEntity> commerceEvents)
        {
            this.CommerceEvents = commerceEvents;
        }

        [DataMember]
        public PagedResult<CommerceEventEntity> CommerceEvents { get; private set; }
    }
}