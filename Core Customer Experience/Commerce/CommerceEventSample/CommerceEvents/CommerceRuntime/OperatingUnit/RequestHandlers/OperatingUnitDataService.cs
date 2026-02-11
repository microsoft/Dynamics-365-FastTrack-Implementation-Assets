/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

namespace OperatingUnit.CommerceRuntime.RequestHandlers
{
    using System;
    using System.Collections.Generic;
    using System.Globalization;
    using System.Linq;
    using System.Threading.Tasks;
    using Microsoft.Dynamics.Commerce.Runtime;
    using Microsoft.Dynamics.Commerce.Runtime.Data;
    using Microsoft.Dynamics.Commerce.Runtime.Messages;
    using OperatingUnit.CommerceRuntime.Messages;
    using Microsoft.Dynamics.Commerce.Runtime.DataModel;

    /// <summary>
    /// Sample service to demonstrate managing a collection of entities.
    /// </summary>
    public class OperatingUnitDataService : IRequestHandlerAsync
    {
        /// <summary>
        /// Gets the collection of supported request types by this handler.
        /// </summary>
        public IEnumerable<Type> SupportedRequestTypes
        {
            get
            {
                return new[]
                {
                    typeof(GetOperatingUnitDataRequest)
                };
            }
        }

        /// <summary>
        /// Entry point to service.
        /// </summary>
        /// <param name="request">The request to execute.</param>
        /// <returns>Result of executing request, or null object for void operations.</returns>
        public Task<Response> Execute(Request request)
        {
            ThrowIf.Null(request, nameof(request));

            switch (request)
            {
                case GetOperatingUnitDataRequest getOperatingUnitDataRequest:
                    return this.GetOperatingUnitNumber(getOperatingUnitDataRequest);
                default:
                    throw new NotSupportedException($"Request '{request.GetType()}' is not supported.");
            }
        }


        private async Task<Response> GetOperatingUnitNumber(GetOperatingUnitDataRequest request)
        {
            ThrowIf.Null(request, "request");
            GetOperatingUnitDataResponse response=new GetOperatingUnitDataResponse();

            using (DatabaseContext databaseContext = new DatabaseContext(request.RequestContext))
            {
                 var query = new SqlPagedQuery(QueryResultSettings.SingleRecord)
                {
                    Select = new ColumnSet("OPERATINGUNITNUMBER"),
                    From = "CHANNELIDENTITYVIEW",
                    Where = "RECID = @recid",
                };

                query.Parameters["@recid"] = request.ChannelId;
                var result = await databaseContext.ExecuteScalarCollectionAsync<string>(query).ConfigureAwait(false);
                if (result?.Count <= 0)
                {
                    throw new DataValidationException(
                        DataValidationErrors.Microsoft_Dynamics_Commerce_Runtime_InvalidRequest,
                        $"Could not retrieve Oun");
                }
                else if (result?.Count >= 2)
                {
                    throw new DataValidationException(
                        DataValidationErrors.Microsoft_Dynamics_Commerce_Runtime_InvalidRequest,
                        $"Could not retrieve Oun");
                }

                response.OperatingUnitNumber = result[0];
            }
            return response;
        }
    }
}