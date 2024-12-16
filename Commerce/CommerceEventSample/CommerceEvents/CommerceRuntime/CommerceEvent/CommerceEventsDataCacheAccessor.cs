/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */
namespace CommerceEvent.CommerceRuntime.Data
{
    using System;
    using Microsoft.Dynamics.Commerce.Runtime;
    using Microsoft.Dynamics.Commerce.Runtime.Data;
    using System.Runtime.Caching;
    using System.Collections.Generic;
    using System.Linq;
    using Microsoft.Dynamics.Commerce.Runtime.Configuration;
    using Microsoft.Dynamics.Commerce.Runtime.DataModel;

    public class CommerceEventsDataCacheAccessor : SampleDataCacheAccessor
    {
        public CommerceEventsDataCacheAccessor(RequestContext context)
            : base(context)
        {

        }

        protected override string GetKeyPattern()
        {
            return string.Format("{0}\\{1}\\", this.ChannelId, "CommerceEvents");
        }

        internal static CommerceEventsDataCacheAccessor Instantiate(RequestContext context)
        {
            return new CommerceEventsDataCacheAccessor(context);
        }

        public T GetCommerceEventsBySearchCriteria<T>(string eventType, DateTime dateFrom, DateTime dateTo, QueryResultSettings settings)
        {
            string key = this.GenerateKey(eventType, dateFrom, dateTo, settings);

            this.TryGetItem(key, out T result);

            return result;
        }

        public void PutCommerceEventsBySearchCriteria<T>(string eventType, DateTime dateFrom, DateTime dateTo, QueryResultSettings settings, T result)
        {
            string key = this.GenerateKey(eventType, dateFrom, dateTo, settings);
            DateTimeOffset expiration = DateTimeOffset.Now + TimeSpan.FromHours(1);

            this.PutItem(key, result, expiration);
        }



    }
}