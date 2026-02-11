/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

namespace Contoso.CommerceRuntime.RequestHandlers
{
    using System;
    using System.Collections.Generic;
    using System.Globalization;
    using System.Linq;
    using System.Threading.Tasks;
    using Microsoft.Dynamics.Commerce.Runtime;
    using Microsoft.Dynamics.Commerce.Runtime.Data;
    using Microsoft.Dynamics.Commerce.Runtime.DataAccess.SqlServer;
    using Microsoft.Dynamics.Commerce.Runtime.Messages;
    using CommerceEvent.CommerceRuntime.Entities.DataModel;
    using CommerceEvent.CommerceRuntime.Messages;
    using Microsoft.Dynamics.Commerce.Runtime.DataModel;

    public class CommerceEventLastSyncDataService : IRequestHandlerAsync
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
                    typeof(SetCommerceEventLastSyncDataRequest),
                    typeof(GetCommerceEventLastSyncDataRequest)
                };
            }
        }

        public Task<Response> Execute(Request request)
        {
            ThrowIf.Null(request, nameof(request));

            switch (request)
            {
                case GetCommerceEventLastSyncDataRequest getCommerceEventLastSyncDataRequest:
                    return this.GetLastSyncDatetime(getCommerceEventLastSyncDataRequest);
                case SetCommerceEventLastSyncDataRequest setCommerceEventLastSyncDataRequest:
                    return this.CreateCommerceEventLastSync(setCommerceEventLastSyncDataRequest);
                default:
                    throw new NotSupportedException($"Request '{request.GetType()}' is not supported.");
            }
        }

        private async Task<Response> GetLastSyncDatetime(GetCommerceEventLastSyncDataRequest request)
        {
            ThrowIf.Null(request, "request");
            GetCommerceEventLastSyncDataResponse response=new GetCommerceEventLastSyncDataResponse();

            using (DatabaseContext databaseContext = new DatabaseContext(request.RequestContext))
            {
                var query = new SqlPagedQuery(QueryResultSettings.SingleRecord)
                {
                    DatabaseSchema = "ext",
                    Select = new ColumnSet("EVENTLASTSYNCTDATETIME"),
                    From = "COMMERCEEVENTSLASTSYNCVIEW",
                    OrderBy = "EVENTLASTSYNCTDATETIME DESC"
                    
                };

                query.Where += $"APPNAME = '{request.AppName}'";
               

                var result = await databaseContext.ExecuteScalarAsync<DateTime>(query).ConfigureAwait(false);
        
                response.LastSyncDateTime = result;
            }
            return response;
        }

        private async Task<Response> CreateCommerceEventLastSync(SetCommerceEventLastSyncDataRequest request)
        {
            ThrowIf.Null(request, nameof(request));

            var response = new SetCommerceEventLastSyncDataResponse();
            using (var databaseContext = new SqlServerDatabaseContext(request.RequestContext))
            {
                ParameterSet parameters = new ParameterSet();
                parameters["@d_LastsyncDatetime"] = request.LastSyncDateTime;
                parameters["@s_DataAreaId"] = request.RequestContext.GetChannelConfiguration().InventLocationDataAreaId;
                parameters["@s_AppName"] = request.AppName;
                var result = await databaseContext
                    .ExecuteStoredProcedureDataSetAsync("[ext].[INSERTCOMMERCEEVENTSYNCTABLE]", parameters, request.QueryResultSettings)
                    .ConfigureAwait(continueOnCapturedContext: false);
                response.LastSyncDateTime = Convert.ToDateTime(result?.Tables.SingleOrDefault()?.Rows.SingleOrDefault()?["EVENTLASTSYNCTDATETIME"]);
                response.AppName =result?.Tables.SingleOrDefault()?.Rows.SingleOrDefault()?["APPNAME"].ToString();
            }

            return response;
        }

}
}