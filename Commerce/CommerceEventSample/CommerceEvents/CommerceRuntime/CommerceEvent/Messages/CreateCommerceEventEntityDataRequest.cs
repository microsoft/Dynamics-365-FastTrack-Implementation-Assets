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
    using CommerceEvent.CommerceRuntime.Entities.DataModel;
    using Microsoft.Dynamics.Commerce.Runtime.Messages;

    /// <summary>
    /// A simple request class to create an Example Entity in the database.
    /// </summary>
    [DataContract]
    public sealed class CreateCommerceEventEntityDataRequest : Request
    {
        /// <summary>
        /// Initializes a new instance of the <see cref="CreateCommerceEventEntityDataRequest"/> class.
        /// </summary>
        /// <param name="entityData">An example entity with its fields populated with the values to be stored.</param>
        public CreateCommerceEventEntityDataRequest(CommerceEventEntity entityData)
        {
            this.EntityData = entityData;
        }

        /// <summary>
        /// Gets an CommerceEvent Entity instance with its fields set with the values to be stored.
        /// </summary>
        [DataMember]
        public CommerceEventEntity EntityData { get; private set; }
    }
}