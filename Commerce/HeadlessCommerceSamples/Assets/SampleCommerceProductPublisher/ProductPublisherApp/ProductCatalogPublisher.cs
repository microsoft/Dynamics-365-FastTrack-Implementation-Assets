using Microsoft.Dynamics.Commerce.RetailProxy;
using ProductPublisher.Core.Interface;
using ProductPublisherApp.Adapters;

/// <summary>
/// This class is responsible for handling the products.
/// From here, you can instantiate the adapter(s) to send the products to the target integration point.
namespace ProductPublisherApp
{
    internal class ProductCatalogPublisher : ICatalogPublisher
    {
        public void OnCatalogReadCompleted(long catalogId)
        {
        }

        /// <summary>
        /// Indicates that changed (new or modified) products were found in CSU.
        /// </summary>
        /// <param name="products">The products which were changed.</param>
        /// <param name="pageNumberInCatalog">Page number used while retrieving products from CRT. Can be used by clients for diagnostics purposes.</param>
        /// <param name="catalogId">The catalog ID which contains the changed products.</param>
        /// <returns>The task.</returns>
        /// <remarks>The class which implements this method should expect this method to be called multiple times. The number of times it is called depends on page size used while initializing the Publisher.</remarks>
        public async Task OnChangedProductsFound(IEnumerable<Product> products, int pageNumberInCatalog, long catalogId)
        {
            DestinationAdapter adapter = new();

            ArgumentNullException.ThrowIfNull(nameof(products));

            if (products.Any())
            {
                await adapter.PublishProducts(products);
            }

            await Task.Run(() => { });
        }

        /// <summary>
        /// Indicates that individually deleted products were detected.
        /// </summary>
        /// <param name="ids">Deleted products' IDs.</param>
        public void OnDeleteIndividualProductsRequested(IEnumerable<ListingIdentity> ids)
        {
        }

        public async Task OnActivePricesCompleted(IEnumerable<ProductPrice> produtPrices)
        {
            await Task.Run(() => { });
        }
    }
}
