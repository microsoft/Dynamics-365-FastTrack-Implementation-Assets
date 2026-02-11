using System.Runtime.Caching;
using Microsoft.Dynamics.Commerce.Runtime;

namespace ProductPublisher.Core
{
    /// <summary>
    /// Cache accesor class
    /// </summary>
    internal class PublisherSessionCacheAccessor
    {
        private static MemoryCache Cache
        {
            get
            {
                return MemoryCache.Default;
            }
        }

        public PublisherSessionCacheAccessor()
        {
        }

        /// <summary>
        /// Try get item from cache
        /// </summary>
        /// <typeparam name="T"></typeparam>
        /// <param name="key"></param>
        /// <param name="item"></param>
        /// <returns></returns>
        public static bool TryGetItem<T>(string key, out T? item)
        {
            ThrowIf.NullOrWhiteSpace(key, nameof(key));

            var cachedItem = PublisherSessionCacheAccessor.Cache.Get(key);

            var itemExists = cachedItem != null;

            item = itemExists ? (T?)cachedItem : default;

            return itemExists;

        }

        /// <summary>
        /// Put item in cache with absolute expiration
        /// </summary>
        /// <typeparam name="T"></typeparam>
        /// <param name="key"></param>
        /// <param name="item"></param>
        /// <param name="absoluteExpiration"></param>
        public static void PutItem<T>(string key, T item, DateTimeOffset absoluteExpiration)
        {
            ThrowIf.NullOrWhiteSpace(key, nameof(key));

            PublisherSessionCacheAccessor.PutItem(key, item, absoluteExpiration, TimeSpan.Zero);
        }

        /// <summary>
        /// Put item with sliding expiration
        /// </summary>
        /// <typeparam name="T"></typeparam>
        /// <param name="key"></param>
        /// <param name="item"></param>
        /// <param name="absoluteExpiration"></param>
        /// <param name="slidingExpiration"></param>
        public static void PutItem<T>(string key, T item, DateTimeOffset absoluteExpiration, TimeSpan slidingExpiration)
        {
            ThrowIf.NullOrWhiteSpace(key, nameof(key));

            var policy = new CacheItemPolicy
            {
                AbsoluteExpiration = absoluteExpiration,
                SlidingExpiration = slidingExpiration,
            };

            PublisherSessionCacheAccessor.Cache.Set(key, item, policy, regionName: null);

        }

        /// <summary>
        /// Remove item from cache
        /// </summary>
        /// <param name="key"></param>
        public static void EvictItem(string key)
        {
            ThrowIf.NullOrWhiteSpace(key, nameof(key));

            if (PublisherSessionCacheAccessor.Cache.Contains(key, regionName: null))
            {
                PublisherSessionCacheAccessor.Cache.Remove(key, regionName: null);
            }
        }
        
    }
}
