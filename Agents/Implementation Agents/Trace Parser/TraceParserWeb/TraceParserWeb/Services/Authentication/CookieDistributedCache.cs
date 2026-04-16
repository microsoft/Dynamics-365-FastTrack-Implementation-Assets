using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.Extensions.Caching.Distributed;

namespace TraceParserWeb.Services.Authentication
{
    /// <summary>
    /// A cookie-based implementation of IDistributedCache that stores MSAL tokens
    /// in encrypted, chunked cookies. This allows tokens to survive app restarts
    /// without requiring external distributed cache infrastructure.
    /// </summary>
    public class CookieDistributedCache(
        IHttpContextAccessor httpContextAccessor,
        IDataProtectionProvider dataProtectionProvider,
        ILogger<CookieDistributedCache> logger)
        : IDistributedCache
    {
        private readonly IDataProtector _protector = dataProtectionProvider.CreateProtector("MSAL.TokenCache.v1");

        // Cookie size limit (leaving room for overhead)
        private const int MaxChunkSize = 3500;
        private const string CookiePrefix = ".MSAL.Token.";
        private const string ChunkCountSuffix = ".Count";

        public byte[]? Get(string key)
        {
            
            var context = httpContextAccessor.HttpContext;
            if (context == null) return null;

            try
            {
                var cookieKey = GetCookieKey(key);
                var countKey = cookieKey + ChunkCountSuffix;

                // Check if we have chunked data
                if (context.Request.Cookies.TryGetValue(countKey, out var countStr)
                    && int.TryParse(countStr, out var chunkCount))
                {
                    var chunks = new List<string>();
                    for (int i = 0; i < chunkCount; i++)
                    {
                        var chunkKey = $"{cookieKey}.{i}";
                        if (context.Request.Cookies.TryGetValue(chunkKey, out var chunk))
                        {
                            chunks.Add(chunk);
                        }
                        else
                        {
                            logger.LogWarning("Missing chunk {ChunkIndex} for key {Key}", i, key);
                            return null;
                        }
                    }

                    var combined = string.Join("", chunks);
                    var decrypted = _protector.Unprotect(combined);
                    var entry = JsonSerializer.Deserialize<CacheEntry>(decrypted);

                    if (entry == null) return null;

                    // Check expiration
                    if (entry.AbsoluteExpiration.HasValue &&
                        entry.AbsoluteExpiration.Value < DateTimeOffset.UtcNow)
                    {
                        logger.LogDebug("Cache entry expired for key {Key}", key);
                        // Only attempt to remove if response hasn't started
                        if (!context.Response.HasStarted)
                        {
                            Remove(key);
                        }
                        else
                        {
                            logger.LogDebug("Cannot remove expired entry for key {Key} - response already started, will be cleaned up on next request", key);
                        }
                        return null;
                    }

                    logger.LogDebug("Retrieved token cache entry for key {Key}, size: {Size} bytes",
                        key, entry.Value?.Length ?? 0);
                    return entry.Value;
                }

                // Try single cookie (backward compatibility or small data)
                if (context.Request.Cookies.TryGetValue(cookieKey, out var value))
                {
                    var decrypted = _protector.Unprotect(value);
                    var entry = JsonSerializer.Deserialize<CacheEntry>(decrypted);

                    if (entry == null) return null;

                    if (entry.AbsoluteExpiration.HasValue &&
                        entry.AbsoluteExpiration.Value < DateTimeOffset.UtcNow)
                    {
                        // Only attempt to remove if response hasn't started
                        if (!context.Response.HasStarted)
                        {
                            Remove(key);
                        }
                        else
                        {
                            logger.LogDebug("Cannot remove expired entry for key {Key} - response already started, will be cleaned up on next request", key);
                        }
                        return null;
                    }

                    return entry.Value;
                }
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Failed to retrieve cache entry for key {Key}", key);
            }

            return null;
        }

        public Task<byte[]?> GetAsync(string key, CancellationToken token = default)
        {
            return Task.FromResult(Get(key));
        }

        public void Set(string key, byte[] value, DistributedCacheEntryOptions options)
        {
            var context = httpContextAccessor.HttpContext;
            if (context == null)
            {
                logger.LogWarning("Cannot set cache entry - no HttpContext available");
                return;
            }

            // Can't modify cookies after response has started
            if (context.Response.HasStarted)
            {
                logger.LogWarning("Cannot set cache entry for key {Key} - response already started", key);
                return;
            }

            try
            {
                var entry = new CacheEntry
                {
                    Value = value,
                    AbsoluteExpiration = options.AbsoluteExpiration ??
                        (options.AbsoluteExpirationRelativeToNow.HasValue
                            ? DateTimeOffset.UtcNow.Add(options.AbsoluteExpirationRelativeToNow.Value)
                            : DateTimeOffset.UtcNow.AddHours(24)) // Default 24 hours
                };

                var json = JsonSerializer.Serialize(entry);
                var encrypted = _protector.Protect(json);

                var cookieKey = GetCookieKey(key);
                var cookieOptions = CreateCookieOptions(entry.AbsoluteExpiration);

                // Clear any existing chunks first
                ClearChunks(context, cookieKey);

                if (encrypted.Length <= MaxChunkSize)
                {
                    // Single cookie
                    context.Response.Cookies.Append(cookieKey, encrypted, cookieOptions);
                    logger.LogDebug("Stored token cache entry for key {Key} in single cookie, size: {Size} bytes",
                        key, value.Length);
                }
                else
                {
                    // Chunk the data
                    var chunks = ChunkString(encrypted, MaxChunkSize);
                    for (int i = 0; i < chunks.Count; i++)
                    {
                        var chunkKey = $"{cookieKey}.{i}";
                        context.Response.Cookies.Append(chunkKey, chunks[i], cookieOptions);
                    }

                    // Store chunk count
                    var countKey = cookieKey + ChunkCountSuffix;
                    context.Response.Cookies.Append(countKey, chunks.Count.ToString(), cookieOptions);

                    logger.LogDebug(
                        "Stored token cache entry for key {Key} in {ChunkCount} chunks, total size: {Size} bytes",
                        key, chunks.Count, value.Length);
                }
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Failed to set cache entry for key {Key}", key);
            }
        }

        public Task SetAsync(string key, byte[] value, DistributedCacheEntryOptions options,
            CancellationToken token = default)
        {
            Set(key, value, options);
            return Task.CompletedTask;
        }

        public void Refresh(string key)
        {
            // For cookie-based cache, refresh is a no-op as we don't support sliding expiration
            logger.LogDebug("Refresh called for key {Key} - no-op for cookie cache", key);
        }

        public Task RefreshAsync(string key, CancellationToken token = default)
        {
            Refresh(key);
            return Task.CompletedTask;
        }

        public void Remove(string key)
        {
            var context = httpContextAccessor.HttpContext;
            if (context == null) return;

            // Can't modify cookies after response has started
            if (context.Response.HasStarted)
            {
                logger.LogDebug("Cannot remove cache entry for key {Key} - response already started", key);
                return;
            }

            var cookieKey = GetCookieKey(key);
            ClearChunks(context, cookieKey);

            // Also delete the main cookie
            context.Response.Cookies.Delete(cookieKey);

            logger.LogDebug("Removed token cache entry for key {Key}", key);
        }

        public Task RemoveAsync(string key, CancellationToken token = default)
        {
            Remove(key);
            return Task.CompletedTask;
        }

        private void ClearChunks(HttpContext context, string cookieKey)
        {
            // Can't modify cookies after response has started
            if (context.Response.HasStarted)
            {
                logger.LogDebug("Cannot clear chunks for {CookieKey} - response already started", cookieKey);
                return;
            }

            var countKey = cookieKey + ChunkCountSuffix;

            if (context.Request.Cookies.TryGetValue(countKey, out var countStr)
                && int.TryParse(countStr, out var chunkCount))
            {
                for (int i = 0; i < chunkCount; i++)
                {
                    context.Response.Cookies.Delete($"{cookieKey}.{i}");
                }
                context.Response.Cookies.Delete(countKey);
            }
        }

        private static string GetCookieKey(string key)
        {
            // Create a shorter, safe cookie name from the cache key
            // MSAL keys can be quite long, so we hash them
            using var sha = System.Security.Cryptography.SHA256.Create();
            var hash = sha.ComputeHash(Encoding.UTF8.GetBytes(key));
            var shortKey = Convert.ToBase64String(hash)
                .Replace("+", "-")
                .Replace("/", "_")
                .TrimEnd('=')
                .Substring(0, 16);
            return CookiePrefix + shortKey;
        }

        private static CookieOptions CreateCookieOptions(DateTimeOffset? expiration)
        {
            return new CookieOptions
            {
                HttpOnly = true,
                Secure = true,
                SameSite = SameSiteMode.Lax,
                IsEssential = true,
                Expires = expiration ?? DateTimeOffset.UtcNow.AddHours(24)
            };
        }

        private static List<string> ChunkString(string str, int chunkSize)
        {
            var chunks = new List<string>();
            for (int i = 0; i < str.Length; i += chunkSize)
            {
                chunks.Add(str.Substring(i, Math.Min(chunkSize, str.Length - i)));
            }
            return chunks;
        }

        private class CacheEntry
        {
            public byte[]? Value { get; set; }
            public DateTimeOffset? AbsoluteExpiration { get; set; }
        }
    }
}
