/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */
using Microsoft.Dynamics.Commerce.RetailProxy;
using ProductPublisher.Core.Helper;
using ProductPublisher.Core.Interface;

namespace ProductPublisher.Core
{
    /// <summary>
    /// Sample publisher class that demonstrates how to publish products and categories. 
    /// </summary>
    public class SamplePublisher :IPublisher
    {
        private readonly int pageSize;
        private ChannelConfiguration? channelConfiguration;
        private ManagerFactory? factory;
        private readonly string clientId= string.Empty;
        private readonly string clientSecret = string.Empty;
        private readonly Uri retailServerUri=default!;
        private readonly string operatingUnitNumber= string.Empty;
        private readonly string authority = string.Empty;
        private readonly string audience = string.Empty;
        private readonly string tenantId = string.Empty;
        private readonly long catalogId =0;
        private readonly bool publishPrices = false;
        private readonly ICatalogPublisher catalogPublisher = default!;
        private readonly IChannelPublisher channelPublisher= default!;
        private readonly string sessionKey = "ReadChangedProductsSession";

        /// <summary>
        /// Sample publisher constructor.
        /// </summary>
        /// <param name="channelPublisher"></param>
        /// <param name="catalogPublisher"></param>
        /// <param name="operatingUnitNumber"></param>
        /// <param name="retailServerUri"></param>
        /// <param name="authority"></param>
        /// <param name="clientId"></param>
        /// <param name="clientSecret"></param>
        /// <param name="audience"></param>
        /// <param name="tenantId"></param>
        public SamplePublisher(IChannelPublisher _channelPublisher,
         ICatalogPublisher _catalogPublisher, string _operatingUnitNumber,
          Uri _retailServerUri, string _authority, string _clientId,
           string _clientSecret, string _audience, string _tenantId,
           long _catalogId,int _pageSize,bool _publishPrices)
        {
            this.operatingUnitNumber = _operatingUnitNumber;
            this.retailServerUri = _retailServerUri;
            this.authority = _authority;
            this.clientId = _clientId;
            this.clientSecret = _clientSecret;
            this.audience = _audience;
            this.tenantId = _tenantId;
            this.catalogId= _catalogId;
            this.catalogPublisher = _catalogPublisher;
            this.channelPublisher = _channelPublisher;
            this.pageSize = _pageSize;
            this.publishPrices = _publishPrices;
        }

        public SamplePublisher()
        {

        }

