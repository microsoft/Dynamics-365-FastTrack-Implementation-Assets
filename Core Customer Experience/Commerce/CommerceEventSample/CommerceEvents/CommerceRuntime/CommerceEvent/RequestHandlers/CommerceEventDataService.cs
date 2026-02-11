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
    using System.Linq;
    using System.Threading.Tasks;
    using Microsoft.Dynamics.Commerce.Runtime;
    using Microsoft.Dynamics.Commerce.Runtime.Data;
    using Microsoft.Dynamics.Commerce.Runtime.DataAccess.SqlServer;
    using Microsoft.Dynamics.Commerce.Runtime.Messages;
    using CommerceEvent.CommerceRuntime.Entities.DataModel;
    using CommerceEvent.CommerceRuntime.Messages;
    using CommerceEvent.CommerceRuntime.Data;


    public class CommerceEventDataService : IRequestHandlerAsync
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
                    typeof(CommerceEventEntityDataRequest),
                    typeof(CreateCommerceEventEntityDataRequest),
                    typeof(SearchEventEntityDataRequest),
                };
            }
        }

        public Task<Response> Execute(Request request)
        {
            ThrowIf.Null(request, nameof(request));

            switch (request)
            {
                case CommerceEventEntityDataRequest commerceEventEntityDataRequest:
                    return this.GetCommerceEvents(commerceEventEntityDataRequest);
                case CreateCommerceEventEntityDataRequest createCommerceEventEntityDataRequest:
                    return this.CreateCommerceEvent(createCommerceEventEntityDataRequest);
                case SearchEventEntityDataRequest searchEventEntityDataRequest:
                    return this.SearchCommerceEvents(searchEventEntityDataRequest);
                default:
                    throw new NotSupportedException($"Request '{request.GetType()}' is not supported.");
            }
        }

        private async Task<Response> GetCommerceEvents(CommerceEventEntityDataRequest request)
        {
            ThrowIf.Null(request, "request");

            using (DatabaseContext databaseContext = new DatabaseContext(request.RequestContext))
            {
                var query = new SqlPagedQuery(request.QueryResultSettings)
                {
                    DatabaseSchema = "ext",
                    Select = new ColumnSet("EVENTTRANSACTIONID", "EVENTDATETIME", "EVENTTYPE", "EVENTDATA", "EVENTCUSTOMERID", "EVENTTERMINALID", "EVENTCHANNELID", "EVENTSTAFFID", "EVENTDATAAREAID"),
                    From = "COMMERCEEVENTSVIEW",
                    OrderBy = "EVENTDATETIME",
                };

                var queryResults =
                    await databaseContext
                    .ReadEntityAsync<CommerceEventEntity>(query)
                    .ConfigureAwait(continueOnCapturedContext: false);
                return new CommerceEventEntityDataResponse(queryResults);
            }
        }

        private async Task<Response> SearchCommerceEvents(SearchEventEntityDataRequest request)
        {
            ThrowIf.Null(request, "request");
            var cacheDataAccessor = this.GetCacheAccessor(request.RequestContext);

            var result = cacheDataAccessor.GetCommerceEventsBySearchCriteria<PagedResult<CommerceEventEntity>>(request.SearchCriteria.EventType,
                    request.SearchCriteria.EventDateTimeFrom, request.SearchCriteria.EventDateTimeTo, request.QueryResultSettings);

            if (result != null)
            {
                return new SearchEventEntityDataResponse(result);
            }
            else
            {

                using (DatabaseContext databaseContext = new DatabaseContext(request.RequestContext))
                {
                    var query = new SqlPagedQuery(request.QueryResultSettings)
                    {
                        DatabaseSchema = "ext",
                        Select = new ColumnSet("EVENTTRANSACTIONID", "EVENTDATETIME", "EVENTTYPE", "EVENTDATA", "EVENTCUSTOMERID", "EVENTTERMINALID", "EVENTCHANNELID", "EVENTSTAFFID", "EVENTDATAAREAID"),
                        From = "COMMERCEEVENTSVIEW",
                        OrderBy = "EVENTDATETIME",
                    };

                    query.Where += $"EVENTDATETIME > '{request.SearchCriteria.EventDateTimeFrom}' AND EVENTDATETIME <= '{request.SearchCriteria.EventDateTimeTo}'";

                    if (!String.IsNullOrEmpty(request.SearchCriteria.EventType))
                        query.Where += $" AND EVENTTYPE = '{request.SearchCriteria.EventType}'";

                    var queryResults =
                        await databaseContext
                        .ReadEntityAsync<CommerceEventEntity>(query)
                        .ConfigureAwait(continueOnCapturedContext: false);

                    if (queryResults.Count<CommerceEventEntity>() > 0)
                    {
                        cacheDataAccessor.PutCommerceEventsBySearchCriteria<PagedResult<CommerceEventEntity>>(request.SearchCriteria.EventType,
                        request.SearchCriteria.EventDateTimeFrom, request.SearchCriteria.EventDateTimeTo, request.QueryResultSettings, queryResults);
                    }
                    return new SearchEventEntityDataResponse(queryResults);
                }
            }
        }

        private async Task<Response> CreateCommerceEvent(CreateCommerceEventEntityDataRequest request)
        {
            ThrowIf.Null(request, nameof(request));
            ThrowIf.Null(request.EntityData, nameof(request.EntityData));

            CommerceEventEntity insertedEntity;
            using (var databaseContext = new SqlServerDatabaseContext(request.RequestContext))
            {
                ParameterSet parameters = new ParameterSet();
                parameters["@s_EventTransactionId"] = request.EntityData.EventTransactionId;
                parameters["@d_EventDateTime"] = request.EntityData.EventDateTime;
                parameters["@s_EventType"] = request.EntityData.EventType;
                parameters["@s_EventCustomerId"] = request.EntityData.EventCustomerId;
                parameters["@s_EventStaffId"] = request.EntityData.EventStaffId;
                parameters["@b_EventChannelId"] = request.EntityData.EventChannelId;
                parameters["@s_EventTerminalId "] = request.EntityData.EventTerminalId;
                parameters["@s_EventData"] = request.EntityData.EventData;
                parameters["@s_DataAreaId"] = request.EntityData.EventDataAreaId;
                var result = await databaseContext
                    .ExecuteStoredProcedureAsync<CommerceEventEntity>("[ext].[INSERTCOMMERCEEVENT]", parameters, request.QueryResultSettings)
                    .ConfigureAwait(continueOnCapturedContext: false);
                insertedEntity = result.Item2.Single();
            }

            return new CreateCommerceEventEntityDataResponse(insertedEntity.EventTransactionId, insertedEntity.EventType, insertedEntity.EventDateTime, insertedEntity.EventDataAreaId);
        }

        private CommerceEventsDataCacheAccessor GetCacheAccessor(RequestContext context)
        {
            return CommerceEventsDataCacheAccessor.Instantiate(context);
        }
    }
}