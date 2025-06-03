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
    using System.Runtime.Caching;
    using System.Text;
    using Microsoft.Dynamics.Commerce.Runtime.DataModel;

    public class SampleDataCacheAccessor
    {

        protected MemoryCache Cache
        {
            get
            {
                return MemoryCache.Default;
            }
        }

        protected RequestContext Context
        {
            get;
            set;
        }

        protected long ChannelId
        {
            get
            {
                return this.Context.GetPrincipal().ChannelId;
            }
        }

        protected SampleDataCacheAccessor()
        {
        }

        protected SampleDataCacheAccessor(RequestContext context)
        {

            ThrowIf.Null(context, nameof(context));
            this.Context = context;
        }

        protected bool TryGetItem<T>(string key, out T item)
        {
            ThrowIf.NullOrWhiteSpace(key, nameof(key));

            item = default(T);

            var cachedItem = this.Cache.Get(key);

            var itemExists = cachedItem != null;

            item = itemExists ? (T)cachedItem : default;

            return itemExists;

        }

        protected void PutItem<T>(string key, T item, DateTimeOffset absoluteExpiration)
        {
            ThrowIf.NullOrWhiteSpace(key, nameof(key));

            this.PutItem(key, item, absoluteExpiration, TimeSpan.Zero);
        }

        protected void PutItem<T>(string key, T item, DateTimeOffset absoluteExpiration, TimeSpan slidingExpiration)
        {
            ThrowIf.NullOrWhiteSpace(key, nameof(key));

            var policy = new CacheItemPolicy
            {
                AbsoluteExpiration = absoluteExpiration,
                SlidingExpiration = slidingExpiration,
            };

            this.Cache.Set(key, item, policy, regionName: null);

        }

        public void EvictItem(string key)
        {
            ThrowIf.NullOrWhiteSpace(key, nameof(key));

            if (this.Cache.Contains(key, regionName: null))
            {
                this.Cache.Remove(key, regionName: null);
            }
        }

        protected virtual string GetKeyPattern()
        {
            return string.Format("{0}\\{1}\\", this.ChannelId, "Sample");
        }

        protected string GenerateKey<T1, T2, T3>(string callingFunction, T1 parameter1, T2 parameter2, T3 parameter3)
        {
            return string.Format("{0}{1}\\{2}_{3}_{4}", this.GetKeyPattern(), callingFunction, parameter1, parameter2, parameter3);
        }

        protected string GenerateKey<T1, T2>(string callingFunction, T1 parameter1, T2 parameter2)
        {
            return string.Format("{0}{1}\\{2}_{3}", this.GetKeyPattern(), callingFunction, parameter1, parameter2);
        }

        protected virtual string GenerateKey<T1, T2>(string callingFunction, T1 parameter1, T2 parameter2, QueryResultSettings querySettings)
        {
            ThrowIf.NullOrWhiteSpace(callingFunction, nameof(callingFunction));
            ThrowIf.Null(querySettings, nameof(querySettings));

            int settingsHash = CalculateQuerySettingsHash(querySettings);

            return string.Format("{0}{1}\\{2}_{3}_{4}", this.GetKeyPattern(), callingFunction, parameter1, parameter2, settingsHash);
        }

        protected int CalculateQuerySettingsHash(QueryResultSettings settings)
        {
            ThrowIf.Null(settings, nameof(settings));

            StringBuilder collectionStr = new StringBuilder();

            // add change tracking parameters
            if (settings.ChangeTracking != null)
            {
                collectionStr.AppendFormat("{0}_", settings.ChangeTracking.ExpectedLastSyncAnchor);
                collectionStr.AppendFormat("{0}_", settings.ChangeTracking.NextSyncAnchor);
            }

            // add columnset
            if (settings.ColumnSet != null)
            {
                collectionStr.AppendFormat("{0}_", CalculateColumnSetHash(settings.ColumnSet));
            }

            // add paging parameters
            if (!settings.Paging.NoPageSizeLimit)
            {
                collectionStr.AppendFormat("{0}_{1}_", settings.Paging.Top, settings.Paging.Skip);
            }

            // add sorting parameters
            if (settings.Sorting != null && settings.Sorting.IsSpecified)
            {
                collectionStr.AppendFormat("{0}", settings.Sorting);
            }

            string collectionKey = collectionStr.ToString().ToUpperInvariant();
            return collectionKey.GetHashCode();
        }

        protected static int CalculateColumnSetHash(ColumnSet columnSet)
        {
            ThrowIf.Null(columnSet, nameof(columnSet));

            StringBuilder collectionStr = new StringBuilder();

            collectionStr.AppendFormat("{0}_", columnSet.Count);
            foreach (string column in columnSet)
            {
                collectionStr.AppendFormat("{0}_", column);
            }

            string collectionKey = collectionStr.ToString().ToUpperInvariant();
            return collectionKey.GetHashCode();
        }

    }
}