        /// <summary>
        /// Initialize channel
        /// </summary>
        /// <returns></returns>
        public async Task InitializeChannelConfiguration()
        {
            this.factory = await this.CreateManagerFactory();
            IOrgUnitManager orgUnitManager = this.factory.GetManager<IOrgUnitManager>();
            this.channelConfiguration = await orgUnitManager.GetOrgUnitConfiguration().ConfigureAwait(false);
        }
        /// <summary>
        /// Publishes the channel categories and attributes.
        /// </summary>
        /// <param name="channelPublisher"></param>
        /// <returns></returns>
        /// <exception cref="ArgumentNullException"></exception>
        /// <exception cref="InvalidDataException"></exception>
        public async Task PublishChannel()
        {
            IEnumerable<Category> categories;
            var categoriesInfo = await this.LoadCategories(this.factory!);
            channelPublisher.OnProductCategoriesAvailable(categoriesInfo);
            categories = categoriesInfo.Item1;
            int categoriesCount = categories.Count();

            if (categoriesCount == 0)
            {
                throw new InvalidDataException(string.Format(
                    "Navigation categories count returned is '{0}'. Error details {1}",
                categoriesCount,
                    "The channel doesn't have any categories."));
            }

            IEnumerable<AttributeProduct> productAttributes = await this.LoadProductAttributes(this.factory!);
            channelPublisher.OnProductAttributesAvailable(productAttributes);
            int listingAttributesCount = productAttributes.Count();

            if (listingAttributesCount == 0)
            {
                throw new InvalidDataException(string.Format(
                    "Listing Attributes Count returned is '{0}'. Error details '{1}'",
                    listingAttributesCount,
                    "The channel doesn't have any listing attributes."));
            }


        }
        /// <summary>
        /// Publishes the catalog.
        /// </summary>
        /// <param name="catalogPublisher"></param>
        /// <returns></returns>
        public async Task PublishCatalog()
        {
            List<long> productCatalogIds = new(1);

            IProductManager productManager = this.factory!.GetManager<IProductManager>();

            productCatalogIds.Add(this.catalogId);

            bool deletesFound = await this.DeleteProducts(productCatalogIds, catalogPublisher, productManager);

            ChangedProductsSearchCriteria searchCriteria = new()
            {
                Context = new ProjectionDomain { ChannelId = this.channelConfiguration!.RecordId, CatalogId = this.catalogId },
                Session = new()
            };

            QueryResultSettings productsQuerySettings = new() { Paging = new PagingInfo { Top = this.pageSize, Skip = 0 } };

            try
            {
                PublisherSessionCacheAccessor.TryGetItem<string>(sessionKey, out string? synchronizationToken);
                if (!string.IsNullOrEmpty(synchronizationToken))
                {
                    searchCriteria.SynchronizationToken = synchronizationToken;
                }

                searchCriteria.Session = await productManager.BeginReadChangedProducts(searchCriteria);
                PublisherSessionCacheAccessor.PutItem(this.sessionKey, searchCriteria.Session.NextSynchronizationToken, DateTimeOffset.Now + TimeSpan.FromHours(1));

                if (searchCriteria.Session.TotalNumberOfProducts > 0)
                {
                    int totalProductsCount = 0;

                    foreach (long productCatalogId in productCatalogIds)
                    {
                        // reset counters.
                        searchCriteria.Session.NumberOfProductsRead = 0;
                        searchCriteria.Session.NumberOfProductsReadInCurrentPage = 0;

                        int pageNumberForCatalog = 0;
                        int catalogProductsCount = 0;

                        long numberOfProductsRequested = 0;

                        PagedResult<Product> products;

                        do
                        {
                            productsQuerySettings.Paging.Skip = numberOfProductsRequested;
                            try
                            {
                                products = await productManager.ReadChangedProducts(searchCriteria, skipProductPriceCalculation: false, productsQuerySettings);
                                if (this.publishPrices && products.Any())
                                {
                                    await this.PublishPrices(products.Select(item => item.RecordId).ToList());
                                }

                                List<ListingPublishStatus> statuses = new(products.Count());
                                List<List<ListingPublishStatus>> catalogStatuses = [statuses];
                                foreach (Product product in products)
                                {
                                    ListingPublishStatus publishStatus = this.CreatePublishingStatus(
                                        this.catalogId,
                                        product.RecordId,
                                        this.channelConfiguration.Languages.Single(l => l.IsDefault).LanguageId,
                                        PublishingAction.Publish,
                                        product.RecordId.ToString());

                                    statuses.Add(publishStatus);
                                }
                                foreach (List<ListingPublishStatus> statusesPage in catalogStatuses)
                                {
                                    await productManager.UpdateListingPublishingStatus(statusesPage);
                                }

                            }
                            catch
                            {
                                throw;
                            }

                            int numberOfReadProducts = products.Results.Count();
                            totalProductsCount += numberOfReadProducts;
                            catalogProductsCount += numberOfReadProducts;

                            await catalogPublisher.OnChangedProductsFound(products, pageNumberForCatalog, productCatalogId);
                            pageNumberForCatalog++;
                            numberOfProductsRequested = productsQuerySettings.Paging.Skip.Value + productsQuerySettings.Paging.Top.Value;
                        }
                        while (numberOfProductsRequested < searchCriteria.Session.TotalNumberOfProducts.Value);

                        catalogPublisher.OnCatalogReadCompleted(productCatalogId);
                    }  
                } 
            }
            finally
            {
                //Changing the next synchronization token to empty for ignoring the channel property
                if (!string.IsNullOrEmpty(searchCriteria.Session.NextSynchronizationToken))
                {
                    searchCriteria.Session.NextSynchronizationToken = string.Empty;
                    await productManager.EndReadChangedProducts(searchCriteria.Session);
                }
            }

        }

        public async Task PublishPrices(IEnumerable<long> productsList)
        {
            IProductManager productManager = this.factory!.GetManager<IProductManager>();
            QueryResultSettings activePricesQuerySettings = new() { Paging = new PagingInfo { Top = this.pageSize, Skip = 0 } };
            var productPrices = await productManager.GetActivePrices(new ProjectionDomain()
            {
                CatalogId = this.catalogId,
                ChannelId = this.channelConfiguration!.RecordId
            }, productsList, DateTime.Now, null, null, false, false, false, null, activePricesQuerySettings);
            await catalogPublisher.OnActivePricesCompleted([.. productPrices]);
        }

        /// <summary>
        /// Product manager factory creation.
        /// </summary>
        /// <returns></returns>
        private async Task<ManagerFactory> CreateManagerFactory()
        {
            RetailServerContext retailServerContext = RetailServerContext.Create(retailServerUri, operatingUnitNumber,
                await AuthenticationHelper.GetAuthenticationResult(this.clientId, this.authority, this.clientSecret, this.tenantId, this.audience));
            ManagerFactory factory = ManagerFactory.Create(retailServerContext);
            return factory;
        }

        /// <summary>
        /// Loads the categories and their attributes.
        /// </summary>
        /// <param name="factory"></param>
        /// <returns></returns>
        private async Task<Tuple<IEnumerable<Category>, Dictionary<long, IEnumerable<AttributeCategory>>>> LoadCategories(ManagerFactory factory)
        {
            ////******** Reading categories *****************
            PagingInfo pagingInfo = new(){ Top = this.pageSize, Skip = 0 };
            QueryResultSettings getCategoriesCriteria = new() { Paging = pagingInfo };

            List<Category> categories = [];

            IEnumerable<Category> currentPageCategories;
            ICategoryManager categoryManager = factory.GetManager<ICategoryManager>();
            do
            {
                currentPageCategories = await categoryManager.GetCategories(this.channelConfiguration!.RecordId, null, getCategoriesCriteria);
                categories.AddRange(currentPageCategories);
                getCategoriesCriteria.Paging.Skip = getCategoriesCriteria.Paging.Skip + this.pageSize;
            }
            while (currentPageCategories.Count() == getCategoriesCriteria.Paging.Top);

            // ******* Reading categories' attributes
            QueryResultSettings getCategoryAttributesCriteria = new() { Paging = new PagingInfo { Top = this.pageSize, Skip = 0 } };
            Dictionary<long, IEnumerable<AttributeCategory>> categoryAttributesMap = [];
            foreach (Category category in categories)
            {
                getCategoryAttributesCriteria.Paging.Skip = 0;
                List<AttributeCategory> allCategoryAttributes = [];
                IEnumerable<AttributeCategory> categoryAttributes;
                do
                {
                    categoryAttributes = await categoryManager.GetAttributes(category.RecordId, getCategoryAttributesCriteria);
                    allCategoryAttributes.AddRange(categoryAttributes);
                    getCategoryAttributesCriteria.Paging.Skip = getCategoryAttributesCriteria.Paging.Skip + this.pageSize;
                }
                while (categoryAttributes.Count() == getCategoryAttributesCriteria.Paging.Top);

                categoryAttributesMap.Add(category.RecordId, allCategoryAttributes);
            }

            var result = new Tuple<IEnumerable<Category>, Dictionary<long, IEnumerable<AttributeCategory>>>(categories, categoryAttributesMap);
            return result;
        }
        /// <summary>
        /// Retrieves the product attributes.
        /// </summary>
        /// <param name="factory"></param>
        /// <returns></returns>
        private async Task<IEnumerable<AttributeProduct>> LoadProductAttributes(ManagerFactory factory)
        {
            QueryResultSettings getProductAttributesCriteria = new(){ Paging = new PagingInfo { Top = this.pageSize, Skip = 0 } };
            IProductManager productManager = factory.GetManager<IProductManager>();
            List<AttributeProduct> attributes = [];
            IEnumerable<AttributeProduct> currentAttributePage;
            do
            {
                currentAttributePage = await productManager.GetChannelProductAttributes(getProductAttributesCriteria);
                attributes.AddRange(currentAttributePage);
                getProductAttributesCriteria.Paging.Skip = getProductAttributesCriteria.Paging.Skip + getProductAttributesCriteria.Paging.Top;
            }
            while (currentAttributePage.Count() == getProductAttributesCriteria.Paging.Top);

            return attributes;
        }

        private async Task<bool> DeleteProducts(
              List<long> productCatalogs,
              ICatalogPublisher catalogPublisher,
              IProductManager productManager)
        {
            ArgumentNullException.ThrowIfNull(nameof(productCatalogs));
            ArgumentNullException.ThrowIfNull(nameof(catalogPublisher));

            bool changesDetected = false;

            //Using the default catalog and channel default language
            foreach (long catalog in productCatalogs)
            {
                List<List<ListingPublishStatus>> catalogStatuses = [];
                long skip = 0;
                DeletedListingsResult deletedListingsResult;
                do
                {
                    deletedListingsResult = await productManager.GetDeletedListings(catalog, skip, top: this.pageSize);
                    skip += this.pageSize;

                    if (deletedListingsResult.DeletedListings.Count > 0)
                    {
                        changesDetected = true;
                        catalogPublisher.OnDeleteIndividualProductsRequested(deletedListingsResult.DeletedListings);

                        List<ListingPublishStatus> statuses = new(deletedListingsResult.DeletedListings.Count);
                        catalogStatuses.Add(statuses);
                        foreach (ListingIdentity id in deletedListingsResult.DeletedListings)
                        {
                            ListingPublishStatus publishStatus = this.CreatePublishingStatus(
                                catalog,
                                id.ProductId!.Value,
                                id.LanguageId,
                                PublishingAction.Delete,
                                id.Tag);

                            statuses.Add(publishStatus);
                        }
                    }
                }
                while (deletedListingsResult.HasMorePublishedListings!.Value);

                foreach (List<ListingPublishStatus> statusesPage in catalogStatuses)
                {
                    await productManager.UpdateListingPublishingStatus(statusesPage);
                }
            }

            return changesDetected;
        }

        public ListingPublishStatus CreatePublishingStatus(long catalogId, long listingId, string language, PublishingAction action, string tag)
        {
            ListingPublishStatus publishStatus = new()
            {
                CatalogId = catalogId,
                ChannelId = this.channelConfiguration!.RecordId,
                ChannelListingId = listingId.ToString(),
                LanguageId = language,
                AppliedActionValue = (int)action,
                PublishStatusValue = (int)ListingPublishingActionStatus.Done,
                ListingModifiedDateTime = System.DateTimeOffset.UtcNow,
                ProductId = listingId,
                Tag = tag
            };

            return publishStatus;
        }

    }

}
